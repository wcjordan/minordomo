#!/usr/bin/env bats
# Tests for shared/fetch-claude-usage.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"

    # Speed up tests: minimal delays
    export FETCH_CLAUDE_USAGE_STARTUP_DELAY=0.1
    export FETCH_CLAUDE_USAGE_TIMEOUT=10
    export FETCH_CLAUDE_USAGE_POLL_INTERVAL=0.1
    export FETCH_CLAUDE_USAGE_POLL_MAX=30

    SCRIPT="$REPO_ROOT/shared/fetch-claude-usage.sh"
    export SCRIPT
}

teardown() {
    rm -rf "$TMP_DIR"
}

# Create a mock claude that emits /usage output and exits on "exit" command.
make_mock_claude() {
    local pct="${1:-2}"
    cat > "$TMP_DIR/claude" <<EOF
#!/bin/bash
while IFS= read -r line; do
    case "\$line" in
        /usage*)
            printf 'Claude is ready!\n'
            printf 'Current week (all models)\n'
            printf '\xe2\x96\x88  %s%% used\n' "$pct"
            printf 'Resets Jun 21 at 8pm (America/New_York)\n'
            ;;
        exit)
            exit 0
            ;;
    esac
done
EOF
    chmod +x "$TMP_DIR/claude"
}

@test "fetch-claude-usage: extracts 2% from sample output" {
    make_mock_claude 2
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "fetch-claude-usage: extracts 50% from sample output" {
    make_mock_claude 50
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "50" ]
}

@test "fetch-claude-usage: extracts 100% from sample output" {
    make_mock_claude 100
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "100" ]
}

@test "fetch-claude-usage: exits non-zero when output cannot be parsed" {
    # Mock claude that outputs nothing useful
    cat > "$TMP_DIR/claude" <<'EOF'
#!/bin/bash
echo "Something went wrong"
exit 0
EOF
    chmod +x "$TMP_DIR/claude"
    run "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "fetch-claude-usage: handles ANSI escape codes in output" {
    # Mock claude that emits ANSI codes around the usage line
    cat > "$TMP_DIR/claude" <<'EOF'
#!/bin/bash
while IFS= read -r line; do
    case "$line" in
        /usage*)
            printf '\x1b[1mCurrent week\x1b[0m (all models)\n'
            printf '\x1b[32m  15%% used\x1b[0m\n'
            printf 'Resets Jun 21 at 8pm\n'
            ;;
        exit)
            exit 0
            ;;
    esac
done
EOF
    chmod +x "$TMP_DIR/claude"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "15" ]
}
