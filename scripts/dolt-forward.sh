#!/usr/bin/env bash
# Port-forward the in-cluster Dolt server for local bd use.
#
# Usage:
#   scripts/dolt-forward.sh bd list --status=open   # one-shot: run command, then tear down
#   scripts/dolt-forward.sh                         # interactive: subshell with env pre-set

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./dolt-setup.sh
source "$SCRIPT_DIR/dolt-setup.sh"

# In Jenkins, Dolt is reachable directly via k8s DNS — no port-forward needed.
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    exec "$@"
fi

dolt_setup

if [[ $# -gt 0 ]]; then
    "$@"
else
    echo "Dolt port-forward active on localhost:${BEADS_DOLT_SERVER_PORT}"
    echo "Type 'exit' to stop."
    "$SHELL"
fi
