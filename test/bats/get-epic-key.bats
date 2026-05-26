#!/usr/bin/env bats
# Tests for shared/get-epic-key.sh
# Run from repo root: bats test/bats/get-epic-key.bats

REPO_ROOT=""
MOCKS=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    MOCKS="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCKS"
    export PATH="$MOCKS:$PATH"
}

teardown() {
    rm -rf "$MOCKS"
}

# ---------------------------------------------------------------------------
# Happy path: GH Issue URL is in the task's own description
# ---------------------------------------------------------------------------

@test "happy path: URL in task description" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
# bd show <id> --json
echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "in_progress", "parent": "test-1"}]'
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
# gh issue view 42 --repo wcjordan/myrepo --json comments
echo '{"comments": [{"body": "Jira Epic: MDOMO-10"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1.1" "myrepo"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = "MDOMO-10" ]
    [ "$(echo "$output" | sed -n '2p')" = "42" ]
}

# ---------------------------------------------------------------------------
# Happy path: GH Issue URL is only in the parent's description
# ---------------------------------------------------------------------------

@test "happy path: URL in parent description only" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$2" in
    "test-1.1")
        echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
        ;;
    "test-1")
        echo '[{"id": "test-1", "title": "Plan: Feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/99", "status": "open", "parent": null}]'
        ;;
    *)
        echo "[]"
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": [{"body": "Jira Epic: MDOMO-20"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1.1" "myrepo"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = "MDOMO-20" ]
    [ "$(echo "$output" | sed -n '2p')" = "99" ]
}

# ---------------------------------------------------------------------------
# Failure: no GH Issue URL in task or parent
# ---------------------------------------------------------------------------

@test "failure: no GH Issue URL found" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$2" in
    "test-1.1")
        echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
        ;;
    "test-1")
        echo '[{"id": "test-1", "title": "Plan: Feature", "description": "No URL here", "status": "open", "parent": null}]'
        ;;
    *)
        echo "[]"
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": []}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1.1" "myrepo"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "No GH Issue URL"
}

# ---------------------------------------------------------------------------
# Failure: URL found but no Jira Epic comment
# ---------------------------------------------------------------------------

@test "failure: no Jira Epic comment in GH issue" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "in_progress", "parent": "test-1"}]'
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": [{"body": "Just a regular comment, no epic here"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1.1" "myrepo"
    [ "$status" -ne 0 ]
    echo "$output" | grep -qi "Jira Epic"
}
