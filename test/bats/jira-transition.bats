#!/usr/bin/env bats
# Tests for shared/jira-transition.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"

    export JIRA_URL="https://jira.example.com"
    export JIRA_EMAIL="test@example.com"
    export JIRA_API_TOKEN="fake-token"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "jira-transition: happy path transitions successfully" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-X POST"* ]]; then
    exit 0
else
    echo '{"transitions": [{"id": "31", "to": {"name": "In Review"}}, {"id": "11", "to": {"name": "Done"}}]}'
    exit 0
fi
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Status name not found
# ---------------------------------------------------------------------------

@test "jira-transition: exits non-zero when target status not in transitions list" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-X POST"* ]]; then
    exit 0
else
    echo '{"transitions": [{"id": "11", "to": {"name": "Done"}}]}'
    exit 0
fi
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -ne 0 ]
    [[ "$output" == *"In Review"* ]]
}

# ---------------------------------------------------------------------------
# GET curl fails
# ---------------------------------------------------------------------------

@test "jira-transition: exits non-zero when GET curl returns non-zero" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-X POST"* ]]; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Missing environment variables
# ---------------------------------------------------------------------------

@test "jira-transition: exits non-zero when JIRA_URL is not set" {
    unset JIRA_URL
    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -ne 0 ]
}

@test "jira-transition: exits non-zero when JIRA_EMAIL is not set" {
    unset JIRA_EMAIL
    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -ne 0 ]
}

@test "jira-transition: exits non-zero when JIRA_API_TOKEN is not set" {
    unset JIRA_API_TOKEN
    run "$REPO_ROOT/shared/jira-transition.sh" "MDOMO-45" "In Review"
    [ "$status" -ne 0 ]
}
