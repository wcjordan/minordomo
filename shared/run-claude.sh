#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION_DONE_FILE="${CLAUDE_SESSION_DONE_FILE:-/tmp/claude-session-done}"

rm -f "$SESSION_DONE_FILE"

# Stream transcript alongside claude; suppress raw PTY output (escape codes).
python3 "$SCRIPT_DIR/stream-transcript.py" "$PWD" &
STREAM_PID=$!

# Run claude in a PTY so interactive mode works. script(1) allocates the PTY;
# the prompt is read inside the -c subshell so arbitrary content never passes
# through shell quoting on the command line.
# shellcheck disable=SC2016  # single quotes intentional: expansion happens in the script(1) subshell
script -q -e -c 'PROMPT=$(cat /tmp/system-prompt.md); exec claude --dangerously-skip-permissions "$PROMPT"' /dev/null > /dev/null 2>&1 &
SCRIPT_PID=$!
echo "$SCRIPT_PID" > /tmp/claude-script-pid

# Background monitor: the stop hook writes /tmp/claude-session-done when the
# task is complete (or needs-input). Kill the script process once that signal
# appears, giving the hook a moment to finish its own cleanup first.
(
    while kill -0 "$SCRIPT_PID" 2>/dev/null; do
        if [ -f "$SESSION_DONE_FILE" ]; then
            sleep 0.5
            kill "$SCRIPT_PID" 2>/dev/null || true
            exit 0
        fi
        sleep 0.5
    done
) &
MONITOR_PID=$!

wait "$SCRIPT_PID" || CLAUDE_EXIT=$?
kill "$MONITOR_PID" 2>/dev/null || true
wait "$MONITOR_PID" 2>/dev/null || true
kill "$STREAM_PID" 2>/dev/null || true
wait "$STREAM_PID" 2>/dev/null || true

CLAUDE_EXIT=${CLAUDE_EXIT:-0}
rm -f /tmp/claude-script-pid

# SIGTERM exit (143) triggered by monitor means the stop hook declared done —
# not a crash. Treat it as success.
if [ "${CLAUDE_EXIT}" -eq 143 ] && [ -f "$SESSION_DONE_FILE" ]; then
    exit 0
fi
exit "${CLAUDE_EXIT}"
