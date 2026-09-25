#!/bin/bash
# Fixture check for broad-walk-guard.sh: exit-code table over the command shapes that matter.
# Usage: hooks/broad-walk-guard.probe.sh   (from anywhere)

set -uo pipefail
HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/broad-walk-guard.sh"
fail=0
run() { # $1 want-rc, $2 command, $3 cwd (default: a project folder)
  local rc
  jq -nc --arg c "$2" --arg d "${3:-$HOME/Projects/claude-harness}" '{tool_input: {command: $c}, cwd: $d}' |
    bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "$1" ]; then echo "ok   [$rc]: $2 (in ${3:-project})"; else echo "FAIL [$rc want $1]: $2"; fail=1; fi
}

# Blocked: walks of /, /home, the home folder or the Drive mount.
run 2 'find / -name errors.go'
run 2 'find / -path /home/deck/gdrive -prune -o -name "*.go" -print 2>/dev/null | head'
run 2 'find ~ -name foo'
run 2 'find $HOME -type f'
run 2 'find "${HOME}/" -newer x'
run 2 'find /home -name x'
run 2 'find ~/gdrive/Books -name "*.pdf"'
run 2 'cd /tmp && find -L / -name x'
run 2 'du -sh ~'
run 2 'du -sh /* 2>/dev/null'  # the shell expands /* to every top-level folder
run 2 'du -sh ~/* | sort -h'
run 0 'du -sh ./*'
run 2 'grep -rn TODO ~'
run 2 'grep -R foo /'
run 2 'rg pattern ~'
run 2 'fd errors.go /'
run 2 'sudo find / -xdev -name x'
run 2 'timeout 60 find / -name x'
run 2 'find . -name x' "$HOME"
run 2 'du -sh .' "$HOME/gdrive"
# Allowed.
run 0 'find . -name "*.go"'
run 0 'find ~/Projects/claude-harness -name "*.sh"'
run 0 'find ~/go/pkg/mod -maxdepth 3 -name errors.go'
run 0 'find / -maxdepth 1 -type d'
run 0 'find ~ -maxdepth 2 -name "*.md"'
run 0 'du -sh /tmp/node-compile-cache'
run 0 'grep -n foo ~/.bashrc'
run 0 'grep foo /etc/hosts'
run 0 'grep -rn TODO .'
run 0 'rg -n pattern ~/Projects'
run 0 'ls ~/gdrive'
run 0 'echo "find / is dangerous"'
run 0 'git log --grep=find'
run 0 'HARNESS_ALLOW_BROAD_WALK=1 find / -name x'
run 0 ''
exit $fail
