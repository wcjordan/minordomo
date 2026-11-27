#!/usr/bin/env bats
# Tests for shared/list-impl-tasks-ready.sh
bats_require_minimum_version 1.5.0

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
if [ "$1" = "show" ]; then
    echo '[{"id": "t-3", "title": "Story: Some feature"}]'
    exit 0
fi
echo '[
  {"id": "t-1", "title": "Stage 1: Do thing",    "status": "open", "parent": "t-3"},
  {"id": "t-2", "title": "Plan: Some feature",    "status": "open", "parent": "t-3"},
  {"id": "t-3", "title": "Story: Some feature",   "status": "open"},
  {"id": "t-4", "title": "Stage 2: Do other thing","status": "open", "parent": "t-3"}
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

@test "skips tasks with no parent" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "show" ]; then
    echo '[{"id": "s-1", "title": "Story: Feature"}]'
    exit 0
fi
echo '[
  {"id": "s-1.1", "title": "Stage 1: Real stage", "status": "open", "parent": "s-1"},
  {"id": "orphan", "title": "Hand-filed follow-up", "status": "open"},
  {"id": "orphan-null", "title": "Another follow-up", "status": "open", "parent": null}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    ids=$(echo "$output" | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)])")
    [ "$ids" = "['s-1.1']" ]
    [[ "$stderr" == *"skipping orphan: no parent Story bead"* ]]
    [[ "$stderr" == *"skipping orphan-null: no parent Story bead"* ]]
}

@test "skips tasks whose parent is not a Story bead" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "show" ]; then
    case "$2" in
        s-1) echo '[{"id": "s-1", "title": "Story: Feature"}]' ;;
        e-1) echo '[{"id": "e-1", "title": "Some epic"}]' ;;
    esac
    exit 0
fi
echo '[
  {"id": "s-1.1", "title": "Stage 1: Real stage", "status": "open", "parent": "s-1"},
  {"id": "e-1.1", "title": "Child of non-Story", "status": "open", "parent": "e-1"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    ids=$(echo "$output" | python3 -c "import json,sys; print([t['id'] for t in json.load(sys.stdin)])")
    [ "$ids" = "['s-1.1']" ]
    [[ "$stderr" == *"skipping e-1.1: parent e-1 is not a Story bead"* ]]
}

@test "skips tasks whose parent lookup fails" {
    cat > "$TMP_DIR/bd" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "show" ]; then
    echo "not found" >&2
    exit 1
fi
echo '[{"id": "x-1.1", "title": "Stage 1: Stage", "status": "open", "parent": "x-1"}]'
EOF
    chmod +x "$TMP_DIR/bd"

    run --separate-stderr bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "looks up each parent only once" {
    cat > "$TMP_DIR/bd" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "show" ]; then
    echo "\$2" >> "$TMP_DIR/show-calls"
    echo '[{"id": "s-1", "title": "Story: Feature"}]'
    exit 0
fi
echo '[
  {"id": "s-1.1", "title": "Stage 1: A", "status": "open", "parent": "s-1"},
  {"id": "s-1.2", "title": "Stage 2: B", "status": "open", "parent": "s-1"}
]'
EOF
    chmod +x "$TMP_DIR/bd"

    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "$TMP_DIR/show-calls" | tr -d ' ')" -eq 1 ]
}
