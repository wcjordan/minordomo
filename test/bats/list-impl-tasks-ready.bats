#!/usr/bin/env bats
# Tests for shared/list-impl-tasks-ready.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/shared/list-impl-tasks-ready.sh"
    TMP_DIR="$(mktemp -d)"
    export REPO_ROOT SCRIPT TMP_DIR
    export PATH="$TMP_DIR:$PATH"
}

teardown() {
    rm -rf "$TMP_DIR"
}

@test "returns only impl tasks when list contains mixed types" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[
  {"id": "t-1", "title": "Stage 1: Do thing",    "status": "open"},
  {"id": "t-2", "title": "Plan: Some feature",    "status": "open"},
  {"id": "t-3", "title": "Story: Some feature",   "status": "open"},
  {"id": "t-4", "title": "Stage 2: Do other thing","status": "open"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    ids=$(echo "$output" | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)])")
    [ "$ids" = "['t-1', 't-4']" ]
}

@test "returns empty array when no ready tasks exist" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "returns empty array when all ready tasks are Plan or Story" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
echo '[
  {"id": "t-1", "title": "Plan: Feature A",  "status": "open"},
  {"id": "t-2", "title": "Story: Feature A", "status": "open"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "passes --json flag to bd ready" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
# Fail unless --json is present
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
