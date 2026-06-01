#!/usr/bin/env bats
# Tests for shared/list-plan-beads.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/shared/list-plan-beads.sh"
    TMP_DIR="$(mktemp -d)"
    export REPO_ROOT SCRIPT TMP_DIR
    export PATH="$TMP_DIR:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "returns only Plan: tasks from open beads" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[
  {"id": "t-1", "title": "Plan: Feature A",   "status": "open"},
  {"id": "t-2", "title": "Stage 1: Do thing", "status": "open"},
  {"id": "t-3", "title": "Story: Feature A",  "status": "open"},
  {"id": "t-4", "title": "Plan: Feature B",   "status": "open"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    ids=$(echo "$output" | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)])")
    [ "$ids" = "['t-1', 't-4']" ]
}

@test "passes --status=in_progress through to bd list" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--status=in_progress"* ]]; then
    echo '[{"id": "t-5", "title": "Plan: In progress plan", "status": "in_progress"}]'
else
    echo '[{"id": "t-1", "title": "Plan: Open plan", "status": "open"}]'
fi
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT" --status=in_progress
    [ "$status" -eq 0 ]
    ids=$(echo "$output" | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)])")
    [ "$ids" = "['t-5']" ]
}

@test "returns empty array when no Plan: tasks exist" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[
  {"id": "t-1", "title": "Stage 1: Do thing", "status": "open"},
  {"id": "t-2", "title": "Story: Feature A",  "status": "open"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "returns empty array when bd list returns empty" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "passes --json flag to bd list" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" != *"--json"* ]]; then
    echo "missing --json" >&2
    exit 1
fi
echo '[]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
}
