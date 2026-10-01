#!/bin/bash
# PreToolUse hook (matcher: Bash) — as a `git commit` is about to run, scan the
# STAGED diff's added lines for claim-shaped assertions — "always populated",
# "never null", "cannot happen", "guaranteed to", "only ever".
#
# Those phrasings state what a field or value HOLDS at runtime, which is a
# claim only the producer can settle (seyag core.md § Don't present
# speculation as fact — the producer is authoritative on what a field HOLDS).
# A doc comment states the author's intent at writing time and drifts silently;
# near-identical sibling interfaces make a plausible-looking declaration weak
# evidence.
#
# `cannot be` is NARROWED to a following value token (null/empty/set/…) rather
# than matching bare. Unqualified, it fired on ordinary design prose about code
# STRUCTURE — "cannot be collapsed into one", "cannot be extracted", "cannot be
# reused" — which asserts nothing about runtime and has no producer to cite.
# That noise is not free: a guard whose output is mostly false positives trains
# the reader to skim past the true ones. The other arms (`always populated`,
# `never null`, `cannot happen`) are already runtime-claim-shaped and are left
# alone.
#
# The trailing ([^a-z]|$) is LOAD-BEARING, not tidiness. awk's `~` is a
# substring match with no \b, so an unanchored alternation matched whenever the
# next word merely STARTS with a token: "cannot be settled" hit `set`, "cannot
# be negatively impacted" hit `negative`, "cannot be zeroed out" hit `zero`.
# That is the same design-prose false positive the narrowing exists to remove,
# reintroduced through the back door.
#
# `[^a-z]` is a broad boundary, not a true word break — awk ERE has no \b — so
# ANY hyphenated compound built on a token still fires: "cannot be
# false-positive", "cannot be zero-indexed", "cannot be null-terminated". The
# limitation is not specific to one token, and a reader who assumes otherwise
# will be surprised by the second one. Left as is: the constructions are rare,
# and over-firing on an advisory guard costs a glance where under-firing costs
# the signal entirely.
#
# `reached` was considered for the token list and left OUT: "this branch cannot
# be reached" is a control-flow claim, not a claim about what a value holds, so
# it sits outside this guard's stated scope and reads like the design prose
# above. If reachability claims ever deserve a guard, that is its own decision
# with its own evidence. Pinned silent in the probe so the decision cannot be
# reverted by accident.
#
# ACCEPTED RECALL LOSS: only the exact token form fires, so inflected ones no
# longer do — "cannot be nulled / emptied / populating" are real value claims
# that now pass unflagged, where the bare arm caught them. This is a deliberate
# trade of recall for precision, not an oversight, and it is not free.
#
# Not fixed by adding the inflections, because the ambiguity is genuine rather
# than a vocabulary gap: "the count cannot be zeroed out" is pinned SILENT here
# as design prose, yet it is defensible as a value claim. Deciding that sentence
# either way requires the reader's context, which is exactly the judgement the
# bare arm made badly and noisily. A guard that fires on the unambiguous forms
# and stays quiet on the arguable ones is the version people keep reading.
#
# Channel: this runs as a PreToolUse Bash hook, NOT as a git hook. Plain hook
# stdout does not reach the agent — the same gap pr-monitor-reminder.sh probed
# and confirmed for every matcher — so the channel that DELIVERS is
# hookSpecificOutput.additionalContext, per the Claude Code hooks reference
# ("Add context for Claude": PreToolUse additionalContext reaches Claude next
# to the tool result). No permissionDecision field is ever emitted, so the
# hook cannot block: the commit proceeds either way, and the banner is read
# BEFORE the commit object exists — an earlier moment than the source's
# pre-commit channel, which an agent only sees after `git commit` returns.
# The practical remedy is an ordinary edit (or `git commit --amend`), same
# direction as the source.
#
# Path exclusions: tracker/, backlog/, docs/, .claude/, .husky/, and ALL *.md
# files. Markdown is prose that legitimately DESCRIBES these phrasings
# (CLAUDE.md, READMEs, backlog notes — this hook's own source too); the
# guarded surface is claims entering CODE. `.husky/` is inherited from the
# source this hook was ported from, for the same reason as `.claude/`: hook-
# and skill-config surfaces necessarily quote the phrasings they guard, and
# repos that still carry a pre-commit hook flag its own description comment.
# Filtering happens on the diff's `+++ b/<path>` headers, so a mixed commit
# still scans its code files.
#
# Advisory only: never blocks, always exits 0, and every git/awk/jq failure
# fails open.
#
# Fixture check: run plugins/seyag/hooks/claim-shape-guard.probe.sh after
# ANY edit.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null || echo "")
[ "$TOOL_NAME" = "Bash" ] || exit 0

COMMAND=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null || echo "")
[ -n "$COMMAND" ] || exit 0

# Cheap pre-filter before spawning git: only a word-bounded `git` followed by
# a word-bounded `commit` anywhere in the command can be a commit invocation.
# (Sibling prefilter style. A false positive here only costs one
# `git diff --cached`, so the filter stays loose rather than reimplementing
# the command parser — the guard is advisory and fail-open.)
if ! grep -qE '(^|[[:space:]&|;(`])git([[:space:]]|$)' <<<"$COMMAND"; then
  exit 0
fi
if ! grep -qE '(^|[[:space:]&|;(`=-])commit([[:space:]]|$)' <<<"$COMMAND"; then
  exit 0
fi

# The staged diff belongs to the project the session runs in; the probe
# points CLAUDE_PROJECT_DIR at a throwaway repo. A command naming
# `git commit` outside any repo fails below and fails open (silent).
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Single `git diff --cached` piped through one awk pass: file-header tracking
# for the path exclusions, then the claim-shape match over added lines only.
# The -c overrides force canonical a/ b/ unquoted headers regardless of the
# user's diff.mnemonicPrefix / core.quotePath config, which the path
# exclusions depend on.
# The 3-line cap lives INSIDE awk rather than in a `head -3`: under
# `pipefail`, head closing the pipe early makes the whole substitution exit
# nonzero, and a fail-open `|| MATCHES=""` there would silently discard the
# very matches it just found. The cap is COMMIT-wide, not per-file — the
# banner is a pointer to the staged change, not an exhaustive report.
MATCHES=$(git -c diff.mnemonicprefix=false -c core.quotepath=false diff --cached 2>/dev/null | awk '
/^\+\+\+ /{
    path = substr($0, 5)
    sub(/^b\//, "", path)
    skip = (path ~ /^(tracker|backlog|docs|\.claude|\.husky)\// || path ~ /\.md$/) ? 1 : 0
    next
}
/^\+/{
    if (skip || n >= 3) next
    line = substr($0, 2)
    if (tolower(line) ~ /always (populated|set|non-null|present|returns)|never (null|empty|undefined|happens|fires)|cannot be (null|empty|undefined|unset|set|present|absent|missing|zero|negative|false|true|populated)([^a-z]|$)|cannot (happen|match|occur)|guaranteed to|(is|are) always|only ever/) {
        print substr(line, 1, 100)
        n++
    }
}
')

# Any git/awk failure leaves this empty, which is the fail-open path.
[ -z "${MATCHES//[[:space:]]/}" ] && exit 0

# Command substitution strips the LAST newline of the indented block, so the
# format string carries an explicit \n between the matches and the guidance
# line — otherwise the guidance glues onto the final match.
TEXT=$(printf 'CLAIM-SHAPE GUARD: staged line(s) assert what a field/value always or never holds:\n%s\nPer seyag core.md § Don'\''t present speculation as fact (the producer is authoritative): verify each at its producer/assignment site and cite it, or amend.\n' \
  "$(printf '%s\n' "$MATCHES" | sed 's/^/  /')")

# Advisory delivery: additionalContext is the field PreToolUse actually
# delivers to Claude (see the channel note in the header). Plain stdout is
# NOT printed as well — it never reaches the agent, so it would only be a
# second copy of the wording to keep in sync. No permissionDecision field is
# ever emitted: this hook never blocks.
jq -n --arg ctx "$TEXT" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}'

exit 0
