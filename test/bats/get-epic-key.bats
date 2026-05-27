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
# Happy path: parent is Story bead with GH URL in its description
# ---------------------------------------------------------------------------

@test "happy path: parent is Story bead" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
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
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": [{"body": "Jira Epic: MDOMO-10"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1.1" "myrepo"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = "test-1" ]
    [ "$(echo "$output" | sed -n '2p')" = "42" ]
    [ "$(echo "$output" | sed -n '3p')" = "MDOMO-10" ]
}

# ---------------------------------------------------------------------------
# Happy path: URL is in the Story parent's description (no URL on child)
# ---------------------------------------------------------------------------

@test "happy path: URL in parent description only" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$2" in
    "test-1.1")
        echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
        ;;
    "test-1")
        echo '[{"id": "test-1", "title": "Story: Feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/99", "status": "open", "parent": null}]'
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
    [ "$(echo "$output" | sed -n '1p')" = "test-1" ]
    [ "$(echo "$output" | sed -n '2p')" = "99" ]
    [ "$(echo "$output" | sed -n '3p')" = "MDOMO-20" ]
}

# ---------------------------------------------------------------------------
# Happy path: task itself is the Story bead (no parent lookup needed)
# ---------------------------------------------------------------------------

@test "happy path: task itself is Story bead" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/55", "status": "open", "parent": null}]'
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": [{"body": "Jira Epic: MDOMO-30"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1" "myrepo"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = "test-1" ]
    [ "$(echo "$output" | sed -n '2p')" = "55" ]
    [ "$(echo "$output" | sed -n '3p')" = "MDOMO-30" ]
}

# ---------------------------------------------------------------------------
# Happy path: Story bead has a parent but parent must not be consulted
# ---------------------------------------------------------------------------

@test "happy path: Story bead with parent — parent not consulted" {
    call_count_file="$BATS_TEST_TMPDIR/bd_calls"
    echo 0 > "$call_count_file"

    cat > "$MOCKS/bd" << MOCK
#!/usr/bin/env bash
count=\$(cat "$call_count_file")
echo \$((count + 1)) > "$call_count_file"
case "\$2" in
    "test-1")
        echo '[{"id": "test-1", "title": "Story: My feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/77", "status": "open", "parent": "test-0"}]'
        ;;
    *)
        echo "[]"
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
echo '{"comments": [{"body": "Jira Epic: MDOMO-40"}]}'
MOCK
    chmod +x "$MOCKS/gh"

    run "$REPO_ROOT/shared/get-epic-key.sh" "test-1" "myrepo"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | sed -n '1p')" = "test-1" ]
    [ "$(echo "$output" | sed -n '2p')" = "77" ]
    [ "$(echo "$output" | sed -n '3p')" = "MDOMO-40" ]
    # bd should only be called once (for the task itself, not its parent)
    [ "$(cat "$call_count_file")" = "1" ]
}

# ---------------------------------------------------------------------------
# Failure: neither task nor parent has a Story: title
# ---------------------------------------------------------------------------

@test "failure: no Story bead found" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$2" in
    "test-1.1")
        echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
        ;;
    "test-1")
        echo '[{"id": "test-1", "title": "Plan: Feature", "description": "GH Issue: https://github.com/wcjordan/myrepo/issues/42", "status": "open", "parent": null}]'
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
    echo "$output" | grep -qi "Story"
}

# ---------------------------------------------------------------------------
# Failure: Story bead found but no GH Issue URL in its description
# ---------------------------------------------------------------------------

@test "failure: no GH Issue URL found" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$2" in
    "test-1.1")
        echo '[{"id": "test-1.1", "title": "Stage 1: Do something", "description": null, "status": "in_progress", "parent": "test-1"}]'
        ;;
    "test-1")
        echo '[{"id": "test-1", "title": "Story: Feature", "description": "No URL here", "status": "open", "parent": null}]'
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
