#!/usr/bin/env bats
# Tests for shared/check-pr-merged.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/check-pr-merged.sh"
    export SCRIPT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "merged case: exits 0 and prints PR number" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '[{"number": 42}]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36 minordomo-abc1.2
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "not-merged case: exits 1 and produces no output" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36 minordomo-abc1.2
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "wrong argument count: exits non-zero without calling gh" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
touch "$TMP_DIR/gh-was-called"
echo '[]'
EOF
    chmod +x "$TMP_DIR/gh"

    run "$SCRIPT" myrepo MDOMO-36
    [ "$status" -ne 0 ]
    [ ! -f "$TMP_DIR/gh-was-called" ]
}
