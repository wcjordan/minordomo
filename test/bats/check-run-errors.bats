#!/usr/bin/env bats
# Tests for shared/check-run-errors.py

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/check-run-errors.py"
    SUCCESS_FIXTURE="$REPO_ROOT/test/fixtures/prompt-output-success.txt"
    ERRORS_FIXTURE="$REPO_ROOT/test/fixtures/prompt-output-errors.txt"
    export SCRIPT SUCCESS_FIXTURE ERRORS_FIXTURE
}

# --- Multi-line markdown JSON format (real Jenkins build output) ---

@test "exits 0 for run log with no errors (build-81 style)" {
    run python3 "$SCRIPT" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
}

@test "exits 1 for run log with non-empty errors array (build-56 style)" {
    run python3 "$SCRIPT" "$ERRORS_FIXTURE"
    [ "$status" -eq 1 ]
}

# --- Compact single-line JSON format (claude-output-*.json result field format) ---

@test "exits 1 for inline JSON with status failure" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" \
        "$REPO_ROOT/test/fixtures/claude-output-error.json"
    INLINE_OUTPUT="$output"
    TMPFILE="$(mktemp)"
    echo "$INLINE_OUTPUT" > "$TMPFILE"
    run python3 "$SCRIPT" "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 1 ]
}

@test "exits 0 for inline JSON with status success and empty errors" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" \
        "$REPO_ROOT/test/fixtures/claude-output-success.json"
    INLINE_OUTPUT="$output"
    TMPFILE="$(mktemp)"
    echo "$INLINE_OUTPUT" > "$TMPFILE"
    run python3 "$SCRIPT" "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 0 ]
}

# --- Edge cases ---

@test "exits 0 when file does not exist" {
    run python3 "$SCRIPT" "/nonexistent/path/to/prompt-output.txt"
    [ "$status" -eq 0 ]
}

@test "exits 0 when file has no JSON" {
    TMPFILE="$(mktemp)"
    echo "=== Token Usage ===" > "$TMPFILE"
    echo "  Input tokens: 1,234" >> "$TMPFILE"
    run python3 "$SCRIPT" "$TMPFILE"
    rm -f "$TMPFILE"
    [ "$status" -eq 0 ]
}
