#!/usr/bin/env bats
# Tests for shared/planner-error-exit.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/planner-error-exit.sh"
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

@test "happy path: both steps succeed" {
    run "$SCRIPT" beads-123 myrepo 42 "Planning agent crashed"
    [ "$status" -eq 0 ]
}

@test "GH comment fails: error is logged, beads reset still runs, exits 0" {
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "issue" ] && [ "$2" = "comment" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/bd-was-called"
exit 0
EOF
    chmod +x "$MOCKS/bd"

    run "$SCRIPT" beads-123 myrepo 42 "Planning agent crashed"
    [ "$status" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/bd-was-called" ]
    echo "$output" | grep -qi "comment"
}

@test "beads-write.sh fails: exits non-zero" {
    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
if [ "$1" = "update" ]; then
    exit 1
fi
exit 0
EOF
    chmod +x "$MOCKS/bd"

    run "$SCRIPT" beads-123 myrepo 42 "Planning agent crashed"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "beads"
}

@test "missing argument: exits with status 2 without calling gh or bd" {
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

    run "$SCRIPT" beads-123 myrepo 42
    [ "$status" -eq 2 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-was-called" ]
    [ ! -f "$BATS_TEST_TMPDIR/bd-was-called" ]
}

@test "empty gh_issue_number: GH comment is skipped, beads reset still runs, exits 0" {
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

    run "$SCRIPT" beads-123 myrepo "" "Planning agent crashed before reading GH issue"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-was-called" ]
    [ -f "$BATS_TEST_TMPDIR/bd-was-called" ]
}
