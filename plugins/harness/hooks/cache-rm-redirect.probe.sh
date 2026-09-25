#!/bin/bash
# Fixture check for cache-rm-redirect.sh: exit-code table over the command shapes that matter.
# Usage: hooks/cache-rm-redirect.probe.sh   (from anywhere)

set -uo pipefail
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cache-rm-redirect.sh"
fail=0
run() { # $1 want-rc, $2 command
  local rc
  jq -nc --arg c "$2" '{tool_input: {command: $c}}' | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$1" ]; then echo "ok   [$rc]: $2"; else echo "FAIL [$rc want $1]: $2"; fail=1; fi
}

# Blocked: hand-rolled cache deletion.
run 2 'rm -rf node_modules'
run 2 'rm -r plugins/harness/hooks/lib/__pycache__/'
run 2 'cd sub && rm -Rf .pytest_cache .ruff_cache'
run 2 'rm --recursive --force htmlcov'
run 2 'find . -name __pycache__ -type d -exec rm -rf {} +'
run 2 'find . -name "__pycache__" -delete'
run 2 'find . -name __pycache__ -print0 | xargs -0 rm -rf'
run 2 'sudo rm -rf ./node_modules'
# Allowed.
run 0 'safe-clean node_modules'
run 0 'safe-clean --find __pycache__ .'
run 0 'rm -rf build/tmp-output'
run 0 'rm node_modules.txt'
run 0 'rm .coverage'
run 0 'git rm -r --cached node_modules'
run 0 'ls node_modules | head'
run 0 'find . -name __pycache__ -type d'
run 0 'HARNESS_ALLOW_CACHE_RM=1 rm -rf node_modules'
run 0 'echo "rm -rf node_modules is risky"'
run 0 ''
exit $fail
