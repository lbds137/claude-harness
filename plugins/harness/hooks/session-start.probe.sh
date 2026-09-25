#!/bin/bash
# Fixture check for session-start.sh. Uses a temp CLAUDE_PLUGIN_ROOT and a temp
# user rules dir (HARNESS_USER_RULES_DIR), so it never depends on the real ones.
#
# Usage: hooks/session-start.probe.sh   (from anywhere)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$SCRIPT_DIR/session-start.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/root/rules" "$TMP/rules-linked" "$TMP/rules-empty"
printf '# Core\nfixture\n' > "$TMP/root/rules/core.md"
ln -s "$TMP/root/rules/core.md" "$TMP/rules-linked/harness-core.md"
printf 'unrelated\n' > "$TMP/rules-empty/other.md"

fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; [ -n "${2:-}" ] && printf '      got: %s\n' "$2"; fail=1; }

run() { # $1 source, $2 user rules dir → sets OUT, RC
  OUT=$(jq -nc --arg s "$1" '{session_id: "probe", source: $s}' \
    | CLAUDE_PLUGIN_ROOT="$TMP/root" HARNESS_USER_RULES_DIR="$2" bash "$HOOK" 2>/dev/null)
  RC=$?
}
ctx() { jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT" 2>/dev/null; }
valid() {
  jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | type == "string")' \
    <<<"$OUT" >/dev/null 2>&1
}

for src in startup clear; do
  run "$src" "$TMP/rules-linked"
  [ "$RC" = 0 ] && [ -z "$OUT" ] && ok "$src with rules linked: no output" || bad "$src linked: expected empty" "$OUT"
  run "$src" "$TMP/rules-empty"
  if [ "$RC" = 0 ] && valid && ctx | grep -q 'core rules are not loaded' && ctx | grep -qF "$TMP/root/rules/core.md"; then
    ok "$src without the link: one-line warning naming the ln command"
  else
    bad "$src without link: expected warning JSON" "$OUT"
  fi
done

run compact "$TMP/rules-linked"
if [ "$RC" = 0 ] && valid && ctx | grep -q 'POST-COMPACTION RECOVERY' && ! ctx | grep -q '# Core'; then
  ok "compact: checklist only, core.md not injected"
else
  bad "compact: expected checklist without core.md" "$OUT"
fi

run resume "$TMP/rules-empty"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "resume: no output" || bad "resume: expected empty output" "$OUT"

run "" "$TMP/rules-empty"
[ "$RC" = 0 ] && [ -z "$OUT" ] && ok "missing source: no output" || bad "missing source: expected empty" "$OUT"

# Output must stay far below Claude Code's ~10 KB hook-output preview cliff.
run compact "$TMP/rules-linked"
[ "${#OUT}" -lt 4000 ] && ok "compact output is ${#OUT} bytes (< 4000)" || bad "compact output too large: ${#OUT} bytes"

exit $fail
