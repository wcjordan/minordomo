#!/usr/bin/env bats
# Tests for shared/post-gh-issue-comment.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/post-gh-issue-comment.sh"
    export SCRIPT

    MOCKS="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCKS"
    export PATH="$MOCKS:$PATH"

    # Default gh mock: succeeds for all calls
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCKS/gh"
}

@test "happy path: posts comment successfully" {
    run "$SCRIPT" 210 minordomo "Worker stopped at step 3"
    [ "$status" -eq 0 ]
}

@test "gh command failure: exits non-zero with descriptive message" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCKS/gh"

    run "$SCRIPT" 210 minordomo "Worker stopped at step 3"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "comment"
}

@test "missing argument: exits non-zero without calling gh" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/gh-was-called"
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$SCRIPT" 210 minordomo
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-was-called" ]
}
