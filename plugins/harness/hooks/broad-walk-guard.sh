#!/bin/bash
# PreToolUse:Bash hook (harness plugin): block filesystem walks rooted at /, the home folder or ~/gdrive.
#
# Blocks (exit 2) a Bash command that runs find, du, fd, rg, or grep -r/-R starting at /,
# /home, the home folder, or anything under ~/gdrive. On this machine ~/gdrive is an rclone
# mount: a walk that reaches it lists the whole Drive over the network and can wedge the
# mount in uninterruptible I/O. `-prune` doesn't help a walk of /: it still crawls every
# other tree first. Relative paths resolve against the tool call's cwd.
# Allowed: find with -maxdepth 2 or less (it never goes past the mount's top level).
#
# Bypass: put HARNESS_ALLOW_BROAD_WALK=1 in the command (the walk is meant to be broad).
# Fail-open: no python3/jq, unparsable input or command → exit 0.

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0
case "$CMD" in *HARNESS_ALLOW_BROAD_WALK=1*) exit 0 ;; esac
# Cheap prefilter: nothing to do unless a walking command appears at all.
case "$CMD" in
  *find* | *du* | *grep* | *rg* | *fd*) ;;
  *) exit 0 ;;
esac
CWD=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null) || CWD=""

HITS=$(CMD="$CMD" CWD="$CWD" python3 - <<'PYEOF'
import os, shlex, sys

HOME = os.path.realpath(os.path.expanduser("~"))
GDRIVE = os.path.join(HOME, "gdrive")
BROAD = {"/", "/home", HOME}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n"}
CWD = os.environ.get("CWD") or os.getcwd()

try:
    lex = shlex.shlex(os.environ["CMD"], posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    tokens = list(lex)
except ValueError:
    sys.exit(0)

cmds, cur = [], []
for t in tokens:
    if t in SEPARATORS or set(t) <= set(";&|()"):
        if cur:
            cmds.append(cur)
        cur = []
    else:
        cur.append(t)
if cur:
    cmds.append(cur)

def broad(path):
    for var in ("${HOME}", "$HOME"):
        if path == var or path.startswith(var + "/"):
            path = HOME + path[len(var):]
    path = os.path.expanduser(path)
    glob = min((path.find(c) for c in "*?[" if c in path), default=-1)
    if glob >= 0:  # the shell expands it: judge the folder it expands in (/* walks /home too)
        path = os.path.dirname(path[:glob]) or "."
    if not os.path.isabs(path):
        path = os.path.join(CWD, path)
    path = os.path.normpath(path)
    return path in BROAD or path == GDRIVE or path.startswith(GDRIVE + "/")

def positionals(args):
    return [a for a in args if not a.startswith("-")]

hits = []
for argv in cmds:
    while argv and "=" in argv[0] and not argv[0].startswith("-") and argv[0].split("=")[0].isidentifier():
        argv = argv[1:]
    while argv and argv[0] in ("sudo", "command", "nice", "time", "timeout", "ionice"):
        argv = argv[1:]
        while argv and (argv[0].startswith("-") or argv[0][:1].isdigit()):
            argv = argv[1:]  # the wrapper's own flags and timeout's duration
    if not argv:
        continue
    prog, args = os.path.basename(argv[0]), argv[1:]
    roots = []
    if prog == "find":
        i = 0
        while i < len(args) and args[i] in ("-H", "-L", "-P"):
            i += 1
        while i < len(args) and not args[i].startswith(("-", "(", "!")):
            roots.append(args[i])
            i += 1
        if "-maxdepth" in args:
            j = args.index("-maxdepth")
            if j + 1 < len(args) and args[j + 1].isdigit() and int(args[j + 1]) <= 2:
                roots = []
    elif prog == "du":
        roots = positionals(args)
    elif prog in ("fd", "fdfind"):
        roots = positionals(args)[1:]  # the first is the pattern
    elif prog == "rg":
        pos = positionals(args)
        roots = pos if any(a in ("-e", "--regexp", "-f", "--file") for a in args) else pos[1:]
    elif prog in ("grep", "egrep", "fgrep", "ugrep"):
        short = [a for a in args if a.startswith("-") and not a.startswith("--")]
        recursive = any("r" in a or "R" in a for a in short) or any(
            a in ("--recursive", "--dereference-recursive") for a in args)
        if recursive:
            pos = positionals(args)
            roots = pos if any(a == "-e" or a.startswith("--regexp") for a in args) else pos[1:]
    hits += [prog + " " + r for r in roots if broad(r)]

print("\n".join(hits))
PYEOF
) || exit 0

[ -n "$HITS" ] || exit 0

cat >&2 <<EOF
BROAD-WALK GUARD — this walk starts at /, the home folder, or inside ~/gdrive

$(printf '%s\n' "$HITS" | sed 's/^/  - /')

~/gdrive is an rclone mount of the whole Google Drive: a walk that reaches it lists the Drive
over the network and can wedge the mount. Start the walk where the thing lives instead:
  the project folder, or ~/Documents/dev-docs for environment files;
  Go modules: ~/go/pkg/mod (missing one: go mod download -json <mod>@<ver>);
  mise tools: ~/.local/share/mise; commands on PATH: command -v <name>.
If a broad walk is really meant, prefix the command with HARNESS_ALLOW_BROAD_WALK=1.
EOF
exit 2
