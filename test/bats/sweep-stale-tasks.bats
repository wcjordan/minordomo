#!/usr/bin/env bats
# Tests for shared/sweep-stale-tasks.sh

REPO_ROOT=""
MOCKS=""
SCRIPT=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/shared/sweep-stale-tasks.sh"
    export REPO_ROOT SCRIPT

    MOCKS="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCKS"
    export PATH="$MOCKS:$PATH"

    # Default bd mock: handles all subcommands used by sweep + sub-scripts
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[{"id":"minordomo-test-1","started_at":"2020-01-01T00:00:00Z","title":"Stage 1: Test","status":"in_progress"}]'
        ;;
    show)
        case "$2" in
            minordomo-test-1)
                echo '[{"id":"minordomo-test-1","title":"Stage 1: Test","parent":"minordomo-story-1","status":"in_progress","description":null}]'
                ;;
            minordomo-story-1)
                echo '[{"id":"minordomo-story-1","title":"Story: Test feature","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/99","parent":null,"status":"open"}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
        ;;
    dolt)
        exit 0
        ;;
    update)
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    # Default gh mock: all operations succeed
    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1-$2" in
    pr-list)
        echo '[]'
        ;;
    issue-view)
        echo '{"comments":[{"body":"Jira Epic: MDOMO-10"}]}'
        ;;
    issue-comment)
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/gh"
}

# ---------------------------------------------------------------------------
# Happy path: one stale task is reset and commented
# ---------------------------------------------------------------------------

@test "happy path: one stale task is reset and commented" {
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 1 stale task(s) to open (0 comment errors)."
}

# ---------------------------------------------------------------------------
# Multiple stale tasks: all are swept
# ---------------------------------------------------------------------------

@test "multiple stale tasks: all are swept" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[{"id":"minordomo-test-1","started_at":"2020-01-01T00:00:00Z","title":"Stage 1: Test","status":"in_progress"},{"id":"minordomo-test-2","started_at":"2020-01-01T00:00:00Z","title":"Stage 2: Test","status":"in_progress"}]'
        ;;
    show)
        case "$2" in
            minordomo-test-1|minordomo-test-2)
                echo "[{\"id\":\"$2\",\"title\":\"Stage 1: Test\",\"parent\":\"minordomo-story-1\",\"status\":\"in_progress\",\"description\":null}]"
                ;;
            minordomo-story-1)
                echo '[{"id":"minordomo-story-1","title":"Story: Test feature","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/99","parent":null,"status":"open"}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
        ;;
    dolt)
        exit 0
        ;;
    update)
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 2 stale task(s) to open (0 comment errors)."
}

# ---------------------------------------------------------------------------
# Non-stale task: started less than 12 hours ago — not reset
# ---------------------------------------------------------------------------

@test "non-stale task: started 1 hour ago is not reset" {
    recent=$(python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc) - timedelta(hours=1)).strftime('%Y-%m-%dT%H:%M:%SZ'))")
    cat > "$MOCKS/bd" << MOCK
#!/usr/bin/env bash
case "\$1" in
    list)
        echo "[{\"id\":\"minordomo-test-1\",\"started_at\":\"${recent}\",\"title\":\"Stage 1: Test\",\"status\":\"in_progress\"}]"
        ;;
    dolt)
        exit 0
        ;;
    update)
        touch "$MOCKS/update-was-called"
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 0 stale task(s) to open (0 comment errors)."
    [ ! -f "$MOCKS/update-was-called" ]
}

# ---------------------------------------------------------------------------
# get-epic-key.sh failure: task is still reset
# ---------------------------------------------------------------------------

@test "get-epic-key failure: task is still reset, comment error counted" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[{"id":"minordomo-test-1","started_at":"2020-01-01T00:00:00Z","title":"Stage 1: Test","status":"in_progress"}]'
        ;;
    show)
        # Return task with no parent — causes get-story-key.sh to fail
        echo '[{"id":"minordomo-test-1","title":"Stage 1: Test","parent":null,"status":"in_progress","description":null}]'
        ;;
    dolt)
        exit 0
        ;;
    update)
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 1 stale task(s) to open (1 comment errors)."
}

# ---------------------------------------------------------------------------
# gh issue comment failure: task is still reset
# ---------------------------------------------------------------------------

@test "gh issue comment failure: task is still reset, comment error counted" {
    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1-$2" in
    pr-list)
        echo '[]'
        ;;
    issue-view)
        echo '{"comments":[{"body":"Jira Epic: MDOMO-10"}]}'
        ;;
    issue-comment)
        exit 1
        ;;
esac
MOCK
    chmod +x "$MOCKS/gh"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 1 stale task(s) to open (1 comment errors)."
}

# ---------------------------------------------------------------------------
# Task has an open PR: task is skipped (not reset)
# ---------------------------------------------------------------------------

@test "task with open PR: skipped entirely" {
    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1-$2" in
    pr-list)
        echo '[{"number":42}]'
        ;;
    issue-comment)
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[{"id":"minordomo-test-1","started_at":"2020-01-01T00:00:00Z","title":"Stage 1: Test","status":"in_progress"}]'
        ;;
    show)
        case "$2" in
            minordomo-test-1)
                echo '[{"id":"minordomo-test-1","title":"Stage 1: Test","parent":"minordomo-story-1","status":"in_progress","description":null}]'
                ;;
            minordomo-story-1)
                echo '[{"id":"minordomo-story-1","title":"Story: Test feature","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/99","parent":null,"status":"open"}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
        ;;
    dolt)
        exit 0
        ;;
    update)
        touch "$MOCKS/update-was-called"
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 0 stale task(s) to open (0 comment errors)."
    [ ! -f "$MOCKS/update-was-called" ]
}

# ---------------------------------------------------------------------------
# Task has a merged PR: task is skipped (not reset)
# ---------------------------------------------------------------------------

@test "task with merged PR: skipped (not reset)" {
    cat > "$MOCKS/gh" << 'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"--state merged"* ]]; then
    echo '[{"number":42}]'
elif [[ "$*" == *"--state open"* ]]; then
    echo '[]'
fi
MOCK
    chmod +x "$MOCKS/gh"

    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[{"id":"minordomo-test-1","started_at":"2020-01-01T00:00:00Z","title":"Stage 1: Test","status":"in_progress"}]'
        ;;
    show)
        case "$2" in
            minordomo-test-1)
                echo '[{"id":"minordomo-test-1","title":"Stage 1: Test","parent":"minordomo-story-1","status":"in_progress","description":null}]'
                ;;
            minordomo-story-1)
                echo '[{"id":"minordomo-story-1","title":"Story: Test feature","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/99","parent":null,"status":"open"}]'
                ;;
            *)
                echo '[]'
                ;;
        esac
        ;;
    dolt)
        exit 0
        ;;
    update)
        touch "$MOCKS/update-was-called"
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 0 stale task(s) to open (0 comment errors)."
    [ ! -f "$MOCKS/update-was-called" ]
}

# ---------------------------------------------------------------------------
# bd list returns empty: exits 0 with Swept 0 message
# ---------------------------------------------------------------------------

@test "bd list returns empty: exits 0 with Swept 0 message" {
    cat > "$MOCKS/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
    list)
        echo '[]'
        ;;
esac
MOCK
    chmod +x "$MOCKS/bd"

    run "$SCRIPT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Swept 0 stale task(s) to open (0 comment errors)."
}
