# claude-harness

A Claude Code plugin marketplace with one plugin, `harness`. The plugin is the portable "how to work honestly and well" layer, first built inside the Tzurot repo. It gives every Claude Code session on this machine the same working rules, shell-safety guards and turn-shape checks, whatever project the session is in.

It assumes the owner mostly drives sessions from her phone and does not read diffs. Agent review and automated checks are the quality gate, and any blocking question has to go through `AskUserQuestion` so it shows up on the phone.

## What's in it

| Path | What it is |
|---|---|
| `plugins/harness/rules/core.md` | The shared working rules, loaded into every session as a user-level rule (see Install): interaction style, working posture, evidence and claims, extra safety rules, reporting. Project rules win when they conflict. |
| `plugins/harness/hooks/` | Hooks with a `*.probe.sh` test next to each. Shell-safety guards: `self-matching-pattern-guard`, `python-heredoc-edit-guard`, `grep-escaped-dollar-guard`, `broad-walk-guard` (blocks find/du/grep -r/rg/fd walks of `/`, `/home`, `~` or `~/gdrive`, whose rclone mount a walk can wedge), `lossy-pipe-guard` (blocks `git commit`/`git push` piped into any filter, and a `gh` read such as `gh pr checks` piped into head/tail/sed; a project opts its own gh wrapper commands in with `HARNESS_LOSSY_PIPE_GH_WRAPPERS`, a whitespace-separated list of wrapper tokens). Turn-shape checks: `blocking-question-channel-check`, `turn-end-shape-gate`. Prompt-time reminders: `queued-message-receipt`, `bare-token-binding-reminder`, `context-size-reminder`. `lib/shell_quotes.py` is the shared quote/heredoc scanner, pinned directly by `tests/shell_quotes.probe.sh` (cases ported from Tzurot's `shellQuotes.test.ts`). |
| `plugins/harness/skills/council/` | `council` skill: how to use the council MCP server (model choice, debates, reading split panels). |
| `plugins/harness/agents/implementer.md` | `implementer` subagent: carries out a tight spec exactly, runs the project's own checks, never commits, and reports in a fixed format. |
| `plugins/harness/bin/safe-clean` | On every session's PATH. Deletes only regenerable caches (`__pycache__`, `node_modules`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `.turbo`, `htmlcov`, `.coverage`) inside a git repo; refuses symlinks, tracked content and everything else. `--dry-run`, `--find NAME [DIR]`. The `cache-rm-redirect` hook points hand-rolled `rm -rf`/`find -delete` on those names at it. |
| `tests/run-probes.sh` | Runs every probe (hooks and `tests/*.probe.sh`). |

## Install

The plugin installs from a local marketplace, and the rules load through a user-level rules link:

```bash
claude plugin marketplace add ~/Projects/claude-harness
claude plugin install harness@claude-harness --scope user
mkdir -p ~/.claude/rules && ln -s ~/Projects/claude-harness/plugins/harness/rules/core.md ~/.claude/rules/harness-core.md
```

**Why a rules link and not a hook:** Claude Code shows a hook's output to the session in full only up to about 10 KB (measured 2026-09-25: 9.5 KB arrived whole, 12 KB became a 2 KB preview). `core.md` is about 18 KB. Files in `~/.claude/rules/` load into every session in full. If the link is missing, the SessionStart hook says so in one line.

A plugin from this local marketplace runs in place: its hooks and `bin/` resolve to `~/Projects/claude-harness/plugins/harness` (checked 2026-09-25), even though Claude Code also keeps a copy under `~/.claude/plugins/cache/`. So an edit here reaches every new session without a version bump; `/reload-plugins` picks it up mid-session.

**Headless runs** (`claude -p`, SDK scripts; `CLAUDE_CODE_SESSION_ATTENDED=0`) skip the turn-shape hooks, which are about talking to a person. The shell guards still run. The rules file still loads, at about 4.5k tokens per call.

**Fail-open:** `run.sh` skips a hook that has a syntax error instead of letting bash's exit 2 block every Bash call.

**Heredoc edit guard:** `python-heredoc-edit-guard.sh` blocks an inline `python3`/`node -e` script only when it writes a target it also reads (a read-modify-write edit). A script that reads inputs and writes a different output, which is routine in data-processing projects, passes. Bypass: `HARNESS_ALLOW_HEREDOC_EDIT=1`.

## Project overrides

If a project has its own copy of a hook under the same name, `.claude/hooks/<same-name>.sh`, the plugin's version stands down in that project and the project's version runs. This way Tzurot, which still carries its own copies, doesn't get every check twice. The same applies to the rules: `core.md` says project CLAUDE.md and `.claude/rules/` take precedence.

## Bypass tokens

To get one command past a blocking guard on purpose, put an env prefix on that command:

| Token | Guard |
|---|---|
| `HARNESS_ALLOW_HEREDOC_EDIT=1` | python-heredoc-edit-guard |
| `HARNESS_ALLOW_CACHE_RM=1` | cache-rm-redirect (an rm the owner approved) |
| `HARNESS_ALLOW_GREP_DOLLAR=1` | grep-escaped-dollar-guard |
| `HARNESS_ALLOW_BROAD_WALK=1` | broad-walk-guard (a walk meant to be broad) |

The context-size reminder has two tuning variables: `HARNESS_CONTEXT_THRESHOLD` (in tokens, default 500000) and `HARNESS_CONTEXT_COOLDOWN_MIN` (default 30).

## Tests

```bash
tests/run-probes.sh
```

Runtime dependencies for the hooks: bash, `jq`, `python3` and GNU grep.

## License

MIT, see `LICENSE`.
