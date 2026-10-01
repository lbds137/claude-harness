#!/bin/bash
# Fixture check for bin/branch-sweep against a throwaway git repo.
# Usage: tests/branch-sweep.probe.sh   (from anywhere)

set -uo pipefail
BS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/seyag/bin/branch-sweep"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok:   $1"; }
bad() { echo "FAIL: $1"; fail=1; }

R="$T/repo"; mkdir -p "$R"
git -C "$R" init -q -b main
# Repo-local identity: CI runners have no global git user, and two commits
# below deliberately omit the per-commit -c flags.
git -C "$R" config user.email t@t
git -C "$R" config user.name t
echo base > "$R/f.txt" && git -C "$R" add f.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -qm base
# feat-a: one change, squash-merged onto main so the squash commit's tree
# equals feat-a's tree (ancestry differs — the case `git branch -d` refuses).
git -C "$R" checkout -qb feat-a
echo feat > "$R/f.txt" && git -C "$R" commit -qam "feat-a change"
git -C "$R" checkout -q main
git -C "$R" merge --squash -q feat-a >/dev/null 2>&1 || bad "squash merge failed"
git -C "$R" -c user.email=t@t -c user.name=t commit -qm "feat-a change"
SQ=$(git -C "$R" rev-parse main)
# decoy: one more commit on main whose subject CONTAINS feat-a's subject.
# With it, main's tip is no longer the squash commit, so feat-a's ELIGIBLE can
# only come from the capped walk (positive-path coverage); and the old
# substring hint grep would have hinted at THIS commit — the exact-match hint
# must never name it.
echo decoy > "$R/decoy.txt" && git -C "$R" add decoy.txt
git -C "$R" commit -qm "chore: supersede feat-a change"
DECOY=$(git -C "$R" rev-parse main)
# develop: a second local base for the --base flag coverage (item: flag surface).
git -C "$R" branch develop
# wip-b: an unmerged change, no tree match anywhere on main.
git -C "$R" checkout -qb wip-b
echo wip > "$R/g.txt" && git -C "$R" add g.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -qm "wip work"
git -C "$R" checkout -q main
# rework-c: tree differs from every base commit, but its tip subject matches
# the squash commit's — the DIFFERS-hint path ("merged then reworked").
git -C "$R" checkout -qb rework-c
echo rework > "$R/f.txt" && git -C "$R" commit -qam "feat-a change"
git -C "$R" checkout -q main
# tag/branch collision: a tag named `main` pointing off main's history, plus
# a branch whose tree matches the TAG's tree — base-side git DWIM must never
# resolve to the tag and judge tag-match ELIGIBLE against it.
git -C "$R" checkout -qb tagbase
echo taggy > "$R/h.txt" && git -C "$R" add h.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -qm "tag work"
git -C "$R" branch tag-match
git -C "$R" tag main
# 2>/dev/null: the tag/branch name collision is the fixture's point, and git
# warns "refname 'main' is ambiguous" on the checkout even as it picks the branch.
git -C "$R" checkout -q main 2>/dev/null
# wt-branch: tree-identical to main, but checked out in a linked worktree.
git -C "$R" worktree add -q "$T/wt" -b wt-branch
# recycled candidate name: a tag `recyc` left at a BASE commit (the decoy),
# THEN an unrelated branch `recyc` from main with its own unmerged change —
# the reviewer's scenario (tag from a deleted/renamed branch, name recycled).
# Construction order matters: tag FIRST at the existing base commit, branch
# AFTER. A candidate-side git call that passes the bare name resolves to the
# TAG (tags win DWIM for diff/log) and would judge recyc ELIGIBLE off the
# tag's base tree — i.e. delete an unmerged branch.
git -C "$R" tag recyc "$DECOY"
git -C "$R" checkout -qb recyc
echo recycled > "$R/r.txt" && git -C "$R" add r.txt
git -C "$R" -c user.email=t@t -c user.name=t commit -qm "recycled work"
git -C "$R" checkout -q main

out=$( (cd "$R" && "$BS") 2>&1 ); rc=$?
[ $rc = 0 ] && ok "dry run exits 0" || bad "dry run exit $rc"
grep -qF "ELIGIBLE feat-a (tree identical to $SQ)" <<< "$out" \
  && ok "ELIGIBLE line for feat-a carries the squash SHA" || bad "feat-a ELIGIBLE (out: $(head -c 400 <<< "$out"))"
git -C "$R" rev-parse --verify -q refs/heads/feat-a >/dev/null \
  && ok "dry run keeps feat-a" || bad "dry run deleted feat-a"
grep -q "SKIP main (current branch)" <<< "$out" && ok "SKIP main (current)" || bad "SKIP main"
grep -q "SKIP wt-branch" <<< "$out" && ok "SKIP wt-branch (worktree)" || bad "SKIP wt-branch"
grep -q "DIFFERS wip-b" <<< "$out" && ok "DIFFERS wip-b" || bad "DIFFERS wip-b"
grep -q "DIFFERS rework-c" <<< "$out" \
  && grep -q "tip subject matches" <<< "$out" \
  && ok "DIFFERS rework-c carries the reworked-subject hint" || bad "rework-c hint"
grep -q "DIFFERS tag-match" <<< "$out" && ! grep -q "ELIGIBLE tag-match" <<< "$out" \
  && ok "tag named main: tag-match judged against the branch, DIFFERS" || bad "tag-match collision"
# Candidate-side collision: branch `recyc` shares its name with a tag parked
# at a base commit; the candidate-side calls must use the full refname, or the
# tag wins DWIM and recyc's unmerged tree reads as ELIGIBLE (deletable).
grep -q "DIFFERS recyc" <<< "$out" && ! grep -q "ELIGIBLE recyc" <<< "$out" \
  && ok "tag named recyc at a base commit: recycled branch judged against the branch, DIFFERS" \
  || bad "recyc candidate-side collision (out: $(head -c 400 <<< "$out"))"
grep -q "base: main" <<< "$out" && ok "header names base main (no-origin fallback)" || bad "header base (out: $(head -2 <<< "$out"))"

# feat-a's match now provably comes from the capped walk: main's tip is the
# decoy commit, not the squash commit the fast path would have hit.
grep -qF "ELIGIBLE feat-a (tree identical to $SQ)" <<< "$out" \
  && ok "feat-a ELIGIBLE via the capped walk (main tip is the decoy, not the squash commit)" \
  || bad "feat-a walk match (out: $(head -c 400 <<< "$out"))"
# --base flag: a second local branch as base; header names the flag source and
# feat-a stays ELIGIBLE against develop's history.
outd=$( (cd "$R" && "$BS" --base develop) 2>&1 ); rc=$?
[ $rc = 0 ] \
  && grep -qF "base: develop (ref: refs/heads/develop; source: --base flag)" <<< "$outd" \
  && grep -qF "ELIGIBLE feat-a (tree identical to $SQ)" <<< "$outd" \
  && ok "--base develop: header names the flag, feat-a still ELIGIBLE" \
  || bad "--base develop (rc $rc; out: $(head -c 400 <<< "$outd"))"
# --base=value form: parses to the same header as the space form.
oute=$( (cd "$R" && "$BS" --base=develop) 2>&1 ); rc=$?
[ $rc = 0 ] \
  && grep -qF "base: develop (ref: refs/heads/develop; source: --base flag)" <<< "$oute" \
  && ok "--base=develop: the = form parses to the space form's header" \
  || bad "--base=develop (rc $rc; out: $(head -c 400 <<< "$oute"))"
outn=$( (cd "$R" && "$BS" --base nosuchbase) 2>&1 ); rc=$?
[ $rc = 1 ] && grep -q "resolves to neither" <<< "$outn" \
  && ok "unresolvable --base: exit 1, resolve failure on stderr" \
  || bad "--base nosuchbase (rc $rc; out: $(head -c 400 <<< "$outn"))"
outf=$( (cd "$R" && "$BS" --no-fetch) 2>&1 ); rc=$?
[ $rc = 0 ] && grep -qF "fetch: skipped (--no-fetch)" <<< "$outf" \
  && ok "--no-fetch: header notes the skipped fetch" \
  || bad "--no-fetch header (rc $rc)"
# Hint exactness: rework-c's subject matches SQ exactly; the decoy commit's
# subject merely CONTAINS it, so the decoy's SHA must never be HINTED. (The
# decoy's full SHA legitimately appears elsewhere: develop branches at the
# decoy tip and is ELIGIBLE against main.)
SQS=$(git -C "$R" rev-parse --short "$SQ"); DECOYS=$(git -C "$R" rev-parse --short "$DECOY")
hint_lines=$(grep "hint:" <<< "$out" || true)
grep -qF "tip subject matches $SQS" <<< "$out" && ! grep -qF "$DECOYS" <<< "$hint_lines" \
  && ok "rework-c hint names the exact-match SHA ($SQS), never the decoy's" \
  || bad "hint exactness (SQ $SQS, decoy $DECOYS; hints: $hint_lines)"

out2=$( (cd "$R" && "$BS" --apply) 2>&1 ); rc=$?
[ $rc = 0 ] && ok "apply exits 0" || bad "apply exit $rc"
git -C "$R" rev-parse --verify -q refs/heads/feat-a >/dev/null \
  && bad "apply did not delete feat-a" || ok "apply deleted feat-a"
grep -qF "deleted feat-a (matching SHA $SQ)" <<< "$out2" \
  && ok "deletion line carries the matching SHA" || bad "deletion line (out: $(head -c 400 <<< "$out2"))"
for keep in wip-b rework-c tag-match wt-branch main recyc; do
  git -C "$R" rev-parse --verify -q "refs/heads/$keep" >/dev/null \
    && ok "apply keeps $keep" || bad "apply deleted $keep"
done

# A tag sharing the CURRENT branch's name (the linked worktree's wt-branch):
# the skip must report the plain name — never heads/<name>, which would miss
# the skip set and break the apply — and the run stays exit 0 under --apply.
git -C "$R" tag wt-branch
out4=$( (cd "$T/wt" && "$BS" --apply) 2>&1 ); rc=$?
[ $rc = 0 ] && grep -q "SKIP wt-branch (current branch)" <<< "$out4" \
  && ! grep -qE '^(ELIGIBLE|DIFFERS|SKIP) heads/' <<< "$out4" \
  && ok "tag on current branch's name: plain-name SKIP, exit 0 under --apply" \
  || bad "current-branch tag collision (rc $rc)"
out5=$( (cd "$R" && "$BS" --nope) 2>&1 ); rc=$?
[ $rc = 1 ] && grep -q "Usage:" <<< "$out5" \
  && ok "unknown argument: usage text, exit 1" || bad "unknown argument (rc $rc)"

out3=$( (cd "$R" && "$BS" --help) 2>&1 ); rc=$?
[ $rc = 0 ] && grep -q "Usage:" <<< "$out3" \
  && ok "--help prints usage, exits 0" || bad "--help (rc $rc)"
allok=1
for keep in wip-b rework-c tag-match wt-branch main recyc; do
  git -C "$R" rev-parse --verify -q "refs/heads/$keep" >/dev/null || allok=0
done
[ $allok = 1 ] && ok "--help removes nothing" || bad "--help removed a branch"
exit $fail
