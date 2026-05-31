#!/usr/bin/env bats
# Tests for shared/jenkins-trigger.sh

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    TMP_DIR="$(mktemp -d)"
    export TMP_DIR
    export PATH="$TMP_DIR:$PATH"

    export JENKINS_USERNAME="test-user"
    export JENKINS_API_KEY="test-key"
    export ROOT_DOMAIN="example.com"
    export BASE_BRANCH="main"
}

teardown() {
    rm -rf "$TMP_DIR"
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "jenkins-trigger: happy path exits 0 when curl returns 201" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
# Return 201 for the -w "%{http_code}" pattern
echo "201"
exit 0
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -eq 0 ]
}

@test "jenkins-trigger: passes Content-Length: 0 header to curl" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
# Record args and return 201
echo "$@" >> "$TMP_DIR/curl_args"
echo "201"
exit 0
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -eq 0 ]
    grep -q "Content-Length: 0" "$TMP_DIR/curl_args"
}

# ---------------------------------------------------------------------------
# Non-201 HTTP response
# ---------------------------------------------------------------------------

@test "jenkins-trigger: exits non-zero when curl returns 404" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
echo "404"
exit 0
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"404"* ]]
}

# ---------------------------------------------------------------------------
# curl itself fails
# ---------------------------------------------------------------------------

@test "jenkins-trigger: exits non-zero when curl itself fails" {
    cat > "$TMP_DIR/curl" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
    chmod +x "$TMP_DIR/curl"

    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Missing environment variables
# ---------------------------------------------------------------------------

@test "jenkins-trigger: exits non-zero when JENKINS_USERNAME is not set" {
    unset JENKINS_USERNAME
    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
}

@test "jenkins-trigger: exits non-zero when JENKINS_API_KEY is not set" {
    unset JENKINS_API_KEY
    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
}

@test "jenkins-trigger: exits non-zero when ROOT_DOMAIN is not set" {
    unset ROOT_DOMAIN
    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
}

@test "jenkins-trigger: exits non-zero when BASE_BRANCH is not set" {
    unset BASE_BRANCH
    run "$REPO_ROOT/shared/jenkins-trigger.sh" "minordomo-step" "minordomo-abc.1"
    [ "$status" -ne 0 ]
}
