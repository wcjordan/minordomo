#!/bin/bash
# Fetch current Claude weekly usage percentage via PTY interaction.
# Exits 0 and prints integer percentage to stdout on success.
# Exits non-zero if usage cannot be parsed.
set -euo pipefail

OUTPUT="$(mktemp)"
STARTUP_DELAY="${FETCH_CLAUDE_USAGE_STARTUP_DELAY:-4}"
TIMEOUT="${FETCH_CLAUDE_USAGE_TIMEOUT:-30}"
POLL_INTERVAL="${FETCH_CLAUDE_USAGE_POLL_INTERVAL:-0.5}"
POLL_MAX="${FETCH_CLAUDE_USAGE_POLL_MAX:-20}"

cleanup() {
    rm -f "$OUTPUT"
}
trap cleanup EXIT

# Run claude in a PTY via script(1). Send /usage after startup delay,
# poll the output file for "Current week", then send exit.
(
    sleep "$STARTUP_DELAY"
    printf '/usage\n'
    # Poll for output up to POLL_MAX iterations, then exit regardless
    i=0
    while [ "$i" -lt "$POLL_MAX" ]; do
        grep -q 'Current week' "$OUTPUT" 2>/dev/null && break
        sleep "$POLL_INTERVAL"
        i=$((i + 1))
    done
    printf 'exit\n'
    sleep 1
) | timeout "$TIMEOUT" script -q -e -c 'claude --dangerously-skip-permissions' "$OUTPUT" > /dev/null 2>&1 || true

# Strip ANSI CSI/OSC escape sequences, carriage returns, then all non-ASCII bytes
# (removes box-drawing characters like █ which are multibyte UTF-8)
CLEANED="$(
    LC_ALL=C sed \
        -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' \
        -e 's/\x1b][^\x07]*\x07//g' \
        -e 's/\x1b.//g' \
        -e 's/\r//g' \
        "$OUTPUT" \
    | LC_ALL=C tr -cd '[:print:]\n'
)"

# Extract integer percentage from "N% used" line following "Current week"
PCT="$(printf '%s\n' "$CLEANED" | awk '
    /Current week/ { found=1; next }
    found && /[0-9]+% used/ {
        match($0, /[0-9]+/)
        print substr($0, RSTART, RLENGTH)
        exit
    }
')"

if [ -z "$PCT" ]; then
    echo "fetch-claude-usage: could not parse usage percentage from output" >&2
    exit 1
fi

echo "$PCT"
