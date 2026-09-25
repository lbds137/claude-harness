#!/bin/bash
# Fixture check for bin/session-extract against a synthetic session file.
# Usage: tests/session-extract.probe.sh   (from anywhere)

set -uo pipefail
SE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/harness/bin/session-extract"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

S="$T/abc.jsonl"
cat > "$S" <<'EOF'
{"type":"user","timestamp":"2026-09-01T00:00:00Z","message":{"content":"old turn"}}
{"type":"user","timestamp":"2026-09-24T01:00:00Z","message":{"content":"please fix the parser"}}
{"type":"user","timestamp":"2026-09-24T01:00:01Z","isMeta":true,"message":{"content":"meta noise"}}
{"type":"assistant","timestamp":"2026-09-24T01:00:02Z","message":{"content":[{"type":"thinking","thinking":"secret thoughts"},{"type":"text","text":"On it."},{"type":"tool_use","name":"Bash","input":{"command":"grep -r foo ~"}}]}}
{"type":"user","timestamp":"2026-09-24T01:00:03Z","message":{"content":[{"type":"tool_result","is_error":true,"content":"blocked by broad-walk-guard"},{"type":"text","text":"array-form turn"}]}}
{"type":"user","timestamp":"2026-09-24T01:00:04Z","message":{"content":[{"type":"tool_result","is_error":false,"content":"fine output"}]}}
{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-24T01:00:05Z","content":"wait, not that folder"}
EOF
"$SE" --since 2026-09-20T00:00 "$T/out" "$S" > "$T/log"; rc=$?
O="$T/out/abc.txt"; A="$T/out/abc.agent.txt"
[ $rc = 0 ] && ok "exits 0" || bad "exit $rc"
grep -q "please fix the parser" "$O" && grep -q "array-form turn" "$O" && ok "owner lens keeps string and array user turns" || bad "user turns"
grep -q "old turn" "$O" && bad "--since let an old turn through" || ok "--since drops the old turn"
grep -q "meta noise" "$O" && bad "isMeta leaked" || ok "drops isMeta entries"
grep -q "\[mid-turn\] ===" "$O" && grep -q "wait, not that folder" "$O" && ok "unions mid-turn queued messages" || bad "mid-turn"
grep -q "On it." "$A" && grep -q "tool Bash: grep -r foo ~" "$A" && ok "agent lens has text and a tool stub" || bad "agent text/stub"
grep -q "tool-error: blocked by broad-walk-guard" "$A" && ok "agent lens keeps the errored tool result" || bad "tool-error"
grep -q "fine output\|secret thoughts" "$A" && bad "agent lens leaked a clean result or thinking" || ok "drops clean results and thinking"
grep -q "abc…: 2 user blocks, 1 mid-turn, 1 agent blocks, 1 tool calls, 1 tool errors" "$T/log" && ok "count line" || bad "count line: $(cat "$T/log")"
"$SE" "$T/out" "$T/missing.jsonl" 2>/dev/null; [ $? = 1 ] && ok "missing file exits 1" || bad "missing file"
"$SE" --since 2026-09-24T01:00-04:00 "$T/o2" "$S" 2>/dev/null; [ $? = 2 ] && ok "--since rejects an offset" || bad "--since offset"
"$SE" --since 2026-09-24T01:00Z "$T/o3" "$S" >/dev/null && grep -q "please fix the parser" "$T/o3/abc.txt" \
  && ok "--since with a trailing Z keeps entries inside that minute" || bad "--since Z minute"
out=$("$SE" --help 2>&1); [ $? = 0 ] && grep -q "Usage:" <<< "$out" && grep -q "zero count is shown" <<< "$out" \
  && ok "--help prints the whole usage and exits 0" || bad "--help"
"$SE" "$T/o4" >/dev/null 2>&1; [ $? = 2 ] && ok "too few arguments exits 2" || bad "too few args"
exit $fail
