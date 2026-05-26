#!/usr/bin/env bash
# Wraps a beads write operation with dolt pull before and push after.
# Pull/push output goes to stderr so stdout (e.g. --json) passes through cleanly.
# Usage: shared/beads-write.sh <bd subcommand> [args...]
#   e.g. shared/beads-write.sh create "Story: ..." --json
#        shared/beads-write.sh close "beads-123"
#        shared/beads-write.sh update "beads-123" --claim

set -euo pipefail

bd dolt pull >&2
bd "$@"
bd dolt push >&2
