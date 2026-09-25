#!/bin/bash
# Fixture check for bin/usage-sweep against a throwaway projects dir.
# Usage: tests/usage-sweep.probe.sh   (from anywhere)

set -uo pipefail
US="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/harness/bin/usage-sweep"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

line() { # id ts in out cache_read [block]
  printf '{"type":"assistant","timestamp":"%s","requestId":"r-%s","message":{"id":"%s","model":"m","content":[{"type":"%s"}],"usage":{"input_tokens":%s,"output_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' \
    "$2" "$1" "$1" "${6:-text}" "$3" "$4" "$5"
}
P="$T/projects"; mkdir -p "$P/slugA/s1/subagents" "$P/slugA/mined-corpus" "$P/slugB"
{ line m0 2026-01-01T00:00:00Z 999 0 0     # before the window
  line m1 2026-09-24T02:00:00Z 10 2 100 thinking   # output_tokens grows as the reply streams:
  line m1 2026-09-24T02:00:00Z 10 2 100 text       # the reply counts once, at its largest (6)
  line m1 2026-09-24T02:00:00Z 10 6 100 tool_use
  printf '{"type":"assistant","timestamp":"2026-09-24T03:00:00Z","message":{"usage"\n'  # half-written tail
} > "$P/slugA/s1.jsonl"
line m2 2026-09-24T02:05:00Z 0 1 0 > "$P/slugA/s1/subagents/agent-x.jsonl"
mkdir -p "$P/slugA/s0/subagents"   # the same agent file carried into a second session: counted once
line m2 2026-09-24T02:05:00Z 0 1 0 > "$P/slugA/s0/subagents/agent-x.jsonl"
mkdir -p "$P/-dash-slug"; line m5 2026-09-24T04:00:00Z 7 0 0 > "$P/-dash-slug/s.jsonl"
line m3 2026-09-24T02:05:00Z 5000 0 0 > "$P/slugA/mined-corpus/copy.jsonl"
line m4 2026-09-24T04:00:00Z 100 0 0 > "$P/slugB/s2.jsonl"

run() { env -i HOME="$T" PATH=/usr/bin:/bin CLAUDE_PROJECTS_DIR="$P" "$US" "$@"; }
j=$(run --since 2026-09-24T01:15Z --json)
total=$(jq .total_weighted <<<"$j")
# 162 = m1 at its largest output (50) + m2 once across both files (5) + m4 (100) + m5 (7).
# First-seen usage would give 142; per-file dedupe 167.
[ "$total" = 162 ] && ok "one count per reply at its largest output, across files; skips mined-corpus and pre-window (162)" || bad "total $total, want 162"
[ "$(jq '[.main_weighted,.subagent_weighted]|join(",")' -r <<<"$j")" = "157,5" ] && ok "splits main vs subagent" || bad "split $(jq -c '[.main_weighted,.subagent_weighted]' <<<"$j")"
[ "$(jq .unparseable_lines <<<"$j")" = 1 ] && ok "counts the half-written line" || bad "unparseable"
[ "$(jq .meter <<<"$j")" = null ] && ok "runs without claude-usage on PATH" || bad "meter"
n=$(run --since 2026-09-24T01:15Z --json --no-dedupe | jq .total_weighted)
[ "$n" = 227 ] && ok "--no-dedupe counts every line (227)" || bad "no-dedupe $n"
b=$(run --since 2026-09-24T01:15Z --json --slug slugB | jq .total_weighted)
[ "$b" = 100 ] && ok "--slug scopes to one folder" || bad "slug $b"
d=$(run --since 2026-09-24T01:15Z --json --slug -dash-slug | jq .total_weighted)
[ "$d" = 7 ] && ok "--slug takes a dash-leading slug as a separate argument" || bad "dash slug $d"
run --since 2026-09-24T01:15Z --slug nope >/dev/null 2>&1; [ $? != 0 ] && ok "rejects an unknown slug" || bad "unknown slug"
run >/dev/null 2>&1; [ $? != 0 ] && ok "refuses to guess a window with no meter and no --since" || bad "no-window"
run --since 2026-09-24T01:15Z | grep -q "TOTAL weighted 0.0M" && ok "text output renders" || bad "text output"
exit $fail
