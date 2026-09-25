#!/bin/bash
# Run every probe (plugins/harness/hooks/*.probe.sh and tests/*.probe.sh) one at a time.
# Prints PASS/FAIL per probe; exits non-zero if any probe fails.
# On failure the probe's own output is shown.
#
# Usage: tests/run-probes.sh   (from anywhere)

set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS="$REPO/plugins/harness/hooks"
export PYTHONDONTWRITEBYTECODE=1

shopt -s nullglob
PROBES=("$HOOKS"/*.probe.sh "$REPO"/tests/*.probe.sh)
if [ ${#PROBES[@]} -eq 0 ]; then
  echo "no probes found under $HOOKS" >&2
  exit 1
fi

pass=0
failed=()
for p in "${PROBES[@]}"; do
  name=$(basename "$p" .probe.sh)
  out=$(bash "$p" </dev/null 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/      /'
    failed+=("$name")
  fi
done

echo "---"
echo "$pass passed, ${#failed[@]} failed (of ${#PROBES[@]})"
[ ${#failed[@]} -eq 0 ]
