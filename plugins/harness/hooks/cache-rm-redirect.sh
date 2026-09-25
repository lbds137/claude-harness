#!/bin/bash
# PreToolUse:Bash hook (harness plugin): redirect hand-rolled cache deletion to safe-clean.
#
# Blocks (exit 2) a Bash command that
#   - runs `rm` with a recursive flag on a path named like a regenerable cache
#     (__pycache__, node_modules, .pytest_cache, ...), or
#   - runs `find ... -name <cache> ... -delete` or `-exec rm`,
# and names the safe-clean command to use instead. safe-clean checks each target is inside a git
# repo, isn't a symlink, and holds no tracked file; improvised `rm -rf` checks none of that.
#
# Bypass: put HARNESS_ALLOW_CACHE_RM=1 in the command (the owner approved this specific rm).
# Fail-open: no python3/jq, unparsable input or command → exit 0.

set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0
case "$CMD" in *HARNESS_ALLOW_CACHE_RM=1*) exit 0 ;; esac
# Cheap prefilter: nothing to do unless a cache name appears at all.
case "$CMD" in
  *__pycache__* | *node_modules* | *.pytest_cache* | *.ruff_cache* | *.mypy_cache* | *.turbo* | *htmlcov* | *.coverage*) ;;
  *) exit 0 ;;
esac

HITS=$(CMD="$CMD" python3 - <<'PYEOF'
import os, shlex, sys

CACHES = {"__pycache__", ".pytest_cache", ".ruff_cache", ".mypy_cache",
          "node_modules", ".turbo", "htmlcov", ".coverage"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n"}

try:
    lex = shlex.shlex(os.environ["CMD"], posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    lex.commenters = ""
    tokens = list(lex)
except ValueError:
    sys.exit(0)

# Split into simple commands.
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

def cache_name(arg):
    return os.path.basename(arg.rstrip("/")) in CACHES

hits = []
find_caches = []      # caches a find selects without deleting (may feed `xargs rm`)
xargs_rm = False
for argv in cmds:
    # Skip leading VAR=value assignments and sudo/command wrappers.
    while argv and ("=" in argv[0] and not argv[0].startswith("-") and argv[0].split("=")[0].isidentifier()):
        argv = argv[1:]
    via_xargs = False
    while argv and argv[0] in ("sudo", "command", "nice", "time", "xargs"):
        via_xargs = via_xargs or argv[0] == "xargs"
        argv = argv[1:]
        while via_xargs and argv and argv[0].startswith("-"):
            argv = argv[1:]  # xargs's own flags (-0, -r, ...)
    if not argv:
        continue
    prog = os.path.basename(argv[0])
    if prog == "rm":
        opts = [a for a in argv[1:] if a.startswith("-") and a != "--"]
        recursive = any(a in ("--recursive",) or (not a.startswith("--") and ("r" in a or "R" in a)) for a in opts)
        if recursive:
            hits += [a for a in argv[1:] if not a.startswith("-") and cache_name(a)]
            xargs_rm = xargs_rm or via_xargs
    elif prog == "find":
        deletes = "-delete" in argv or any(
            argv[i] in ("-exec", "-execdir") and i + 1 < len(argv) and os.path.basename(argv[i + 1]) == "rm"
            for i in range(len(argv)))
        names = [argv[i + 1] for i, a in enumerate(argv[:-1])
                 if a in ("-name", "-iname") and argv[i + 1] in CACHES]
        if deletes:
            hits += ["find -name " + n for n in names]
        else:
            find_caches += names

if xargs_rm:
    hits += ["find -name " + n + " | xargs rm" for n in find_caches]

print("\n".join(hits))
PYEOF
) || exit 0

[ -n "$HITS" ] || exit 0

cat >&2 <<EOF
CACHE-RM REDIRECT — use safe-clean for regenerable caches

This command deletes cache folders by hand:
$(printf '%s\n' "$HITS" | sed 's/^/  - /')

Use the checked command instead. It refuses symlinks, anything outside a git repo, and any
folder holding git-tracked files, and it can't touch gitignored data:
  safe-clean <path>...             # e.g. safe-clean node_modules .pytest_cache
  safe-clean --find __pycache__ .  # every __pycache__ under a folder
  safe-clean --dry-run ...         # show what would go
If the owner approved this exact rm, prefix the command with HARNESS_ALLOW_CACHE_RM=1.
EOF
exit 2
