#!/bin/bash
set -euo pipefail

# Pass the prompt file as the initial user message so Claude begins work
# immediately on launch. --dangerously-skip-permissions is required for
# interactive mode (the bypass dialog is pre-accepted via .claude.json).
#
# Using a variable assignment avoids word-splitting and special-character
# issues that would occur with inline "$(cat ...)" expansion.
PROMPT=$(cat /tmp/system-prompt.md)
exec claude --dangerously-skip-permissions "$PROMPT"
