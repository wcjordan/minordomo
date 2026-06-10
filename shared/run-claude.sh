#!/bin/bash
set -euo pipefail

pwd

# script(1) allocates a PTY so claude runs in interactive mode.
# The prompt file is read inside the -c subshell so its content never
# passes through shell quoting — arbitrary markdown/code in the prompt
# can't break the command line. claude receives the content as the
# initial user message, which kicks off work immediately on launch.
# --dangerously-skip-permissions bypass dialog is pre-accepted via .claude.json.
exec script -q -e -c 'PROMPT=$(cat /tmp/system-prompt.md); exec claude --dangerously-skip-permissions "$PROMPT"' /dev/null
