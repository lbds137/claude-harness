#!/bin/bash
# Fixture check for tests/replay-hook.sh — self-contained, uses a synthetic
# projects dir, never touches real session logs.
# Usage: tests/replay-hook.probe.sh   (from anywhere)

set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RH="$REPO/tests/replay-hook.sh"

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

mkdir -p "$T/proj-slug"
cat > "$T/proj-slug/session1.jsonl" <<'EOF'
this line is not JSON at all
{"type":"assistant","cwd":"/tmp/fixture-project","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"gh pr view 1 --json title | head -5"}}]}}
{"type":"assistant","cwd":"/tmp/fixture-project","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]}}
{"type":"assistant","cwd":"/tmp/fixture-project","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git status --short"}}]}}
{"type":"assistant","cwd":"/tmp/fixture-project","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}},{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/x"}}]}}
EOF

# Positive control: lossy-pipe-guard blocks this exact shape directly.
jq -n '{tool_name:"Bash",tool_input:{command:"gh pr view 1 --json title | head -5"}}' \
  | env -u CLAUDE_PROJECT_DIR bash "$REPO/plugins/harness/hooks/lossy-pipe-guard.sh" >/dev/null 2>&1
[ $? -ne 0 ] && ok "positive control: lossy-pipe-guard blocks the fixture's gh|head command directly" \
  || bad "positive control: lossy-pipe-guard did not block the fixture command"

out=$("$RH" lossy-pipe-guard --since 1 --slug proj-slug --projects-dir "$T")
echo "$out" | grep -qF "gh pr view 1 --json title | head -5" \
  && ok "blocked command text appears in output" || bad "blocked command text missing"
# 3 original commands + the extra Bash block in the two-tool_use entry = 4;
# the malformed line and the non-Bash (Read) block do not count.
echo "$out" | tail -1 | grep -qxF "replay-hook: lossy-pipe-guard: 1/4 commands blocked across 1 files" \
  && ok "summary line: 1/4 blocked across 1 files (malformed line and non-Bash block skipped, not double-counted)" \
  || bad "summary line: $(echo "$out" | tail -1)"

"$RH" no-such-hook >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "unknown hook name exits 2" || bad "unknown hook name exit=$rc"

out0=$("$RH" lossy-pipe-guard --since 0 --slug proj-slug --projects-dir "$T")
echo "$out0" | tail -1 | grep -qxF "replay-hook: lossy-pipe-guard: 0/0 commands blocked across 0 files" \
  && ok "--since 0 (impossible window) yields 0/0 across 0 files" || bad "--since 0: $(echo "$out0" | tail -1)"

"$RH" lossy-pipe-guard --slug nope --projects-dir "$T" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "--slug nope (nonexistent dir) exits 2" || bad "--slug nope exit=$rc"

exit $fail
