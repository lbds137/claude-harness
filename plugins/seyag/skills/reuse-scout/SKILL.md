---
name: reuse-scout
description: 'Pre-write reuse scouting and drifted-duplicate consolidation. Use before writing new detection, normalization, resolution, formatting or classification logic, when the owner asks "don''t we already have X?", or when a bug turns up in logic that exists in more than one place.'
---

# Reuse Scout

Semantically drifted duplicates (two places doing the same job slightly differently) cause bugs that copy-paste detectors can't see, because the code isn't literally the same. The defense is procedural, at two moments.

## Moment 1: before writing

Before implementing new detection, normalization, resolution, formatting or classification logic ("is this file a voice message?", "which config applies?", "how is this row rendered?"), search for an existing primitive:

- Use at least three vocabulary variants: your term, the domain's term, the library's term (core rules § Negative existence and the grep rule).
- Prefer the project's authoritative index over a raw grep when it has one: an export listing, a symbol index, a dead-code report (dormant scaffolding counts as prior art).
- Check the project's own tables of shared utilities, if its rules or docs keep one.
- **The owner's "don't we already have X?" is a search order, not a debate prompt.**
- Found it? Call or extend it; don't fork it. Found something almost right? Decide between extending it and writing anew on the merits, and if you write anew, say in the PR or commit why the existing one didn't fit.

## Moment 2: a bug in duplicated logic

- **Enumerate all copies deterministically** (by behavior keywords, not just the one or two in view). Fixing the visible copy while a drifted sibling survives is the recurring failure.
- Consolidate to one source of truth and turn every copy into a call site. If consolidation is genuinely out of scope, fix every copy identically now and file the consolidation with the full copy list.
- Prefer authoritative registries over heuristics: schema-derived lists, exported constants, typed tables, not string-suffix sniffing or hand-kept parallel lists (those drift).
- A same-name duplicate check doesn't catch same-behavior-different-name duplicates; this sweep does.

## Boundary

Don't over-rotate into the wrong abstraction. Duplicated skeleton shape (standard call sites of one shared helper) is fine. The target is duplicated decisions: two places that can disagree about the same question.
