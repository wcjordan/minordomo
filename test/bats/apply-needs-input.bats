#!/usr/bin/env bats
# Tests for shared/apply-needs-input.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/apply-needs-input.sh"
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
