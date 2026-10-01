#!/bin/bash
# Direct unit cases for plugins/seyag/hooks/lib/shell_quotes.py, ported from
# Tzurot's shellQuotes.test.ts. The cases live in tests/shell_quotes_cases.py.
# Usage: tests/shell_quotes.probe.sh   (from anywhere)
# SHELL_QUOTES_LIB_DIR overrides the library directory (positive-control use).

set -uo pipefail
# Keep the import from dropping a __pycache__ beside the library.
export PYTHONDONTWRITEBYTECODE=1
python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shell_quotes_cases.py"
exit $?
