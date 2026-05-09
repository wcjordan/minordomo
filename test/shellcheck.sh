#!/usr/bin/env bash
# Lint all shell scripts in shared/ with shellcheck.
# Prereq: shellcheck (brew install shellcheck)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shellcheck shared/*.sh
echo "shellcheck: OK"
