#!/usr/bin/env bash
# Deploys Claude agent permissions.
# Source this script; do not execute it directly.

set -euo pipefail

mkdir -p ~/.claude/hooks
cp shared/agent-settings.json ~/.claude/settings.json
cp shared/pre-bash-guard.sh ~/.claude/hooks/pre-bash-guard.sh
