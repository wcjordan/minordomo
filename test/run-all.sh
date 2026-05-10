#!/usr/bin/env bash
# Run all tests, installing missing dependencies automatically.
# Usage: bash test/run-all.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

PASS=0
FAIL=0

section() { echo; echo "=== $* ==="; }
ok()      { echo "  PASS  $*"; PASS=$((PASS + 1)); }
fail()    { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
section "Dependencies"

if ! command -v shellcheck &>/dev/null; then
    echo "  Installing shellcheck..."
    brew install shellcheck
fi
ok "shellcheck $(shellcheck --version | awk 'NR==2{print $2}')"

if ! command -v bats &>/dev/null; then
    echo "  Installing bats-core..."
    brew install bats-core
fi
ok "bats $(bats --version)"

if ! python3 -c "import yaml" &>/dev/null; then
    echo "  Installing pyyaml..."
    pip3 install pyyaml -q
fi
ok "pyyaml $(python3 -c 'import yaml; print(yaml.__version__)')"

# ---------------------------------------------------------------------------
# shellcheck
# ---------------------------------------------------------------------------
section "shellcheck"
if bash test/shellcheck.sh; then
    ok "shared/*.sh"
else
    fail "shared/*.sh"
fi

# ---------------------------------------------------------------------------
# validate-prompts
# ---------------------------------------------------------------------------
section "validate-prompts"
if python3 test/validate-prompts.py; then
    ok "system-prompt.md files"
else
    fail "system-prompt.md files"
fi

# ---------------------------------------------------------------------------
# dry-run
# ---------------------------------------------------------------------------
section "dry-run"
if bash test/dry-run.sh; then
    ok "setup chain"
else
    fail "setup chain"
fi

# ---------------------------------------------------------------------------
# bats unit tests
# ---------------------------------------------------------------------------
section "bats"
if bats test/bats/; then
    ok "bats suite"
else
    fail "bats suite"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
