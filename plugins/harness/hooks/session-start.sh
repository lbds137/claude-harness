#!/bin/bash
# SessionStart hook (harness plugin).
#
# The core rules (rules/core.md) are NOT injected here: Claude Code shows hook
# output over ~10 KB only as a 2 KB preview, and core.md is larger. They load as
# a user-level rule instead (~/.claude/rules/harness-core.md -> rules/core.md;
# see the README). This hook only:
# - startup / clear: warns in one line if that rules link is missing.
# - compact: adds the post-compaction recovery checklist (the failure class
#   where re-suggested settings, dropped promises and lost work-stack pointers
#   keep recurring). Adapted from Tzurot's session-start.sh.
# - resume: outputs nothing.
#
# Output is built with jq (never hand-escaped). Fail-open: no jq, or nothing to
# say, means a silent exit 0. A project's own .claude/hooks/session-start.sh
# takes precedence via run.sh.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SOURCE=$(jq -r '.source // empty' <<<"$INPUT" 2>/dev/null || echo "")

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RULES_DIR="${HARNESS_USER_RULES_DIR:-$HOME/.claude/rules}"

TEXT=""
case "$SOURCE" in
  startup | clear)
    core=$(readlink -f "$PLUGIN_ROOT/rules/core.md" 2>/dev/null)
    linked=""
    for f in "$RULES_DIR"/*.md; do
      [ -e "$f" ] && [ "$(readlink -f "$f")" = "$core" ] && linked=1 && break
    done
    [ -n "$linked" ] || TEXT="The harness plugin's core rules are not loaded: link them with  ln -s \"$PLUGIN_ROOT/rules/core.md\" \"$RULES_DIR/harness-core.md\"  (tell the owner; it takes effect in the next session)."
    ;;
  compact)
    TEXT=$(cat <<'EOF'
POST-COMPACTION RECOVERY (structural checklist — act before new work):
0. Undelivered reports FIRST: if the compaction summary names a user-facing
   report, answer, or completion message that was never delivered, deliver it
   in the FIRST reply — before any tool calls.
1. Session settings: recover effort level / permission mode from pre-compaction
   state; do NOT re-suggest settings that were already active. The env block's
   MODEL line may be stale after an in-session /model switch — verify the
   driver model via the session JSONL's per-message `.message.model` field
   before asserting it, and never flag a mismatch from the env block alone.
2. Open promises and asks: grep the session JSONL under
   ~/.claude/projects/<project-slug>/ for "I'll" and unanswered user questions
   before re-deriving or guessing at lost state.
3. Work-stack pointer: resume the interrupted task at its resume point; a
   side-quest does not clear the main line.
4. Re-read the project's rules and your role file / handoff notes.
   Auto-loaded content never counts as Read for editing — Edit/Write requires
   a fresh Read of any file first.
EOF
)
    ;;
esac

[ -n "$TEXT" ] || exit 0

jq -n --arg ctx "$TEXT" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
