#!/usr/bin/env bats
# Tests for shared/setup-workspace.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-workspace.bats

REPO_ROOT=""
REMOTE=""
FIXTURE_JSON=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FIXTURE_JSON="$REPO_ROOT/test/fixtures/jira-task-response.json"

    # Create a local bare git repo to act as the GitHub remote.
    # Setting HEAD → bootstrap before the first clone ensures all subsequent
    # clones check out the bootstrap branch instead of landing in a detached/unborn state.
    REMOTE="$BATS_TEST_TMPDIR/remote.git"
    git init --bare "$REMOTE" -q
    git -C "$REMOTE" symbolic-ref HEAD refs/heads/bootstrap
    local init="$BATS_TEST_TMPDIR/init"
    git clone "$REMOTE" "$init" -q
    git -C "$init" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "Initial commit" -q
    git -C "$init" push origin HEAD:bootstrap -q

    # Work dir: a temp directory with shared/config.yaml so scripts find the config
    cd "$BATS_TEST_TMPDIR"
    mkdir -p shared
    cp "$REPO_ROOT/shared/config.yaml" shared/config.yaml

    # Mock binaries in a temp dir prepended to PATH
    local mocks="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$mocks"
    export REMOTE FIXTURE_JSON

    cat > "$mocks/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "auth setup-git") exit 0 ;;
  "repo clone")
    # gh repo clone wcjordan/REPO REPO  → args: $3=wcjordan/REPO $4=REPO
    git clone "$REMOTE" "$4" -q
    ;;
  *) echo "mock gh: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
    chmod +x "$mocks/gh"

    cat > "$mocks/curl" << 'MOCK'
#!/usr/bin/env bash
cat "$FIXTURE_JSON"
MOCK
    chmod +x "$mocks/curl"

    export PATH="$mocks:$PATH"

    # Required env vars
    export JIRA_TASK_ID="MDOMO-44"
    export JIRA_URL="https://api.atlassian.com/ex/jira/test"
    export JIRA_EMAIL="test@example.com"
    export JIRA_API_TOKEN="fake-token"
    export GH_TOKEN="fake-gh-token"
    export BASE_BRANCH="bootstrap"
    unset REPO EPIC_KEY FEATURE_BRANCH
}

@test "planning mode: exports REPO, EPIC_KEY, FEATURE_BRANCH correctly" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$REPO" = "minordomo" ]
    [ "$EPIC_KEY" = "MDOMO-1" ]
    [ "$FEATURE_BRANCH" = "feature/MDOMO-1" ]
}

@test "planning mode: creates feature branch on remote when absent" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    git ls-remote --exit-code "$REMOTE" "feature/MDOMO-1"
}

@test "planning mode: creates and checks out task branch" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/MDOMO-44" ]
}

@test "planning mode: resumes existing task branch instead of creating a new one" {
    # Pre-create the task branch on the remote so ls-remote finds it
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q
    git -C "$work" checkout -b "task/MDOMO-44" -q
    git -C "$work" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "prior work" -q
    git -C "$work" push origin task/MDOMO-44 -q

    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/MDOMO-44" ]
}

@test "worker mode: checks out feature branch and creates fresh task branch" {
    # Pre-create feature branch on remote (worker assumes it exists)
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q

    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker
    [ "$(git branch --show-current)" = "task/MDOMO-44" ]
}
