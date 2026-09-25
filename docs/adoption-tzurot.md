# What the harness took over from Tzurot

Tzurot is where the harness started (its `doc-64`, "Meta-Harness Spinoff"). Since 2026-09-25 the Deck management session builds it here, in `claude-harness`. This file is the handover: what has a plugin version, and what Tzurot can retire on its own schedule. Tzurot owns its `.claude/`, tracker and branches; nothing here changes them.

## Hooks

A project hook with the same file name as a plugin hook wins in that project (see README § Project overrides). So in Tzurot, **Tzurot's copy runs and the plugin's copy stands down.**

| Hook | Plugin state vs Tzurot's copy |
|---|---|
| bare-token-binding-reminder, blocking-question-channel-check, context-size-reminder, grep-escaped-dollar-guard, queued-message-receipt, self-matching-pattern-guard, turn-end-shape-gate | Twin; the differences are comments pointing at `rules/core.md` instead of Tzurot's rule files, the `HARNESS_ALLOW_GREP_DOLLAR` bypass name (the plugin still accepts `TZUROT_ALLOW_GREP_DOLLAR`), and one behavior change: queued-message-receipt's hop-chain fix (b06e7a4), which stops a relayed cross-session message from reporting itself as unanswered |
| cwd-drift-guard, lossy-pipe-guard, promise-ledger-check, python-heredoc-edit-guard | Twin, substantially reworked: cwd-drift asks the filesystem and needs no per-repo config; lossy-pipe takes project gh wrappers via `HARNESS_LOSSY_PIPE_GH_WRAPPERS`; promise-ledger takes `HARNESS_LEDGER_PATH_RE`; heredoc guard blocks only read-modify-write edits |
| broad-walk-guard, cache-rm-redirect | Plugin only; already run in Tzurot sessions |

Tzurot-only hooks (board-commit-branch-gate, claim-shape-guard, develop-code-commit-guard, dispatch-*, pr-*, skill-eval, tracker-dirty-push-gate) have no plugin version and stay Tzurot's.

**To retire a twin:** run Tzurot's `<hook>.probe.sh` against the plugin's script and confirm that every case Tzurot depends on still passes (set any `HARNESS_*` variable Tzurot needs in its settings env). Then delete Tzurot's copy; the plugin's version takes over at the next `/reload-plugins`, provided the installed plugin copy registers that hook (harness 0.2.0 and later register all 14; 0.1.0 registered only 9, see README § Install).

## Skills

| Tzurot skill | Plugin skill | Note |
|---|---|---|
| `tzurot-usage-audit` | `usage-audit` + `bin/usage-sweep` | Sweeps every project folder, not just Tzurot's. **Tzurot's Step 2 jq overcounts about 2.2x**: Claude Code writes each content block of a reply as its own JSONL line, each repeating the reply's usage (output growing as it streams), and that recipe sums lines. `usage-sweep` counts each reply once, at its largest output. Weighted totals in Tzurot's `usage-ledger.md`, and any posture figures derived from them, are inflated by roughly that factor; meter percentages are unaffected, and same-method rows stay roughly comparable with each other (the factor was 2.18-2.29 across two windows, varying with the model mix). |
| `tzurot-session-mining` | `session-mining` + `bin/session-extract` | Same method, any slug; output stays in each slug's `mined-corpus/`, so Tzurot's history and README keep working. The extract recipes are now one fixture-tested script. |
| `tzurot-council-mcp` | `council` | Ported in harness 0.1.0 (0bc1961). |
| `tzurot-doc-audit` | `doc-audit` + `bin/context-audit` | Keeps the memory verdicts (destination first, then propose the deletion) and the four-question economy cut test; covers the shared memory and every project's always-loaded set. Tzurot's docs-tree sections (proposals, research, README guards, `pnpm ops lines:check`) stay Tzurot's. |
| `tzurot-bug-remediation` | `bug-remediation` | Same five steps; Tzurot's tool names (xray, Railway, `/inspect`) replaced by "the project's own tools". |
| `tzurot-reuse-scout` | `reuse-scout` | Same two moments; Tzurot's utility tables and `pnpm ops` guards replaced by generic equivalents. |

## Rules

`plugins/harness/rules/core.md` loads into every session, Tzurot's included (via `~/.claude/rules/harness-core.md`). Tzurot's `.claude/rules/` win where they conflict.
