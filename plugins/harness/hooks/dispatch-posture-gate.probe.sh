#!/bin/bash
# Fixture check for dispatch-posture-gate.sh — run after ANY edit to the hook.
#
# Builds a throwaway CLAUDE_PROJECT_DIR fixture and a throwaway ack file
# (via HARNESS_DISPATCH_ACK_FILE) so the probe never reads or mutates the
# real ack state. Each case that needs a "fresh ack" starts from an
# empty/absent ack file. Every case sets HARNESS_DISPATCH_SRC_RE to the probe
# regex below except the opt-in cases, which pass it explicitly.
#
# Usage: bash plugins/harness/hooks/dispatch-posture-gate.probe.sh   (from anywhere)

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HOOK="$SCRIPT_DIR/dispatch-posture-gate.sh"

TMPDIR_PROBE=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR_PROBE"; }
trap cleanup EXIT

FIXTURE="$TMPDIR_PROBE/fixture"
mkdir -p "$FIXTURE/services/x" "$FIXTURE/packages/y" "$FIXTURE/docs" "$FIXTURE/.claude/worktrees/w1/services/x"

# The opt-in regex the probe's project "sets": Tzurot's original scope.
PROBE_RE='^(services|packages)/.+\.(ts|tsx|js|jsx|mjs|cjs|mts|cts|py)$'

FAILURES=0

# run <expected-exit> <label> <tool_name> <file_path> <ack_file> [project_dir]
run() {
  local expected="$1" label="$2" tool="$3" path="$4" ack="$5" project="${6:-$FIXTURE}"
  jq -n --arg t "$tool" --arg p "$path" '{tool_name:$t,tool_input:{file_path:$p}}' \
    | CLAUDE_PROJECT_DIR="$project" HARNESS_DISPATCH_ACK_FILE="$ack" HARNESS_DISPATCH_SRC_RE="$PROBE_RE" \
      "$HOOK" >/dev/null 2>&1
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    printf 'PASS  (exit %d)  %s\n' "$actual" "$label"
  else
    printf 'FAIL  (exit %d, expected %d)  %s\n' "$actual" "$expected" "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

# run_sized <expected-exit> <label> <payload-json> <ack_file> [project_dir] [src_re]
# The 6th arg overrides HARNESS_DISPATCH_SRC_RE; the literal `-` means UNSET.
run_sized() {
  # `${6-...}` (no colon): an EMPTY sixth arg stays empty, it is the env-empty case.
  local expected="$1" label="$2" payload="$3" ack="$4" project="${5:-$FIXTURE}" re="${6-$PROBE_RE}"
  if [ "$re" = "-" ]; then
    printf '%s' "$payload" \
      | env -u HARNESS_DISPATCH_SRC_RE CLAUDE_PROJECT_DIR="$project" HARNESS_DISPATCH_ACK_FILE="$ack" \
        "$HOOK" >/dev/null 2>&1
  else
    printf '%s' "$payload" \
      | CLAUDE_PROJECT_DIR="$project" HARNESS_DISPATCH_ACK_FILE="$ack" HARNESS_DISPATCH_SRC_RE="$re" \
        "$HOOK" >/dev/null 2>&1
  fi
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    printf 'PASS  (exit %d)  %s\n' "$actual" "$label"
  else
    printf 'FAIL  (exit %d, expected %d)  %s\n' "$actual" "$expected" "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

# lines <n> — a string of n newline-separated lines, with NO trailing newline.
lines() {
  local n="$1" i out=""
  for ((i = 1; i <= n; i++)); do out+="line $i"$'\n'; done
  printf '%s' "${out%$'\n'}"
}

# lines_nl <n> <varname> — the same n lines, but WITH a trailing newline. This
# is the ordinary shape of a block copied out of a file, and the count must not
# treat that final newline as a sixth line. It assigns to the variable NAMED by
# $2: command substitution strips trailing newlines, so `$(lines_nl 5)` would
# silently receive the no-trailing-newline shape and test nothing.
lines_nl() {
  printf -v "$2" '%s\n' "$(lines "$1")"
}

edit_payload() {
  jq -cn --arg p "$1" --arg o "$2" --arg n "$3" \
    '{tool_name:"Edit",tool_input:{file_path:$p,old_string:$o,new_string:$n}}'
}

write_payload() {
  jq -cn --arg p "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$p,content:$c}}'
}

SRC="$FIXTURE/services/x/a.ts"

# === opt-in (the harness-specific part) =======================================
# The hook is OFF unless HARNESS_DISPATCH_SRC_RE is set: every project that has
# not opted in must see no change, whatever the edit.

# --- case O1: env UNSET, 50-line Write to a matching-looking path → no-op ----
ACK_O1="$TMPDIR_PROBE/ack_o1"
run_sized 0 "env unset: 50-line Write to services/x/a.ts is a no-op" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O1" "$FIXTURE" "-"
[ ! -e "$ACK_O1" ] && printf 'PASS  (no ack file)  env unset: nothing recorded\n' \
  || { printf 'FAIL  env unset: ack file was written\n'; FAILURES=$((FAILURES + 1)); }

# --- case O2: env set to the EMPTY string → same no-op -----------------------
ACK_O2="$TMPDIR_PROBE/ack_o2"
run_sized 0 "env empty: 50-line Write to services/x/a.ts is a no-op" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O2" "$FIXTURE" ""

# --- case O3: env set, same 50-line Write → hard block -----------------------
ACK_O3="$TMPDIR_PROBE/ack_o3"
run_sized 2 "env set: 50-line Write to services/x/a.ts blocks" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O3"

# --- case O4: env set to a regex the path does NOT match → passes ------------
ACK_O4="$TMPDIR_PROBE/ack_o4"
run_sized 0 "env set to ^lib/: 50-line Write to services/x/a.ts passes (no match)" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O4" "$FIXTURE" '^lib/.*\.ts$'

# --- case O5: the regex is matched against the PROJECT-RELATIVE path ---------
# `^services/` can only match the relative form; the absolute form starts with /.
ACK_O5="$TMPDIR_PROBE/ack_o5"
run_sized 2 "regex ^services/ matches the project-relative path (absolute input)" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O5" "$FIXTURE" '^services/'
ACK_O5B="$TMPDIR_PROBE/ack_o5b"
run_sized 2 "regex ^services/ matches a relative file_path too" \
  "$(write_payload "services/x/a.ts" "$(lines 50)")" "$ACK_O5B" "$FIXTURE" '^services/'

# --- case O5c..f: path normalization (realpath -m on both sides) -------------
# Each is a 50-line Write that must BLOCK under the opted-in regex.
ACK_O5C="$TMPDIR_PROBE/ack_o5c"
run_sized 2 "trailing-slash project dir still matches" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O5C" "$FIXTURE/"
ACK_O5D="$TMPDIR_PROBE/ack_o5d"
run_sized 2 "docs/../services/x/a.ts scope escape is normalized and blocks" \
  "$(write_payload "$FIXTURE/docs/../services/x/a.ts" "$(lines 50)")" "$ACK_O5D"
ACK_O5E="$TMPDIR_PROBE/ack_o5e"
run_sized 2 ".claude/worktrees/../../services/x/a.ts forged exemption blocks" \
  "$(write_payload "$FIXTURE/.claude/worktrees/../../services/x/a.ts" "$(lines 50)")" "$ACK_O5E"
LINKDIR="$TMPDIR_PROBE/link-to-fixture"
ln -s "$FIXTURE" "$LINKDIR"
ACK_O5F="$TMPDIR_PROBE/ack_o5f"
run_sized 2 "symlinked project dir vs realpath file_path blocks" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O5F" "$LINKDIR"

# --- case O6: an invalid regex fails open ------------------------------------
ACK_O6="$TMPDIR_PROBE/ack_o6"
run_sized 0 "invalid regex '(' fails open" \
  "$(write_payload "$SRC" "$(lines 50)")" "$ACK_O6" "$FIXTURE" '('

# --- case O7: a subagent's edit (agent_id in the hook input) is exempt -------
ACK_O7="$TMPDIR_PROBE/ack_o7"
P_O7=$(jq -cn --arg p "$SRC" --arg c "$(lines 50)" \
  '{tool_name:"Write",agent_id:"a1b2c3",agent_type:"harness:implementer",tool_input:{file_path:$p,content:$c}}')
run_sized 0 "agent_id present: 50-line Write passes (subagent exempt)" "$P_O7" "$ACK_O7"
# agent_type ALONE is an `--agent` main thread, not a subagent: still gated.
P_O7B=$(jq -cn --arg p "$SRC" --arg c "$(lines 50)" \
  '{tool_name:"Write",agent_type:"driver",tool_input:{file_path:$p,content:$c}}')
run_sized 2 "agent_type without agent_id: 50-line Write still blocks" "$P_O7B" "$ACK_O7"

# --- case O8: agent_id EMPTY is not a subagent → still gated -----------------
ACK_O8="$TMPDIR_PROBE/ack_o8"
P_O8=$(jq -cn --arg p "$SRC" --arg c "$(lines 50)" \
  '{tool_name:"Write",agent_id:"",tool_input:{file_path:$p,content:$c}}')
run_sized 2 "agent_id empty string: 50-line Write still blocks" "$P_O8" "$ACK_O8"

# --- case O9: env unset + NON-JSON stdin → exit 0 (never reaches jq) ---------
ACK_O9="$TMPDIR_PROBE/ack_o9"
run_sized 0 "env unset + non-JSON stdin exits 0" "this is not json" "$ACK_O9" "$FIXTURE" "-"

# --- case O10: two fixtures at the same branch+HEAD share one ack file --------
# PROJECT_DIR is part of the ack key, so each blocks once on its own.
GITA="$TMPDIR_PROBE/gita"; GITB="$TMPDIR_PROBE/gitb"
mkdir -p "$GITA/services/x"
git -C "$GITA" init -q -b probe
git -C "$GITA" -c user.email=probe@probe -c user.name=probe commit -q --allow-empty -m one
cp -r "$GITA" "$GITB"
[ "$(git -C "$GITA" rev-parse HEAD)" = "$(git -C "$GITB" rev-parse HEAD)" ] || echo "WARN: fixtures differ in HEAD"
ACK_O10="$TMPDIR_PROBE/ack_o10"
run 2 "shared ack file: fixture A blocks once" "Edit" "$GITA/services/x/a.ts" "$ACK_O10" "$GITA"
run 2 "shared ack file: fixture B (same branch+HEAD) still blocks once" "Edit" "$GITB/services/x/a.ts" "$ACK_O10" "$GITB"
run 0 "shared ack file: fixture A retry passes" "Edit" "$GITA/services/x/a.ts" "$ACK_O10" "$GITA"

# --- case O11: empty payloads measure 0 lines → ack path (2 then 0) ----------
ACK_O11="$TMPDIR_PROBE/ack_o11"
P_O11=$(jq -cn --arg p "$SRC" '{tool_name:"MultiEdit",tool_input:{file_path:$p,edits:[]}}')
run_sized 2 "MultiEdit edits:[] blocks once (ack path)" "$P_O11" "$ACK_O11"
run_sized 0 "MultiEdit edits:[] retry passes" "$P_O11" "$ACK_O11"
ACK_O11B="$TMPDIR_PROBE/ack_o11b"
P_O11B=$(write_payload "$SRC" "")
run_sized 2 "Write content:\"\" blocks once (ack path)" "$P_O11B" "$ACK_O11B"
run_sized 0 "Write content:\"\" retry passes" "$P_O11B" "$ACK_O11B"

# === scope and ack path (ported from Tzurot's probe) =========================

# --- case 1: fresh ack, Edit to a services/*.ts path → blocks ---------------
ACK1="$TMPDIR_PROBE/ack1"
run 2 "fresh ack: Edit to services/x/a.ts" "Edit" "$SRC" "$ACK1"

# --- case 2: same call again, now acked → passes -----------------------------
run 0 "same call again (acked) passes" "Edit" "$SRC" "$ACK1"

# --- case 2b: a NEW COMMIT re-arms the gate (HEAD is part of the ack key) ----
GITFIX="$TMPDIR_PROBE/gitfix"
mkdir -p "$GITFIX/services/x"
git -C "$GITFIX" init -q -b probe
git -C "$GITFIX" -c user.email=probe@probe -c user.name=probe commit -q --allow-empty -m one
ACK2B="$TMPDIR_PROBE/ack2b"
run 2 "git fixture: fresh ack blocks" "Edit" "$GITFIX/services/x/a.ts" "$ACK2B" "$GITFIX"
run 0 "git fixture: same HEAD acked passes" "Edit" "$GITFIX/services/x/a.ts" "$ACK2B" "$GITFIX"
git -C "$GITFIX" -c user.email=probe@probe -c user.name=probe commit -q --allow-empty -m two
run 2 "git fixture: NEW COMMIT re-arms the block" "Edit" "$GITFIX/services/x/a.ts" "$ACK2B" "$GITFIX"

# --- case 3: worktree-exempt path → passes -----------------------------------
ACK3="$TMPDIR_PROBE/ack3"
run 0 "worktree-exempt path passes" "Edit" "$FIXTURE/.claude/worktrees/w1/services/x/a.ts" "$ACK3"

# --- case 4: docs path → passes (not services|packages) ----------------------
ACK4="$TMPDIR_PROBE/ack4"
run 0 "docs/a.md passes" "Edit" "$FIXTURE/docs/a.md" "$ACK4"

# --- case 5: Write tool, fresh ack, packages/*.ts → blocks -------------------
ACK5="$TMPDIR_PROBE/ack5"
run 2 "fresh ack: Write to packages/y/b.ts" "Write" "$FIXTURE/packages/y/b.ts" "$ACK5"

# --- case 5b: .mjs under packages/ is gated too --------------------------------
ACK5B="$TMPDIR_PROBE/ack5b"
run 2 "fresh ack: Edit to packages/y/c.mjs" "Edit" "$FIXTURE/packages/y/c.mjs" "$ACK5B"

# --- case 5c: MultiEdit is gated like Edit/Write -------------------------------
ACK5C="$TMPDIR_PROBE/ack5c"
run 2 "fresh ack: MultiEdit to services/x/a.ts" "MultiEdit" "$SRC" "$ACK5C"

# --- case 6: tool_name = Bash → passes ----------------------------------------
ACK6="$TMPDIR_PROBE/ack6"
run 0 "tool_name=Bash passes" "Bash" "$SRC" "$ACK6"

# --- case 7: path outside the fixture root → passes ---------------------------
ACK7="$TMPDIR_PROBE/ack7"
run 0 "path outside fixture root passes" "Edit" "/some/other/root/services/x/a.ts" "$ACK7"

# --- case 8: the worktree IS the project root → passes ------------------------
# A dispatched worker runs with CLAUDE_PROJECT_DIR set to its own worktree, so
# the path's project-relative form is a plain `services/...` and only the
# ABSOLUTE-path check can exempt it. Case 3 exits earlier (its relative form
# starts with `.claude/`), so without this case the exemption branch can be
# deleted with the probe still fully green.
WT_ROOT="$TMPDIR_PROBE/main/.claude/worktrees/agent-1"
mkdir -p "$WT_ROOT/services/x"
ACK8="$TMPDIR_PROBE/ack8"
run 0 "worktree AS project root passes" "Edit" "services/x/a.ts" "$ACK8" "$WT_ROOT"

# === size measurement (the 5-line inline exemption, measured) ================
# The cases above pass no old_string/new_string, so they measure 0 lines and
# exercise the ack path. These drive the size branch, which sits BEFORE the ack
# logic: over five touched lines is a hard block with no ack recorded, so the
# retry blocks too.

# --- case i: a 3-line Edit → blocks once, passes on retry (ack path) ---------
ACK_I="$TMPDIR_PROBE/ack_i"
P_I=$(edit_payload "$SRC" "$(lines 3)" "$(lines 3)")
run_sized 2 "3-line Edit: blocks once (ack path)" "$P_I" "$ACK_I"
run_sized 0 "3-line Edit: retry passes (acked)" "$P_I" "$ACK_I"

# --- case i-b: exactly 5 lines is INSIDE the exemption -----------------------
ACK_IB="$TMPDIR_PROBE/ack_ib"
P_IB=$(edit_payload "$SRC" "$(lines 5)" "$(lines 5)")
run_sized 2 "5-line Edit: blocks once (still the ack path)" "$P_IB" "$ACK_IB"
run_sized 0 "5-line Edit: retry passes (boundary is >5, not >=5)" "$P_IB" "$ACK_IB"

# --- case i-c: 6 lines is the first over-size value --------------------------
ACK_IC="$TMPDIR_PROBE/ack_ic"
P_IC=$(edit_payload "$SRC" "$(lines 6)" "$(lines 6)")
run_sized 2 "6-line Edit: hard block" "$P_IC" "$ACK_IC"
run_sized 2 "6-line Edit: retry blocks AGAIN (no ack)" "$P_IC" "$ACK_IC"

# --- case i-d: 5 lines WITH a trailing newline is still inside the exemption -
ACK_ID="$TMPDIR_PROBE/ack_id"
lines_nl 5 FIVE_NL
P_ID=$(edit_payload "$SRC" "$FIVE_NL" "$FIVE_NL")
run_sized 2 "5-line Edit + trailing newline: blocks once (ack path)" "$P_ID" "$ACK_ID"
run_sized 0 "5-line Edit + trailing newline: retry passes (not counted as 6)" "$P_ID" "$ACK_ID"

# --- case i-e: 6 lines with a trailing newline is still the first over-size --
ACK_IE="$TMPDIR_PROBE/ack_ie"
lines_nl 6 SIX_NL
P_IE=$(edit_payload "$SRC" "$SIX_NL" "$SIX_NL")
run_sized 2 "6-line Edit + trailing newline: hard block" "$P_IE" "$ACK_IE"
run_sized 2 "6-line Edit + trailing newline: retry blocks AGAIN (no ack)" "$P_IE" "$ACK_IE"

# --- case ii: a 20-line Edit → blocks, and blocks again on retry -------------
ACK_II="$TMPDIR_PROBE/ack_ii"
P_II=$(edit_payload "$SRC" "$(lines 20)" "$(lines 20)")
run_sized 2 "20-line Edit: hard block" "$P_II" "$ACK_II"
run_sized 2 "20-line Edit: retry blocks AGAIN (no ack recorded)" "$P_II" "$ACK_II"

# --- case ii-b: size is the MAX of old/new, not either alone -----------------
ACK_IIB="$TMPDIR_PROBE/ack_iib"
run_sized 2 "20-line pure insertion (empty old_string): hard block" \
  "$(edit_payload "$SRC" "" "$(lines 20)")" "$ACK_IIB"
ACK_IIC="$TMPDIR_PROBE/ack_iic"
run_sized 2 "20-line pure deletion (empty new_string): hard block" \
  "$(edit_payload "$SRC" "$(lines 20)" "")" "$ACK_IIC"

# --- case iii: a Write of 40 lines → blocks twice ----------------------------
ACK_III="$TMPDIR_PROBE/ack_iii"
P_III=$(write_payload "$FIXTURE/packages/y/b.ts" "$(lines 40)")
run_sized 2 "40-line Write: hard block" "$P_III" "$ACK_III"
run_sized 2 "40-line Write: retry blocks AGAIN" "$P_III" "$ACK_III"

# --- case iii-b: MultiEdit sums its edits over the limit ---------------------
ACK_IIIB="$TMPDIR_PROBE/ack_iiib"
P_IIIB=$(jq -cn --arg p "$SRC" --arg s "$(lines 3)" \
  '{tool_name:"MultiEdit",tool_input:{file_path:$p,
     edits:[{old_string:$s,new_string:$s},{old_string:$s,new_string:$s},{old_string:$s,new_string:$s}]}}')
run_sized 2 "MultiEdit 3x3 lines (sum 9): hard block" "$P_IIIB" "$ACK_IIIB"
run_sized 2 "MultiEdit 3x3 lines: retry blocks AGAIN" "$P_IIIB" "$ACK_IIIB"

# --- case iv: the worktree-path exemption still wins over a 20-line edit -----
ACK_IV="$TMPDIR_PROBE/ack_iv"
run_sized 0 "20-line Edit under .claude/worktrees/ still passes" \
  "$(edit_payload "$FIXTURE/.claude/worktrees/w1/services/x/a.ts" "$(lines 20)" "$(lines 20)")" \
  "$ACK_IV"

# --- case iv-b: a 20-line docs edit is still out of scope --------------------
ACK_IVB="$TMPDIR_PROBE/ack_ivb"
run_sized 0 "20-line Edit to docs/a.md still passes (out of scope)" \
  "$(edit_payload "$FIXTURE/docs/a.md" "$(lines 20)" "$(lines 20)")" "$ACK_IVB"

# --- case iv-c: the worktree AS project root, over-size → still passes -------
ACK_IVC="$TMPDIR_PROBE/ack_ivc"
run_sized 0 "20-line Edit with the worktree AS project root passes" \
  "$(jq -cn --arg o "$(lines 20)" --arg n "$(lines 20)" \
    '{tool_name:"Edit",tool_input:{file_path:"services/x/a.ts",old_string:$o,new_string:$n}}')" \
  "$ACK_IVC" "$WT_ROOT"

echo "failures: $FAILURES"
exit $FAILURES
