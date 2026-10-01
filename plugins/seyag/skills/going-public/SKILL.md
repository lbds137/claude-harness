---
name: going-public
description: Checklist before flipping a repo public, publishing a gist, or making an artifact public. Use when asked to make something public, rename-with-publish, or audit publish readiness.
---

# Going public

The blocking gates below run in order; a fail in any one stops the flip until it has a disposition. The checks are generic on purpose — per-repo specifics live in the audit that runs this skill, not here.

## Blocking gates

1. **Secrets, full history.** Secret-scan the full history — `gitleaks git <repo>` — never the working tree alone. The scanner is installed on this machine via `mise`; if it is absent, that is a stop, not a step to skip. Report findings redacted; the raw findings file stays local.
2. **Personal data.** Author names and emails via `git log --format='%an <%ae>' | sort -u` — noreply addresses preferred, a real address is a finding. Also match the owner's deadname (by rule, against the shared memory note — never grep the literal), real names, chat or user IDs, tailnet hostnames, and home-directory paths naming the user.
3. **Local-only material.** Files living only in gitignored paths, `.git/info/exclude` entries, and `docs/local/`-style folders: nothing public-bound references them, and nothing load-bearing exists ONLY unpushed.
4. **LICENSE and attribution.** LICENSE present and matching upstream — AGPL forks stay AGPL; upstream and donor attribution kept and visible.
5. **Naming.** A fork of a project that refuses AI contributions does not go public under that project's name — rename first, attribution kept. Also flag the owner's names in the repo name, description, topics and README title.
6. **Workflows.** No hardcoded secrets (secret NAMES are fine); note the scope of `permissions:` blocks. A workflow file carrying personal paths, private-repo provenance comments, or the owner's name is a finding.
7. **Description and metadata.** Repo description, homepage, topics — no personal references.

## Advisory checks

Repo settings (issues, wiki), stale branch names, pinned issues. Advisory by default; flip-blocking only if the owner rules them so for that repo. Repo settings preset: `bin/repo-preset apply <owner/repo>` — rebase-only, wiki off, minimal protection; adopted from Tzurot's live settings.

## Record the verdict

Findings go to the owner as a list with severities. Before the flip, each blocking finding has a disposition: fixed, ruled out with reason, or accepted for flip by the owner. Mechanical gates elsewhere may key on `SYG_PUBLISH_CHECKED=<repo>`, set only after this checklist passes.

## Rename is not publish

A repo may rename while private; publishing is its own gate and its own decision.
