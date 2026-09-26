#!/bin/bash
# Fixture check for tests/replay-stop-hook.sh — self-contained synthetic
# projects dir, never touches real session logs.
# Usage: tests/replay-stop-hook.probe.sh   (from anywhere)

set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RSH="$REPO/tests/replay-stop-hook.sh"
BQ="$REPO/plugins/harness/hooks/blocking-question-channel-check.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mkdir -p "$T/proj-slug" "$T/other-slug"

# RECORDED-mode fixture (a stop_hook_summary is present): two bq trips, one
# tesg trip, zero promise-ledger-check trips, one live block, across 5 turn
# ends, PLUS one mid-turn injection (a Skill-directory content block, the
# observed real shape) that a summary-blind rule would wrongly count as a
# 6th turn end.
cat > "$T/proj-slug/session1.jsonl" <<'EOF'
this line is not JSON at all
{"type":"user","message":{"role":"user","content":"start"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Should I proceed with the rename?"}]}}
{"type":"system","subtype":"stop_hook_summary","hookCount":3}
{"type":"user","message":{"role":"user","content":"yes"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Running it."}]}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x"}]}}
{"type":"system","subtype":"stop_hook_summary","hookCount":3}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Another Claude session sent a message: hi"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Done, nothing else needed."}]}}
{"type":"system","subtype":"stop_hook_summary","hookCount":3}
{"type":"user","message":{"role":"user","content":"one more"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Which branch should I use?"}]}}
{"type":"system","subtype":"stop_hook_summary","hookCount":3}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback:\n[bash \"/x/run.sh\" blocking-question-channel-check]: BLOCKING QUESTION ..."}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Should I stop here?"}]}}
{"type":"system","subtype":"stop_hook_summary","hookCount":3}
EOF

# INFERRED-mode fixture (no stop_hook_summary anywhere, and no feedback/
# "Noted" tail): the same injection now IS a turn end (no summary to require),
# and the cross-session entry right after it is NOT one (no assistant entry
# occurred between them) — the purpose canary for the mode split.
cat > "$T/other-slug/session2.jsonl" <<'EOF'
this line is not JSON at all
{"type":"user","message":{"role":"user","content":"start"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Should I proceed with the rename?"}]}}
{"type":"user","message":{"role":"user","content":"yes"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Running it."}]}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: /x"}]}}
{"type":"user","isMeta":true,"message":{"role":"user","content":"Another Claude session sent a message: hi"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Done, nothing else needed."}]}}
{"type":"user","message":{"role":"user","content":"one more"}}
{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Which branch should I use?"}]}}
EOF

# Positive controls: blocking-question-channel-check.sh trips directly on a
# 2-line transcript ending in a question, and is silenced by stop_hook_active.
printf '%s\n%s\n' \
  '{"type":"user","message":{"role":"user","content":"start"}}' \
  '{"type":"assistant","isSidechain":false,"cwd":"/tmp/fixture-project","message":{"role":"assistant","content":[{"type":"text","text":"Should I proceed with the rename?"}]}}' \
  > "$T/two-line.jsonl"

jq -n --arg tp "$T/two-line.jsonl" '{session_id:"x",transcript_path:$tp,cwd:"/tmp/fixture-project",hook_event_name:"Stop",stop_hook_active:false}' \
  | env -u CLAUDE_PROJECT_DIR bash "$BQ" >/dev/null 2>&1
[ $? -ne 0 ] && ok "positive control: bq trips on the 2-line fixture with stop_hook_active:false" \
  || bad "positive control: bq did not trip with stop_hook_active:false"

jq -n --arg tp "$T/two-line.jsonl" '{session_id:"x",transcript_path:$tp,cwd:"/tmp/fixture-project",hook_event_name:"Stop",stop_hook_active:true}' \
  | env -u CLAUDE_PROJECT_DIR bash "$BQ" >/dev/null 2>&1
[ $? -eq 0 ] && ok "positive control: bq is silenced by stop_hook_active:true" \
  || bad "positive control: bq did not exit 0 with stop_hook_active:true"

# The three Stop hooks against the RECORDED fixture (5 turn ends: A-E; A and D
# trip bq, B trips tesg, none trip promise-ledger-check; the injection at
# line 9 is skipped, not a 6th turn end).
out=$("$RSH" blocking-question-channel-check --since 1 --slug proj-slug --projects-dir "$T")
echo "$out" | tail -1 | grep -qxF "replay-stop-hook: blocking-question-channel-check: 2/5 turn ends tripped across 1 files (0/0 inferred in 0 files without Stop records); 1 live blocks in the logs" \
  && ok "bq summary: 2/5 tripped across 1 files, 0 inferred; 1 live block" || bad "bq summary: $(echo "$out" | tail -1)"
echo "$out" | grep -qF "text: Should I proceed with the rename?" \
  && ok "bq tripped section carries the closing question text" || bad "bq tripped text missing"
echo "$out" | grep -qxF "entry: proj-slug/session1.jsonl:5" \
  && ok "bq tripped section carries the cut entry's slug/file:line" || bad "bq tripped entry line missing"
echo "$out" | grep -qF "mode: recorded" \
  && ok "bq tripped section names its mode" || bad "bq tripped section missing mode: line"
# E's closing text now ends on "?" too (a stop_hook_active mirroring check: E
# is silenced because D's ending entry was a "Stop hook feedback:" entry) —
# still 2/5, and no tripped section at EOF.
echo "$out" | tail -1 | grep -qxF "replay-stop-hook: blocking-question-channel-check: 2/5 turn ends tripped across 1 files (0/0 inferred in 0 files without Stop records); 1 live blocks in the logs" \
  && ok "bq stays 2/5 with E's closing text also ending in '?'" || bad "bq summary changed: $(echo "$out" | tail -1)"
echo "$out" | grep -qxF "entry: proj-slug/session1.jsonl:EOF" \
  && bad "bq tripped at EOF — stop_hook_active mirroring is not suppressing E" \
  || ok "no EOF tripped section — stop_hook_active mirroring silences E"

out=$("$RSH" turn-end-shape-gate --since 1 --slug proj-slug --projects-dir "$T")
echo "$out" | tail -1 | grep -qxF "replay-stop-hook: turn-end-shape-gate: 1/5 turn ends tripped across 1 files (0/0 inferred in 0 files without Stop records); 0 live blocks in the logs" \
  && ok "tesg summary: 1/5 tripped across 1 files, 0 inferred; 0 live blocks" || bad "tesg summary: $(echo "$out" | tail -1)"
echo "$out" | grep -qxF "entry: proj-slug/session1.jsonl:11" \
  && ok "tesg trip's entry: line is the cross-session entry, not the injection" || bad "tesg tripped entry line missing/wrong"

out=$("$RSH" promise-ledger-check --since 1 --slug proj-slug --projects-dir "$T")
echo "$out" | tail -1 | grep -qxF "replay-stop-hook: promise-ledger-check: 0/5 turn ends tripped across 1 files (0/0 inferred in 0 files without Stop records); 0 live blocks in the logs" \
  && ok "promise-ledger-check summary: 0/5 tripped across 1 files, 0 inferred; 0 live blocks" || bad "promise-ledger-check summary: $(echo "$out" | tail -1)"

# Purpose canary: other-slug is INFERRED (no stop_hook_summary anywhere) — the
# injection now IS a turn end, the cross-session entry right after it is not
# (no assistant entry between them), and no feedback entry means 0 live blocks.
out=$("$RSH" blocking-question-channel-check --since 1 --slug other-slug --projects-dir "$T")
echo "$out" | tail -1 | grep -qxF "replay-stop-hook: blocking-question-channel-check: 2/4 turn ends tripped across 1 files (2/4 inferred in 1 files without Stop records); 0 live blocks in the logs" \
  && ok "purpose canary: other-slug (INFERRED, no summaries) — 2/4 tripped across 1 files, all 4 inferred; 0 live blocks" \
  || bad "purpose canary: $(echo "$out" | tail -1)"

# Argument handling, mirroring replay-hook.probe.sh's exit-code checks.
"$RSH" lossy-pipe-guard --slug proj-slug --projects-dir "$T" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "a PreToolUse hook name (lossy-pipe-guard) is refused, exit 2" || bad "lossy-pipe-guard exit=$rc"

"$RSH" no-such-hook --slug proj-slug --projects-dir "$T" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "unknown hook name exits 2" || bad "unknown hook name exit=$rc"

out0=$("$RSH" blocking-question-channel-check --since 0 --slug proj-slug --projects-dir "$T")
echo "$out0" | tail -1 | grep -qxF "replay-stop-hook: blocking-question-channel-check: 0/0 turn ends tripped across 0 files (0/0 inferred in 0 files without Stop records); 0 live blocks in the logs" \
  && ok "--since 0 (impossible window) yields 0/0 across 0 files; 0 live blocks" || bad "--since 0: $(echo "$out0" | tail -1)"

"$RSH" blocking-question-channel-check --slug nope --projects-dir "$T" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "--slug nope (nonexistent dir) exits 2" || bad "--slug nope exit=$rc"

# Crash safety: a per-file replay failure (here, permission denied) must fail
# loudly — exit 1, a stderr line naming the file, and NO summary line, so a
# partial count is never mistaken for a total.
mkdir -p "$T/crash-slug"
BLOCKED="$T/crash-slug/blocked.jsonl"
echo '{"type":"user","message":{"role":"user","content":"start"}}' > "$BLOCKED"
chmod 000 "$BLOCKED"
CRASH_ERR="$T/crash.err"
crash_out=$("$RSH" blocking-question-channel-check --since 1 --slug crash-slug --projects-dir "$T" 2>"$CRASH_ERR")
crash_rc=$?
chmod 644 "$BLOCKED"
[ "$crash_rc" -eq 1 ] && ok "crash safety: exit 1 on a permission-denied file" || bad "crash safety exit=$crash_rc"
echo "$crash_out" | grep -q "turn ends tripped" \
  && bad "crash safety: a summary line printed on stdout despite the crash" \
  || ok "crash safety: no summary line printed on stdout"
grep -qE '^replay-stop-hook: replay failed on .*/crash-slug/blocked\.jsonl \(python exit [0-9]+\)$' "$CRASH_ERR" \
  && ok "crash safety: stderr names the failing file and python's exit code" \
  || bad "crash safety: stderr missing/wrong: $(cat "$CRASH_ERR")"

exit $fail
