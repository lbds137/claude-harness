#!/bin/bash
# tests/replay-hook.sh — replay one Bash-matching harness hook against the
# Bash commands recorded in local Claude Code session JSONLs, and report what
# it would have blocked.
#
# SECRETS WARNING: the commands this prints are pulled verbatim from real
# recorded sessions and can contain tokens, paths, or other secrets. This
# output is local working material only — never paste it into a commit, PR,
# or tracked doc (same boundary as the session-mining corpus).
#
# Usage: tests/replay-hook.sh <hook-name> [--since N] [--slug SLUG] [--projects-dir DIR]
#   <hook-name>          a hook under plugins/harness/hooks/ (e.g. lossy-pipe-guard);
#                        an unknown name is refused with a one-line error, exit 2.
#   --since N            only JSONLs modified in the last N days (default 7).
#   --slug SLUG          only ~/.claude/projects/SLUG/*.jsonl and
#                        SLUG/*/subagents/*.jsonl (default: every slug).
#   --projects-dir DIR   the projects root (default $HOME/.claude/projects); lets
#                        a probe point this at a fixture instead of real logs.
#
# Mechanism: pulls every Bash tool_use command from .message.content[]
# entries (.type=="tool_use", .name=="Bash", .input.command) and builds the
# PreToolUse JSON the harness sends ({"tool_name":"Bash",
# "tool_input":{"command":...},"cwd":<entry's cwd, else $HOME>,
# "hook_event_name":"PreToolUse"}) in the SAME jq pass, so a huge command
# never round-trips through a shell argv. Fed to the hook script DIRECTLY
# (`bash plugins/harness/hooks/<hook-name>.sh`, not via run.sh — a project
# shipping its own `.claude/hooks/<name>.sh` override makes run.sh exit 0 for
# every command, reading as "nothing blocked").
#
# Subagent transcripts (<slug>/<session>/subagents/*.jsonl) are replayed too
# and labelled "(subagent)"; other nested JSONLs (mined-corpus reports) are
# not.
#
# A "block" is a non-zero exit from the hook script. Output: one section per
# blocked command (command, first 200 chars, one line; slug; the hook's
# stderr/stdout, first 3 lines), then a summary line:
#   replay-hook: <hook-name>: <blocked>/<total> commands blocked across <files> files
# Nothing else is printed. Exit 0 even with blocks — a report, not a gate.
#
# Streams each file through one jq pass (malformed lines skipped, not fatal);
# 10+ MB session logs are normal. ~20ms/command observed (one hook spawn per
# command) — a 7-day all-slug run is ~10-12 min (subagent logs roughly double
# the commands; ~17 ms/command measured), not the ~14 min a
# three-jq-spawns-per-command version cost.

set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS_DIR="$REPO/plugins/harness/hooks"

HOOK_NAME="${1:-}"
if [ -z "$HOOK_NAME" ] || [[ "$HOOK_NAME" == --* ]]; then
  echo "replay-hook: usage: replay-hook.sh <hook-name> [--since N] [--slug SLUG] [--projects-dir DIR]" >&2
  exit 2
fi
shift

if [ ! -f "$HOOKS_DIR/$HOOK_NAME.sh" ]; then
  echo "replay-hook: unknown hook '$HOOK_NAME'" >&2
  exit 2
fi

SINCE=7
SLUG=""
PROJECTS_DIR="$HOME/.claude/projects"

need_value() { [ $# -ge 2 ] || { echo "replay-hook: $1 needs a value" >&2; exit 2; }; }
while [ $# -gt 0 ]; do
  case "$1" in
    --since) need_value "$@"; SINCE="$2"; shift 2 ;;
    --slug) need_value "$@"; SLUG="$2"; shift 2 ;;
    --projects-dir) need_value "$@"; PROJECTS_DIR="$2"; shift 2 ;;
    *) echo "replay-hook: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

[[ "$SINCE" =~ ^[0-9]+$ ]] || { echo "replay-hook: --since needs a whole number of days" >&2; exit 2; }

# Strip a trailing slash: otherwise ${f#"$PROJECTS_DIR"/} below fails to
# strip (double slash mismatch) and slug_name comes out empty.
PROJECTS_DIR=${PROJECTS_DIR%/}

if [ -n "$SLUG" ]; then
  SEARCH_ROOT="$PROJECTS_DIR/$SLUG"
  MAXDEPTH=1
else
  SEARCH_ROOT="$PROJECTS_DIR"
  MAXDEPTH=2
fi
[ -d "$SEARCH_ROOT" ] || { echo "replay-hook: no such directory: $SEARCH_ROOT" >&2; exit 2; }

TOTAL=0
BLOCKED=0
FILES=0

# Epoch cutoff, not `find -mtime`: -mtime's day-bucket semantics differ across
# find implementations (bfs matches -mtime -0; GNU find's docs say it
# shouldn't). --since 0 means "modified after right now" — no existing file
# can satisfy that, so it deterministically yields 0 files.
CUTOFF=$(( $(date +%s) - SINCE * 86400 ))
FILE_LIST=$( {
  find "$SEARCH_ROOT" -maxdepth "$MAXDEPTH" -type f -name '*.jsonl' 2>/dev/null
  find "$SEARCH_ROOT" -mindepth $((MAXDEPTH + 2)) -maxdepth $((MAXDEPTH + 2)) -type f -regex '.*/subagents/[^/]*\.jsonl' 2>/dev/null
} )

while IFS= read -r f; do
  [ -z "$f" ] && continue
  mtime=$(stat -c %Y "$f" 2>/dev/null) || continue
  [ "$mtime" -gt "$CUTOFF" ] || continue
  FILES=$((FILES + 1))
  rel=${f#"$PROJECTS_DIR"/}
  case "$rel" in
    */*) slug_name=${rel%%/*} ;;
    *) slug_name="(root)" ;;
  esac
  slug_label="slug: $slug_name"
  case "$rel" in
    */subagents/*) slug_label="$slug_label (subagent)" ;;
  esac

  while IFS= read -r payload; do
    [ -z "$payload" ] && continue
    TOTAL=$((TOTAL + 1))

    out=$(printf '%s' "$payload" | env -u CLAUDE_PROJECT_DIR bash "$HOOKS_DIR/$HOOK_NAME.sh" 2>&1)
    rc=$?

    if [ "$rc" -ne 0 ]; then
      BLOCKED=$((BLOCKED + 1))
      cmd=$(jq -r '.tool_input.command' <<<"$payload")
      cmd="${cmd//$'\n'/ }"; cmd="${cmd//$'\r'/ }"; cmd="${cmd//$'\t'/ }"
      echo "--- blocked ---"
      echo "command: ${cmd:0:200}"
      echo "$slug_label"
      printf '%s\n' "$out" | head -3
      echo
    fi
  done < <(jq -Rc --arg home "$HOME" '
      (fromjson? // empty) |
      (.cwd // $home) as $cwd |
      (.message.content // [])[]? | select(.type=="tool_use" and .name=="Bash" and .input.command != null) |
      {tool_name:"Bash", tool_input:{command:.input.command}, cwd:$cwd, hook_event_name:"PreToolUse"}
    ' "$f")
done <<<"$FILE_LIST"

echo "replay-hook: $HOOK_NAME: $BLOCKED/$TOTAL commands blocked across $FILES files"
exit 0
