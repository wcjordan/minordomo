#!/usr/bin/env bats
# Tests for shared/pipeline-helpers.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ---------------------------------------------------------------------------
# beads_task_id_by_title
# ---------------------------------------------------------------------------

@test "beads_task_id_by_title: returns empty when title not found" {
    cat > "$TMP_DIR/bd" << 'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; beads_task_id_by_title 'Nonexistent Title'"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "beads_task_id_by_title: finds open task by exact title" {
    cat > "$TMP_DIR/bd" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"in_progress"* ]]; then
    echo '[]'
else
    echo '[{"id": "task-open-1", "title": "My Task Title", "status": "open"}]'
fi
EOF
    chmod +x "$TMP_DIR/bd"

    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; beads_task_id_by_title 'My Task Title'"
    [ "$status" -eq 0 ]
    [ "$output" = "task-open-1" ]
}

@test "beads_task_id_by_title: finds in_progress task by exact title" {
    cat > "$TMP_DIR/bd" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"in_progress"* ]]; then
    echo '[{"id": "task-inprog-2", "title": "My Task Title", "status": "in_progress"}]'
else
    echo '[]'
fi
EOF
    chmod +x "$TMP_DIR/bd"

    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; beads_task_id_by_title 'My Task Title'"
    [ "$status" -eq 0 ]
    [ "$output" = "task-inprog-2" ]
}

# ---------------------------------------------------------------------------
# has_needs_input
# ---------------------------------------------------------------------------

@test "has_needs_input: returns 0 when needs-input label is present" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '{"labels": [{"name": "needs-input"}, {"name": "bug"}]}'
EOF
    chmod +x "$TMP_DIR/gh"

    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; has_needs_input 'myrepo' '42'"
    [ "$status" -eq 0 ]
}

@test "has_needs_input: returns 1 when needs-input label is absent" {
    cat > "$TMP_DIR/gh" << 'EOF'
#!/usr/bin/env bash
echo '{"labels": [{"name": "bug"}, {"name": "enhancement"}]}'
EOF
    chmod +x "$TMP_DIR/gh"

    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; has_needs_input 'myrepo' '42'"
    [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# extract_priority
# ---------------------------------------------------------------------------

@test "extract_priority: returns matched P-label" {
    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; extract_priority '[{\"name\": \"P1\"}, {\"name\": \"bug\"}]'"
    [ "$status" -eq 0 ]
    [ "$output" = "P1" ]
}

@test "extract_priority: returns P2 as default when no P-label present" {
    run bash -c "source '$REPO_ROOT/shared/pipeline-helpers.sh'; extract_priority '[{\"name\": \"bug\"}, {\"name\": \"enhancement\"}]'"
    [ "$status" -eq 0 ]
    [ "$output" = "P2" ]
}
