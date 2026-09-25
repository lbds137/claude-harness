"""Direct unit cases for plugins/harness/hooks/lib/shell_quotes.py.

Ported from Tzurot's packages/tooling/src/dev/shellQuotes.test.ts (same inputs,
same expected values, same labels, so the two suites can be compared line by
line). A case added there should be added here too.

Run through tests/shell_quotes.probe.sh. Plain python3, stdlib only. The
library directory defaults to plugins/harness/hooks/lib beside this repo; set
SHELL_QUOTES_LIB_DIR to point it at another copy (used for the positive
control that proves these cases can fail).
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.environ.get("SHELL_QUOTES_LIB_DIR") or os.path.join(
    HERE, "..", "plugins", "harness", "hooks", "lib"
)
sys.path.insert(0, LIB_DIR)

from shell_quotes import (  # noqa: E402
    HEREDOC_OPENER,
    executed_segments,
    resolve_placeholders,
    strip_heredoc_bodies,
    strip_quoted,
    strip_quoted_indexed,
    substitution_spans,
    substitution_spans_matching,
    wrapped_command_strings,
)

QUOTED_SPAN = "\ue000"
ESCAPED_BLANK = "\ue001"

passed = 0
failed = 0


def report(label, ok, got, want):
    global passed, failed
    if ok:
        passed += 1
        print("ok   " + label)
    else:
        failed += 1
        print("FAIL %s: got %r want %r" % (label, got, want))


def check_equal(label, got, want):
    report(label, got == want, got, want)


def check_all(label, checks):
    """One TS `it` holding several expects: passes only if every expect does.
    `checks` is a list of (ok, got, want); the first failing one is reported."""
    for ok, got, want in checks:
        if not ok:
            report(label, False, got, want)
            return
    report(label, True, None, None)


# ---------------------------------------------------------------------------
# strip_quoted — [label, input, expected]; None means "unterminated".
# ---------------------------------------------------------------------------
CASES = [
    ('leaves an unquoted command alone', 'git status', 'git status'),
    ('replaces a double-quoted span', 'git commit -m "hello"', 'git commit -m S'),
    ('replaces a single-quoted span', "git commit -m 'hello'", 'git commit -m S'),
    (
        'an apostrophe inside double quotes is literal',
        'echo "it\'s" && git commit -m "won\'t"',
        'echo S && git commit -m S',
    ),
    (
        'the mirror: a double quote inside single quotes is literal',
        'echo \'say "hi"\' && git commit -m x',
        'echo S && git commit -m x',
    ),
    (
        'apostrophes straddling an unquoted token do not swallow it',
        'git commit -m "it\'s" && git add packages/x.ts && echo "don\'t"',
        'git commit -m S && git add packages/x.ts && echo S',
    ),
    ('an escaped letter keeps its value', 'git push | t\\ail -5', 'git push | tail -5'),
    ('an escaped quote cannot open a span', 'echo \\"x', 'echo Qx'),
    ('an even backslash run is not an escaped quote', 'echo \\\\"x"', 'echo \\S'),
    ('an escaped pipe is not a pipeline operator', 'git commit -m x\\|tail', 'git commit -m xQtail'),
    ('an escaped semicolon is not a separator', 'echo a\\;b', 'echo aQb'),
    ('a real pipe survives untouched', 'git push | tail -5', 'git push | tail -5'),
    ('no escapes inside single quotes', "echo 'a\\' && git commit", 'echo S && git commit'),
    ('a backslash escapes the closing double quote', 'echo "a\\" still in" && x', 'echo S && x'),
    (
        "an escaped apostrophe in $'...' desyncs to null, not a swallow",
        "echo $'it\\'s' && git commit -m x",
        None,
    ),
    (
        '...also when it straddles the target',
        "echo $'a\\'b' && git commit -m x && echo $'c\\'d'",
        None,
    ),
    ('...also on the pipe form rule 1 protects', "git commit -m $'it\\'s' | tail -5", None),
    (
        "two escapes in one $'...' span still desync to null",
        "echo $'a\\'b\\'c' && git commit -m x",
        None,
    ),
    (
        "two $'...' constructs straddling the target desync to null",
        "echo $'a\\'b' && git commit -m x && echo $'c\\'d'",
        None,
    ),
    (
        "$'...' with no escape behaves like a plain single-quoted span",
        "echo $'plain' && git commit -m x",
        'echo $S && git commit -m x',
    ),
    (
        'the documented tracker shape strips cleanly',
        "pnpm tracker task create 'T' -d $'Why: x\\nFix: y' && git commit -m x",
        'pnpm tracker task create S -d $S && git commit -m x',
    ),
    (
        'a line continuation splices, preserving word adjacency',
        'git \\\n  commit -m "msg"',
        'git   commit -m S',
    ),
    (
        '...and splices words TOGETHER when no space surrounds it',
        'git\\\ncommit -m x',
        'gitcommit -m x',
    ),
    (
        'a continuation inside a double-quoted span stays inside it',
        'git commit -m "line one \\\nline two"',
        'git commit -m S',
    ),
    ('an unterminated double quote strips nothing', 'git commit -m "oops', None),
    ('an unterminated single quote strips nothing', "git commit -m 'oops", None),
    ('a trailing lone backslash is emitted as itself', 'git commit -m x\\', 'git commit -m x\\'),
]

strip_results = [strip_quoted(inp) for _, inp, _ in CASES]
for (label, _inp, want), got in zip(CASES, strip_results):
    check_equal(label, got, want)

check_all(
    'leaves no quote character behind in any successful strip',
    [
        (not ('"' in got or "'" in got), got, '%s: no quote character' % label)
        for (label, _inp, _want), got in zip(CASES, strip_results)
        if got is not None
    ],
)

# ---------------------------------------------------------------------------
# substitution_spans — [label, input, expected spans]
# ---------------------------------------------------------------------------
SPAN_CASES = [
    ('no substitution yields no spans', 'git commit -m "x"', []),
    ('a $( ) span inside double quotes', 'echo "$(git commit -m x)"', ['git commit -m x']),
    ('a backtick span inside double quotes', 'echo "`git commit -m x`"', ['git commit -m x']),
    ('an unquoted $( ) span', 'echo $(git commit)', ['git commit']),
    ('two spans in one command', 'echo $(a) and `b`', ['a', 'b']),
    ('a nested span is returned inside its outer span, verbatim', 'echo $(a $(b))', ['a $(b)']),
    ('an escaped backtick opens nothing', 'echo \\`x\\`', []),
    ('an escaped dollar opens nothing', 'echo \\$(git commit)', []),
    ('an unterminated $( runs to end of text', 'echo "$(git commit', ['git commit']),
    ('an unterminated backtick runs to end of text', 'echo `git commit', ['git commit']),
    ('a span inside single quotes is not extracted', "echo 'run $(git commit)'", []),
    ('a backtick span inside single quotes is not extracted', "echo 'run `git commit`'", []),
    (
        'the same span inside double quotes is still extracted',
        'echo "run $(git commit)"',
        ['git commit'],
    ),
    (
        'a span after a closed single-quoted region is still extracted',
        "echo 'prose' $(git commit)",
        ['git commit'],
    ),
    ("a plain-content $'…' region is skipped", "echo $'run $(git commit)'", []),
    (
        'an apostrophe inside double quotes opens no region',
        "echo \"it's $(git commit)\" 'x'",
        ['git commit'],
    ),
    ('an unterminated single quote skips nothing', "echo 'oops $(git commit)", ['git commit']),
    ('an escaped apostrophe opens no region', "echo it\\'s $(git commit) 'x'", ['git commit']),
    (
        'fallback: a heredoc operator turns the skip off',
        "cat <<EOF\nit's $(git commit) 'x'\nEOF",
        ['git commit'],
    ),
    ('a here-string is not a heredoc operator', "cat <<< 'x' ; echo 'run $(git commit)'", []),
    (
        'fallback: bash -c executes its single-quoted argument',
        "bash -c 'echo $(git commit)'",
        ['git commit'],
    ),
    (
        'fallback: eval executes its single-quoted argument',
        "eval 'echo $(git commit)'",
        ['git commit'],
    ),
    (
        'fallback: single-quoted text piped into a shell is executed',
        "printf %s 'echo $(git commit)' | bash",
        ['git commit'],
    ),
    ('a .sh file name is not a shell word', "./run.sh 'see $(git commit)'", []),
    ('fallback: an unquoted # turns the skip off', "# don't\necho $(git commit) 'x'", ['git commit']),
    (
        "a comment's trailing backslash does not hide the next line's span",
        "true # x\\\necho \"\nit's $(git commit)\" 'z'",
        ['git commit'],
    ),
    ('a # inside single quotes is prose', "echo 'issue #12: $(git commit)'", []),
    (
        "fallback: a $'…' region ending in a backslash",
        "echo $'a\\'' $(git commit) 'x'",
        ['git commit'],
    ),
    (
        'a $$ before a plain region does not hide a span',
        "echo $$'a\\' \"$(git commit)\" 'b'",
        ['git commit'],
    ),
    (
        'fallback: a span with unbalanced inner quotes',
        'echo "$(echo ")")" x "y\' $(git commit) \'z"',
        ['echo "', 'git commit'],
    ),
    (
        'fallback: a span holding a quoted paren',
        'echo "$(echo "(")" )" y\' $(git commit) \'z"',
        ['echo "(")" ', 'git commit'],
    ),
    (
        'fallback: a span carrying a case word',
        'echo "$(case a in a) echo x;; esac)" y\' $(git commit) \'z',
        ['case a in a', 'git commit'],
    ),
    (
        'fallback: a span carrying a #',
        'echo "$(echo x # )\n)" y\' $(git commit) \'z',
        ['echo x # ', 'git commit'],
    ),
    ('a quoted `)` inside a span ends it early', 'echo "$(echo ")" && git commit)"', ['echo "']),
]

for label, inp, want in SPAN_CASES:
    check_equal(label, substitution_spans(inp), want)

# ---------------------------------------------------------------------------
# strip_heredoc_bodies — [label, input, expected]
# ---------------------------------------------------------------------------
HEREDOC_CASES = [
    ('text with no heredoc is returned unchanged', 'git commit -m x', 'git commit -m x'),
    ("a quoted marker's body is dropped", "cat <<'EOF'\ngit commit\nEOF\n", "cat <<'EOF'\n\n"),
    ("a bare marker's body is dropped", 'cat <<EOF\ngit commit\nEOF\n', 'cat <<EOF\n\n'),
    ('a double-quoted marker works too', 'cat <<"EOF"\ngit commit\nEOF\n', 'cat <<"EOF"\n\n'),
    (
        'the <<- form accepts an indented terminator',
        'cat <<-EOF\n\tgit commit\n\tEOF\n',
        'cat <<-EOF\n\n',
    ),
    (
        'an indented terminator leaves a plain heredoc unterminated; tail kept',
        'cat <<EOF\n\tEOF\ngit commit',
        'cat <<EOF\n\tEOF\ngit commit',
    ),
    (
        'an unterminated heredoc keeps its tail (over-arm, not dropped)',
        'cat <<EOF\ngit commit\n',
        'cat <<EOF\ngit commit\n',
    ),
    (
        'the rest of the opener line survives',
        'cat <<EOF > notes.txt\ngit commit\nEOF\n',
        'cat <<EOF > notes.txt\n\n',
    ),
    (
        'a here-string is not read as an opener',
        'cat <<<marker && git commit',
        'cat <<<marker && git commit',
    ),
    (
        'the canonical commit-message span keeps its skeleton and loses its body',
        "cat <<'EOF'\nfix: stop saying git commit in prose\nEOF\n",
        "cat <<'EOF'\n\n",
    ),
    (
        'second heredoc opener on a line leaves its body',
        'cat <<A <<B\naaa-body\nA\nbbb-body\nB\ntrailer\n',
        'cat <<A <<B\n\nbbb-body\nB\ntrailer\n',
    ),
]

for label, inp, want in HEREDOC_CASES:
    check_equal(label, strip_heredoc_bodies(inp), want)

_command = "\n".join(
    [
        "git commit -m \"$(cat <<'EOF'",
        'docs: explain when to git commit',
        'EOF',
        ')"',
    ]
)
_spans = substitution_spans(_command)
_checks = [(len(_spans) == 1, _spans, 'exactly 1 span')]
if len(_spans) == 1:
    _stripped = strip_heredoc_bodies(_spans[0])
    _checks += [
        ('git commit' in _spans[0], _spans[0], "span containing 'git commit'"),
        ('git commit' not in _stripped, _stripped, "stripped span without 'git commit'"),
    ]
check_all('suppresses a commit-shaped message body inside a canonical commit span', _checks)


# ---------------------------------------------------------------------------
# HEREDOC_OPENER exported group contract
# ---------------------------------------------------------------------------
def opener_groups(c):
    m = HEREDOC_OPENER.search(c)
    return None if m is None else [m.group(1), m.group(2), m.group(3)]


_checks = []
for inp, want in [
    ("cat <<-'EOF'", ['-', "'", 'EOF']),
    ('cat <<"EOF"', ['', '"', 'EOF']),
    ('cat <<EOF', ['', '', 'EOF']),
]:
    got = opener_groups(inp)
    _checks.append((got == want, got, want))
check_all('numbers its groups indent-flag, quote-char, marker', _checks)
check_equal('does not match a here-string', opener_groups('git commit -F - <<<Fixup'), None)


# ---------------------------------------------------------------------------
# substitution_spans_matching with the fixed 'git commit' predicate
# ---------------------------------------------------------------------------
def spans_match_git_commit(c):
    return substitution_spans_matching(c, lambda s: 'git commit' in s.lower())


check_equal(
    'matches a target hidden in a real substitution span',
    spans_match_git_commit('echo "$(git commit -m x)"'),
    True,
)
check_equal(
    'does NOT match a target in an inert heredoc body — heredocs are stripped FIRST',
    spans_match_git_commit(
        "\n".join(["cat <<'EOF' > notes.md", 'we fixed the $(git commit -m x) bypass', 'EOF'])
    ),
    False,
)
check_equal(
    'does NOT match a target that is only quoted prose inside a span — strip_quoted runs',
    spans_match_git_commit('echo "$(gh pr comment --body "git commit early")"'),
    False,
)
check_equal(
    'still matches when a real invocation sits beside quoted prose in the span',
    spans_match_git_commit('echo "$(git commit -m "wip")"'),
    True,
)
check_equal(
    'is span-only: a top-level target with no substitution does not match',
    spans_match_git_commit('git commit -m x'),
    False,
)
check_equal(
    'a target after an unterminated heredoc opener still matches (no truncation bypass)',
    spans_match_git_commit("\n".join(['echo "notes: <<EOF"', 'echo "$(git commit -m x)"'])),
    True,
)

# ---------------------------------------------------------------------------
# executed_segments
# ---------------------------------------------------------------------------
_checks = []
for inp, want in [('git status', ['git status']), ('echo "hello"', ['echo S'])]:
    got = executed_segments(inp)
    _checks.append((got == want, got, want))
check_all('returns the quote-stripped command as the first segment', _checks)

for _label, cmd in [
    ('bash -c', 'bash -c "pnpm tracker task create x"'),
    ('sh -c', "sh -c 'pnpm tracker task create x'"),
    ('zsh -c', 'zsh -c "pnpm tracker task create x"'),
    ('eval', 'eval "pnpm tracker task create x"'),
]:
    got = executed_segments(cmd)
    report(
        'unwraps the argument %s executes' % _label,
        'pnpm tracker task create x' in got,
        got,
        "a list containing 'pnpm tracker task create x'",
    )

check_equal(
    'leaves a non-wrapper argument stripped — echo does not execute its argument',
    executed_segments('echo "pnpm tracker task create x"'),
    ['echo S'],
)
check_equal(
    'recognizes a wrapper only at command position',
    executed_segments('echo bash -c "pnpm tracker task create x"'),
    ['echo bash -c S'],
)
got = executed_segments('ls && bash -c "inner cmd"')
report('recognizes a wrapper after a separator', 'inner cmd' in got, got, "a list containing 'inner cmd'")
got = executed_segments('/bin/sh -lc "inner cmd"')
report(
    'tolerates a path-qualified wrapper and a short-option cluster',
    'inner cmd' in got,
    got,
    "a list containing 'inner cmd'",
)
check_equal(
    'resolves escaped quotes so a nested wrapper unwraps to a real command',
    executed_segments('bash -c "bash -c \\"inner cmd\\""'),
    ['bash -c S', 'bash -c S', 'inner cmd'],
)

_cmd = 'deepest cmd'
for _ in range(5):
    _cmd = 'bash -c ' + json.dumps(_cmd)
got = executed_segments(_cmd)
check_all(
    'stops recursing at the depth cap instead of running away',
    [
        (len(got) == 4, got, 'a list of length 4'),
        ('deepest cmd' not in "\n".join(got), got, "no 'deepest cmd' in the joined result"),
    ],
)
check_equal(
    'falls back to the raw text when a quote is unterminated',
    executed_segments('bash -c "unterminated'),
    ['bash -c "unterminated'],
)
check_equal(
    'yields no wrapper segment when -c has no following word',
    executed_segments('bash -c'),
    ['bash -c'],
)

# ---------------------------------------------------------------------------
# wrapped_command_strings
# ---------------------------------------------------------------------------
for _label, cmd in [
    ('bash -c', 'bash -c "inner cmd"'),
    ('sh -c', "sh -c 'inner cmd'"),
    ('eval', 'eval "inner cmd"'),
]:
    check_equal(
        'returns the unquoted argument of a %s invocation' % _label,
        wrapped_command_strings(cmd),
        ['inner cmd'],
    )
check_equal(
    'recognizes a wrapper only at command position',
    wrapped_command_strings('echo bash -c "inner cmd"'),
    [],
)
check_equal(
    'does not let a leading env-assignment hide the wrapper behind it',
    wrapped_command_strings('FOO=1 bash -c "inner cmd"'),
    ['inner cmd'],
)
check_equal(
    'skips more than one leading assignment before the wrapper',
    wrapped_command_strings('FOO=1 BAR=2 sh -c "inner cmd"'),
    ['inner cmd'],
)

# ---------------------------------------------------------------------------
# strip_quoted_indexed — [label, input, expected (view, values) or None]
# The library returns a tuple; the TS compares against a JSON array, so the
# expected value here is the tuple form of the same pair.
# ---------------------------------------------------------------------------
INDEXED_CASES = [
    (
        'a double-quoted span becomes one placeholder carrying its value',
        'git commit -m "hello"',
        ('git commit -m ' + QUOTED_SPAN, ['hello']),
    ),
    (
        'a single-quoted span becomes one placeholder carrying its value',
        "git commit -m 'hello'",
        ('git commit -m ' + QUOTED_SPAN, ['hello']),
    ),
    (
        'two spans resolve to values in TEXT order',
        'echo "a" "b"',
        ('echo ' + QUOTED_SPAN + ' ' + QUOTED_SPAN, ['a', 'b']),
    ),
    (
        'a backslash-escaped space outside quotes becomes ESCAPED_BLANK',
        'git\\ commit',
        ('git' + ESCAPED_BLANK + 'commit', []),
    ),
    (
        'an escaped pipe outside quotes is still Q, same as strip_quoted',
        'git commit -m x\\|tail',
        ('git commit -m xQtail', []),
    ),
    ('an unterminated quote returns null, same as strip_quoted', 'git commit -m "oops', None),
    (
        'a literal QUOTED_SPAN codepoint outside quotes returns null',
        'echo ' + QUOTED_SPAN + ' && git add "a b"',
        None,
    ),
    (
        'a literal ESCAPED_BLANK codepoint outside quotes returns null',
        'echo ' + ESCAPED_BLANK + ' && git add "a b"',
        None,
    ),
]

for label, inp, want in INDEXED_CASES:
    check_equal(label, strip_quoted_indexed(inp), want)

# ---------------------------------------------------------------------------
# resolve_placeholders — [label, token, values, next_index, expected]
# ---------------------------------------------------------------------------
PLACEHOLDER_CASES = [
    (
        'round-trips a token holding TWO placeholders, index advances by two',
        QUOTED_SPAN + ' ' + QUOTED_SPAN,
        ['a', 'b'],
        0,
        ('a b', 2),
    ),
    (
        'a token with no placeholder is returned unchanged, index unchanged',
        'plain',
        ['a'],
        0,
        ('plain', 0),
    ),
    (
        'a surplus placeholder (more than remaining values) is left in place, '
        'index clamped at len(values)',
        QUOTED_SPAN + QUOTED_SPAN,
        ['a'],
        0,
        ('a' + QUOTED_SPAN, 1),
    ),
    ('ESCAPED_BLANK resolves to a real space', 'a' + ESCAPED_BLANK + 'b', [], 0, ('a b', 0)),
]

for label, token, values, next_index, want in PLACEHOLDER_CASES:
    check_equal(label, resolve_placeholders(token, values, next_index), want)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
