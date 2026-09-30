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

# --- meter points (--points, --until, --by-session) ---
# Fixture extension (after every assertion above has run: m7 shifts the totals).
line m7 2026-09-24T02:06:00Z 0 1 0 > "$P/slugA/s1/subagents/agent-y.jsonl"
# claude-usage's readings log, at the XDG_STATE_HOME default that run()'s env -i leaves unset.
# Key order differs from the real log's lines on purpose; epochs are UTC unix seconds.
RLOG="$T/.local/state/claude-usage/readings.jsonl"; mkdir -p "$(dirname "$RLOG")"
rd() { printf '{"weekly_pct":%s,"epoch":%s,"five_hour_pct":%s,"ts":"2026-09-24"}\n' "$1" "$2" "$3"; }
{ rd 40.0 1790208000 30.0   # 00:00 — last reading at/before the window start (01:15)
  rd 40.0 1790215200 55.0   # 02:00
  rd  5.0 1790218800 80.0   # 03:00 — a weekly reset happened between 02:00 and 03:00
  rd 65.0 1790226000 40.0   # 05:00 — a five-hour reset happened before this
  rd 65.0 1790229600 70.0   # 06:00 — first reading at/after the window end (05:30)
} > "$RLOG"

j=$(run --since 2026-09-24T01:15Z --until 2026-09-24T05:30Z --points --json)
[ "$(jq '.points.weekly_delta == 60' <<<"$j")" = true ] && ok "weekly delta segment-sums to 60, reset segments contribute 0" || bad "weekly delta $(jq .points.weekly_delta <<<"$j")"
[ "$(jq .points.resets_inside.weekly <<<"$j")" = 1 ] && ok "counts the weekly reset inside the window" || bad "weekly resets $(jq -c .points.resets_inside <<<"$j")"
[ "$(jq '.points.five_hour_delta == 80' <<<"$j")" = true ] && ok "five-hour delta 80, its reset segment contributing 0" || bad "5h delta"
[ "$(jq .points.five_hour_usable <<<"$j")" = false ] && ok "marks the 5h figure unusable with a reset inside" || bad "5h usable"
[ "$(jq .points.readings_used <<<"$j")" = 5 ] && [ "$(jq .points.readings_skipped <<<"$j")" = 0 ] && ok "uses all 5 readings, skips none" || bad "readings used/skipped"
printf '{"epoch":"not-a-number","weekly_pct":40.0,"five_hour_pct":1.0}\n' >> "$RLOG"   # JSON-valid, wrong-typed
j2=$(run --since 2026-09-24T01:15Z --until 2026-09-24T05:30Z --points --json)
[ "$?" = 0 ] && [ "$(jq .points.readings_skipped <<<"$j2")" = 1 ] \
  && [ "$(jq '.points.weekly_delta == 60' <<<"$j2")" = true ] \
  && ok "a wrong-typed reading is skipped and the good ones still price" || bad "wrong-typed reading: $(jq -c '.points | {readings_skipped, weekly_delta}' <<<"$j2")"
[ "$(jq -r '.points.edge_left | [.epoch, .distance_s, .extrapolated] | @tsv' <<<"$j")" = "$(printf '1790208000\t4500\tfalse')" ] && ok "edge_left: last reading at/before the start, 4500s away" || bad "edge_left $(jq -c .points.edge_left <<<"$j")"
[ "$(jq -r '.points.edge_right | [.epoch, .distance_s, .extrapolated] | @tsv' <<<"$j")" = "$(printf '1790229600\t1800\tfalse')" ] && ok "edge_right: first reading at/after the end, 1800s away" || bad "edge_right $(jq -c .points.edge_right <<<"$j")"
# With m7 (weight 5) the swept total is 167: slugA 60, slugB 100, -dash-slug 7.
read -r sa sb ds sum <<<"$(jq -r '[.points.by_slug["slugA"], .points.by_slug["slugB"], .points.by_slug["-dash-slug"], ([.points.by_slug[]] | add)] | join(" ")' <<<"$j")"
awk -v a="$sa" -v b="$sb" -v d="$ds" -v s="$sum" 'BEGIN { exit !(a == 21.56 && b == 35.93 && d == 2.51 && s > 59.95 && s < 60.05) }' \
  && ok "per-slug points = share x weekly delta (21.56 / 35.93 / 2.51, sum ~ 60)" || bad "points split $sa $sb $ds $sum"
b=$(run --since 2026-09-24T01:15Z --until 2026-09-24T05:30Z --points --slug slugB --json | jq '.points.by_slug.slugB == 60')
[ "$b" = true ] && ok "--slug shares are of the swept set: the one swept folder takes the full delta" || bad "swept share $b"
run --since 2026-09-24T01:15Z --json | jq -e 'has("points") | not' >/dev/null && ok "without --points no points key (the log is never read)" || bad "points key without --points"
jq -e '.points | has("by_session") | not' <<<"$j" >/dev/null && ok "by_session appears only with --by-session" || bad "by_session without the flag"
j=$(run --since 2026-09-23T00:00Z --until 2026-09-24T02:30Z --points --json)
[ "$(jq -r '.points.edge_left | [.epoch, .distance_s, .extrapolated] | @tsv' <<<"$j")" = "$(printf '1790208000\t86400\ttrue')" ] \
  && ok "no reading at/before the start: first reading stands in, extrapolated, 86400s away" || bad "edge fallback $(jq -c .points.edge_left <<<"$j")"
[ "$(jq .points.readings_used <<<"$j")" = 3 ] && ok "the points window clips to the readings inside it (3)" || bad "clipped readings"
run --since 2026-09-23T00:00Z --until 2026-09-24T02:30Z --points | grep -q "points are approximate" && ok "warns when the nearest reading sits far from the window edge" || bad "approximate warning"
j=$(run --since 2026-09-24T01:15Z --until 2026-09-24T05:30Z --points --by-session --json)
# m1 (s1.jsonl, 50) and every slugA subagent file (5 or 10 with m2) land on a parent
# session key, never their own. m2 exists identically in s0/ and s1/ subagents and the
# dedupe is first-wins, so which of slugA/s0 or slugA/s1 gets it follows scan order —
# only the slugA total (60 of 167 weighted = 21.56 of the delta) is pinned, plus every
# slugA key being a parent session.
[ "$(jq '([.points.by_session | to_entries[] | select(.key | startswith("slugA/")) | .value] | add) - 21.56 | if . < 0 then -. else . end < 0.01' <<<"$j")" = true ] \
  && [ "$(jq '[.points.by_session | to_entries[] | select(.key | startswith("slugA/")) | .key] | all(test("^slugA/s[01]$"))' <<<"$j")" = true ] \
  && ok "--by-session: subagent files attach to their parent session's key, never their own" || bad "by-session $(jq -c .points.by_session <<<"$j")"
u=$(run --since 2026-09-24T01:15Z --until 2026-09-24T02:03Z --json | jq .total_weighted)
[ "$u" = 50 ] && ok "--until bounds the sweep without --points: usage after the cutoff excluded (50)" || bad "until $u"
run --since 2026-09-24T01:15Z --until 2026-09-24T05:30Z --points | grep -q "meter points: weekly +60.0 pts" && ok "text output renders the meter-points block" || bad "text points"
mv "$RLOG" "$T/readings.saved"
run --since 2026-09-24T01:15Z --points >/dev/null 2>"$T/err"
[ $? != 0 ] && grep -q "no usable readings in $RLOG" "$T/err" \
  && ok "missing readings log + --points: exits non-zero, names the path" || bad "missing log: $(cat "$T/err")"
exit $fail
