#!/usr/bin/env bats
# Tests for shared/check-open-task-prs.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/check-open-task-prs.sh"
    export SCRIPT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "open task PR present: exits 0 and prints head branch name" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '[{"headRefName": "task/minordomo-abc.3"}]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36
    [ "$status" -eq 0 ]
    [ "$output" = "task/minordomo-abc.3" ]
}

@test "no open PRs: exits 1 and produces no output" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "non-task open PRs only: exits 1 and produces no output" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '[{"headRefName": "renovate/foo"}, {"headRefName": "fix/some-bug"}]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "wrong argument count: exits 2 without calling gh" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
touch "$TMP_DIR/gh-was-called"
echo '[]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo
    [ "$status" -eq 2 ]
    [ ! -f "$TMP_DIR/gh-was-called" ]
}
