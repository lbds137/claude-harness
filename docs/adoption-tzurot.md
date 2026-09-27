# What the harness took over from Tzurot

Tzurot is where the harness started (its `doc-64`, "Meta-Harness Spinoff"). Since 2026-09-25 the Deck management session builds it here, in `claude-harness`. This file is the handover: what has a plugin version, and what Tzurot can retire on its own schedule. Tzurot owns its `.claude/`, tracker and branches; nothing here changes them.

## Hooks

A project hook with the same file name as a plugin hook wins in that project (see README § Project overrides). So in Tzurot, **Tzurot's copy runs and the plugin's copy stands down.**

| Hook | Plugin state vs Tzurot's copy |
|---|---|
| bare-token-binding-reminder, blocking-question-channel-check, context-size-reminder, grep-escaped-dollar-guard, queued-message-receipt, self-matching-pattern-guard, turn-end-shape-gate | Twin; the differences are comments pointing at `rules/core.md` instead of Tzurot's rule files, the `HARNESS_ALLOW_GREP_DOLLAR` bypass name (the plugin still accepts `TZUROT_ALLOW_GREP_DOLLAR`), and one behavior change: queued-message-receipt's hop-chain fix (b06e7a4), which stops a relayed cross-session message from reporting itself as unanswered |
| cwd-drift-guard, lossy-pipe-guard, promise-ledger-check, python-heredoc-edit-guard | Twin, substantially reworked: cwd-drift asks the filesystem and needs no per-repo config; lossy-pipe takes project gh wrappers via `HARNESS_LOSSY_PIPE_GH_WRAPPERS`; promise-ledger takes `HARNESS_LEDGER_PATH_RE`; heredoc guard blocks only read-modify-write edits; promise-ledger ignores a work verb used as a noun after an article |
| broad-walk-guard, cache-rm-redirect | Plugin only; already run in Tzurot sessions |

Tzurot-only hooks (board-commit-branch-gate, claim-shape-guard, develop-code-commit-guard, dispatch-spec-ledger-gate, skill-eval, tracker-dirty-push-gate) have no plugin version and stay Tzurot's. `dispatch-posture-gate` has a plugin twin (opt-in via `HARNESS_DISPATCH_SRC_RE`, 0.3.3); Tzurot keeps its own copy with its hardcoded `services|packages` scope, and that same-name project hook disables the plugin's copy per run.sh.

`pr-monitor-reminder` now has a plugin twin too (see § CI gate below); Tzurot's copy still wins by name until it's deleted. The rest of the `pr-*` family (pr-body-ref-gate, pr-merge-review-check) has no plugin version and stays Tzurot's.

**To retire a twin:** run Tzurot's `<hook>.probe.sh` against the plugin's script and confirm that every case Tzurot depends on still passes (set any `HARNESS_*` variable Tzurot needs in its settings env). Then delete Tzurot's copy; the plugin's version takes over at the next `/reload-plugins`, provided the installed plugin copy registers that hook (harness 0.2.0 and later register every hook (15 at 0.3.3); 0.1.0 registered only 9, see README § Install).

## CI gate

Tzurot's `gh:ci-gate` (`packages/tooling/src/gh/ci-gate.ts`) and `.claude/hooks/pr-monitor-reminder.sh` now have plugin versions: `plugins/harness/bin/pr-ci-wait` and `plugins/harness/hooks/pr-monitor-reminder.sh`. What differs, ported behavior aside:

- **Delivery.** Tzurot's hook's own header records that its banner never reached the agent — non-blocking PostToolUse stdout is dropped, confirmed by probing every matcher. The plugin's hook emits `hookSpecificOutput.additionalContext` instead (the field PostToolUse actually delivers to Claude, per the Claude Code hooks reference), so its reminder is read, not just logged. This alone is worth adopting even before the rest of the twin retires.
- **Anchor is required in Tzurot, optional in the plugin.** `pr-ci-wait` falls back to a quiet-window rule (settled once nothing is pending and the run-id set has been unchanged for `PR_CI_WAIT_QUIET_S`, default 90s) when `HARNESS_CI_ANCHOR` is unset — weaker than an anchor, since a workflow created after the window closes is missed.
- **No `reportReviewRounds`.** Tzurot-only; keep it or re-home it separately — `pr-ci-wait` doesn't port it (nor the `pnpm`/ops wiring or the fixup-check note it carried).
- **`--sha` is optional.** Omitted, `pr-ci-wait` reads the PR's current head and says so — after the always-first "Waiting for CI on PR #N" line and the anchor/review config lines, not in the first log line itself; Tzurot's gate always required `--sha`.
- **Owner-assignee backfill dropped.** Tzurot's hook also backfilled the PR's assignee from its author; that's Tzurot-specific policy, not part of the portable reminder, and isn't ported.

**To retire the twin:** in Tzurot, set `HARNESS_CI_ANCHOR=CI` (review still auto-detects `Claude Code Review`), point the three copies of the Monitor command — the rule, the skill, and the hook's heredoc, pinned together by `pnpm ops guard:monitor-command` — at `pr-ci-wait <N> --sha $(git rev-parse HEAD)`, then delete `.claude/hooks/pr-monitor-reminder.sh`; the plugin's hook stops deferring at the next `/reload-plugins`. `reportReviewRounds` has no plugin equivalent — keep it Tzurot-side or re-home it.

## Skills

| Tzurot skill | Plugin skill | Note |
|---|---|---|
| `tzurot-usage-audit` | `usage-audit` + `bin/usage-sweep` | Sweeps every project folder, not just Tzurot's. **Tzurot's Step 2 jq overcounts about 2.2x**: Claude Code writes each content block of a reply as its own JSONL line, each repeating the reply's usage (output growing as it streams), and that recipe sums lines. `usage-sweep` counts each reply once, at its largest output. Weighted totals in Tzurot's `usage-ledger.md`, and any posture figures derived from them, are inflated by roughly that factor; meter percentages are unaffected, and same-method rows stay roughly comparable with each other (the factor was 2.18-2.29 across two windows, varying with the model mix). |
| `tzurot-session-mining` | `session-mining` + `bin/session-extract` | Same method, any slug; output stays in each slug's `mined-corpus/`. Tzurot's `reports/README.md` keeps dispositions and guard ledgers; mined ranges now go in the machine-wide ledger (`session-log mark`). The extract recipes are now one fixture-tested script. |
| `tzurot-council-mcp` | `council` | Ported in harness 0.1.0 (0bc1961). |
| `tzurot-doc-audit` | `doc-audit` + `bin/context-audit` | Keeps the memory verdicts (destination first, then propose the deletion) and the four-question economy cut test; covers the shared memory and every project's always-loaded set. Tzurot's docs-tree sections (proposals, research, README guards, `pnpm ops lines:check`) stay Tzurot's. |
| `tzurot-bug-remediation` | `bug-remediation` | Same five steps; Tzurot's tool names (xray, Railway, `/inspect`) replaced by "the project's own tools". |
| `tzurot-reuse-scout` | `reuse-scout` | Same two moments; Tzurot's utility tables and `pnpm ops` guards replaced by generic equivalents. |

## Rules

`plugins/harness/rules/core.md` loads into every session, Tzurot's included (via `~/.claude/rules/harness-core.md`). Tzurot's `.claude/rules/` win where they conflict.
