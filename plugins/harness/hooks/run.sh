#!/bin/bash
# Harness hook dispatcher: run.sh <hook-name>
#
# If the project ships its own copy (.claude/hooks/<name>.sh under
# CLAUDE_PROJECT_DIR, else the cwd), exit 0 silently: the project's copy wins
# and is wired by the project's own settings, so running both would double-fire.
# Otherwise exec the plugin's copy with stdin passed through; its exit code,
# stdout and stderr reach the harness unchanged.

NAME="${1:-}"
case "$NAME" in
  '' | */* | .*) echo "run.sh: invalid hook name '$NAME'" >&2; exit 0 ;;
esac

if [ -f "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hooks/$NAME.sh" ]; then
  exit 0
fi

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$DIR/$NAME.sh"
[ -f "$HOOK" ] || { echo "run.sh: no such harness hook '$NAME'" >&2; exit 0; }

export PYTHONDONTWRITEBYTECODE=1
exec bash "$HOOK"
