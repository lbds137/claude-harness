# claude-harness

The portable Claude Code process layer for every project on Lila's Steam Deck: hooks, rules, skills, the implementer agent. The "Harness" session (role file `roles/claude-harness.md` in claude-memory) is the plugin's author. The "Deck management" session installs releases and coordinates reloads.

## Gate
`bash tests/run-probes.sh` from the repo root, every probe PASS, before any push. A new or changed Bash-matching hook is also replayed against local session logs first: `tests/replay-hook.sh <hook> --since 7`, and its blocked set sampled.

## How changes ship
- Branch, PR, CI probes plus Claude review, merge. No direct pushes to main.
- Implementation over 5 lines, prose included (owner's ruling 2026-09-25), goes through the `delegation` skill: spec in `.claude/dispatch/` (gitignored); worker in a hand-made worktree (`git worktree add -b worktree-agent-<x> .claude/worktrees/<x> <base>`), dispatched WITHOUT the isolation flag and pointed at the worktree's absolute path; the driver reads the full diff; a fresh-context review agent; transfer with the skill's block; probes from the main checkout.
- The step-0 self-heal block in the delegation skill is the one sanctioned `git reset --hard` in this repo.
- A release is one version bump of `plugins/harness/.claude-plugin/plugin.json` per merged batch. Installing it (`claude plugin marketplace update claude-harness && claude plugin update harness@claude-harness --scope user`) and asking Lila to `/reload-plugins` the open sessions is the Deck management session's job: message it after the merge, with the version.

## Ceilings and landmines
- `plugins/harness/rules/core.md` is always-loaded in every session on the machine (19.7 KB at 0.3.8): every added line is paid on every turn everywhere. Cut before adding.
- Probes pin message text and output shapes; a wording change usually needs its probe changed in the same diff.
- `hooks/session-start.sh` prints `harness plugin <version>` as its first line on every start; `deck-sessions --harness` (dev-docs) reads it from session logs. Keep the prefix.
- Session-mining corpora and reports under `~/.claude/projects/*/mined-corpus/` are private working material; only operationalized outcomes (a rule line, a skill step, a hook) enter this repo.
- Local-only list: nothing here needs secrets, a database or live services.
