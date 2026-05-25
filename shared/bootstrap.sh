#!/usr/bin/env bash
# Runs the standard agent setup sequence in order.
# Usage: source shared/bootstrap.sh <planning|worker>
# Source this script; do not execute it directly.

set -euo pipefail

MODE="${1:?Usage: source shared/bootstrap.sh <planning|worker>}"

source shared/setup-env.sh
source shared/setup-claude.sh
source shared/setup-workspace.sh "$MODE"
