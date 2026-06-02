#!/usr/bin/env bats
# Tests for shared/worker-error-exit.sh

REPO_ROOT=""
MOCKS=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOCKS="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCKS"
    export PATH="$MOCKS:$PATH"

    # Default bd mock: get-story-key.sh happy path + beads-write.sh happy path
    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "show")
        case "$2" in
            "test-1.1")
                echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
                ;;
            "test-1")
                echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "open", "parent": null}]'
                ;;
            *)
                echo "[]"
                ;;
        esac
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCKS/bd"

    # Default gh mock: succeeds
    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCKS/gh"
}

teardown() {
    rm -rf "$MOCKS"
}

@test "happy path: all 3 steps succeed, needs-input label applied" {
    gh_label_called="$BATS_TEST_TMPDIR/gh-label-called"

    cat > "$MOCKS/gh" << EOF
#!/usr/bin/env bash
if [ "\$1" = "issue" ] && [ "\$2" = "edit" ]; then
    for arg in "\$@"; do
        if [ "\$arg" = "needs-input" ]; then
            touch "$gh_label_called"
        fi
    done
fi
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo" "Worker failed at step 3"
    [ "$status" -eq 0 ]
    [ -f "$gh_label_called" ]
}

@test "get-story-key.sh fails: GH comment skipped, beads reset still called" {
    beads_reset_called="$BATS_TEST_TMPDIR/beads-reset-called"
    gh_called="$BATS_TEST_TMPDIR/gh-was-called"

    cat > "$MOCKS/bd" << EOF
#!/usr/bin/env bash
case "\$1" in
    "show") exit 1 ;;
    "update")
        touch "$beads_reset_called"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << EOF
#!/usr/bin/env bash
touch "$gh_called"
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo" "Worker failed"
    [ "$status" -eq 0 ]
    [ -f "$beads_reset_called" ]
    [ ! -f "$gh_called" ]
}

@test "gh issue edit fails: label failure is best-effort, comment and beads reset still run" {
    beads_reset_called="$BATS_TEST_TMPDIR/beads-reset-called"
    gh_comment_called="$BATS_TEST_TMPDIR/gh-comment-called"

    cat > "$MOCKS/bd" << EOF
#!/usr/bin/env bash
case "\$1" in
    "show")
        case "\$2" in
            "test-1.1")
                echo '[{"id": "test-1.1", "title": "Stage 1", "description": null, "status": "in_progress", "parent": "test-1"}]'
                ;;
            "test-1")
                echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "open", "parent": null}]'
                ;;
            *) echo "[]" ;;
        esac
        ;;
    "update")
        touch "$beads_reset_called"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << EOF
#!/usr/bin/env bash
if [ "\$1" = "issue" ] && [ "\$2" = "edit" ]; then
    exit 1
fi
touch "$gh_comment_called"
exit 0
EOF
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo" "Worker failed"
    [ "$status" -eq 0 ]
    [ -f "$beads_reset_called" ]
    [ -f "$gh_comment_called" ]
}

@test "post-gh-issue-comment.sh fails: logged, beads reset still called" {
    beads_reset_called="$BATS_TEST_TMPDIR/beads-reset-called"

    cat > "$MOCKS/bd" << EOF
#!/usr/bin/env bash
case "\$1" in
    "show")
        case "\$2" in
            "test-1.1")
                echo '[{"id": "test-1.1", "title": "Stage 1", "description": null, "status": "in_progress", "parent": "test-1"}]'
                ;;
            "test-1")
                echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "open", "parent": null}]'
                ;;
            *) echo "[]" ;;
        esac
        ;;
    "update")
        touch "$beads_reset_called"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo" "Worker failed"
    [ "$status" -eq 0 ]
    [ -f "$beads_reset_called" ]
}

@test "beads-write.sh fails: exits non-zero" {
    cat > "$MOCKS/bd" << 'EOF'
#!/usr/bin/env bash
case "$1" in
    "show")
        case "$2" in
            "test-1.1")
                echo '[{"id": "test-1.1", "title": "Stage 1", "description": null, "status": "in_progress", "parent": "test-1"}]'
                ;;
            "test-1")
                echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "open", "parent": null}]'
                ;;
            *) echo "[]" ;;
        esac
        ;;
    "update") exit 1 ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$MOCKS/bd"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo" "Worker failed"
    [ "$status" -ne 0 ]
}

@test "missing argument: exits non-zero without calling gh or bd" {
    cat > "$MOCKS/gh" << EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/gh-was-called"
exit 0
EOF
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << EOF
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/bd-was-called"
exit 0
EOF
    chmod +x "$MOCKS/bd"

    run "$REPO_ROOT/shared/worker-error-exit.sh" "test-1.1" "myrepo"
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/gh-was-called" ]
    [ ! -f "$BATS_TEST_TMPDIR/bd-was-called" ]
}
