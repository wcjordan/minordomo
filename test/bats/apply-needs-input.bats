#!/usr/bin/env bats
# Tests for shared/apply-needs-input.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/apply-needs-input.sh"
    DISCORD_SEND_STUB="$REPO_ROOT/test/fixtures/discord-send-stub.js"
    export SCRIPT DISCORD_SEND_STUB

    MOCKS="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCKS"
    export PATH="$MOCKS:$PATH"

    # Default gh mock: succeeds for all calls
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCKS/gh"

    # Default bd mock: succeeds for all calls (used by beads-write.sh)
    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCKS/bd"
}

@test "happy path: all three steps succeed" {
    run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -eq 0 ]
}

@test "failure on label step: gh issue edit fails -> exits non-zero" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "edit" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "label"
}

@test "failure on comment step: gh issue comment fails -> exits non-zero" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "comment" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "comment"
}

@test "failure on beads reset step: bd update fails -> exits non-zero" {
    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "update" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCKS/bd"

    run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "beads"
}

@test "missing argument: exits non-zero without calling gh or bd" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/gh-was-called"
exit 0
EOF
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/bd-was-called"
exit 0
EOF
    chmod +x "$MOCKS/bd"

    run "$SCRIPT" myrepo 42 beads-123
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-was-called" ]
    [ ! -f "$BATS_TEST_TMPDIR/bd-was-called" ]
}

@test "sends Discord notification when DISCORD_WEBHOOK_URL is set and all three steps succeed" {
    DISCORD_STUB_OUT="$BATS_TEST_TMPDIR/discord-out.txt"
    run env DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/test-token" \
        DISCORD_SEND_SCRIPT="$DISCORD_SEND_STUB" \
        DISCORD_STUB_OUT="$DISCORD_STUB_OUT" \
        "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -eq 0 ]
    grep -qF "Human input requested: https://github.com/wcjordan/myrepo/issues/42" "$DISCORD_STUB_OUT"
}

@test "does not fail when DISCORD_WEBHOOK_URL is unset" {
    run env -u DISCORD_WEBHOOK_URL \
        DISCORD_SEND_SCRIPT="$DISCORD_SEND_STUB" \
        "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -eq 0 ]
}

@test "required steps run even when Discord send fails" {
    FAILING_DISCORD_STUB="$BATS_TEST_TMPDIR/failing-discord-send.js"
    cat > "$FAILING_DISCORD_STUB" << 'EOF'
#!/usr/bin/env node
process.exit(1);
EOF

    LABEL_CALLED="$BATS_TEST_TMPDIR/label-called"
    COMMENT_CALLED="$BATS_TEST_TMPDIR/comment-called"
    BEADS_RESET_CALLED="$BATS_TEST_TMPDIR/beads-reset-called"

    cat > "$MOCKS/gh" << MOCKEOF
#!/usr/bin/env bash
if [ "\$1" = "issue" ] && [ "\$2" = "edit" ]; then
    touch "$LABEL_CALLED"
fi
if [ "\$1" = "issue" ] && [ "\$2" = "comment" ]; then
    touch "$COMMENT_CALLED"
fi
exit 0
MOCKEOF
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << MOCKEOF
#!/usr/bin/env bash
if [ "\$1" = "update" ]; then
    touch "$BEADS_RESET_CALLED"
fi
exit 0
MOCKEOF
    chmod +x "$MOCKS/bd"

    run env DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/test-token" \
        DISCORD_SEND_SCRIPT="$FAILING_DISCORD_STUB" \
        "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -eq 0 ]
    [ -f "$LABEL_CALLED" ]
    [ -f "$COMMENT_CALLED" ]
    [ -f "$BEADS_RESET_CALLED" ]
}
