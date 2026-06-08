#!/usr/bin/env bats
# Tests for shared/report-token-usage.py

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SUCCESS_FIXTURE="$REPO_ROOT/test/fixtures/claude-output-success.json"
    ERROR_FIXTURE="$REPO_ROOT/test/fixtures/claude-output-error.json"
    export SUCCESS_FIXTURE ERROR_FIXTURE
}

@test "prints token usage section header" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "=== Token Usage ==="
}

@test "prints input tokens from success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Input tokens:.*12,345"
}

@test "prints cache read tokens from success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Cache read tokens:.*40,000"
}

@test "prints output tokens from success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Output tokens:.*3,456"
}

@test "prints cost from success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Cost (USD):.*0.1234"
}

@test "prints duration from success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Duration:.*42.1s"
}

@test "exits 0 on success fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$SUCCESS_FIXTURE"
    [ "$status" -eq 0 ]
}

@test "exits 0 on error fixture (does not propagate is_error)" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "$ERROR_FIXTURE"
    [ "$status" -eq 0 ]
}

@test "exits 0 when given nonexistent file" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "/nonexistent/path/to/file.json"
    [ "$status" -eq 0 ]
}

@test "prints warning when file does not exist" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" "/nonexistent/path/to/file.json"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "warning"
}

# --- --transcript flag (Claude Code JSONL transcript mode) ---

@test "--transcript: exits 0 on success transcript fixture" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
}

@test "--transcript: prints agent output section" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "=== Agent Output ==="
}

@test "--transcript: prints token usage section header" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "=== Token Usage ==="
}

@test "--transcript: prints input tokens summed from transcript" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Input tokens:.*12,345"
}

@test "--transcript: prints cache read tokens summed from transcript" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Cache read tokens:.*40,000"
}

@test "--transcript: prints output tokens summed from transcript" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Output tokens:.*3,456"
}

@test "--transcript: omits Cost (USD) line (not available in transcript)" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Cost (USD)"
}

@test "--transcript: omits Duration line (not available in transcript)" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Duration:"
}

@test "--transcript: exits 0 when transcript file does not exist" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "/nonexistent/transcript.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "warning"
}

@test "--transcript: prints last assistant text content" {
    run python3 "$REPO_ROOT/shared/report-token-usage.py" --transcript "$REPO_ROOT/test/fixtures/claude-transcript-success.jsonl"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "I'll start by reading the beads task"
}
