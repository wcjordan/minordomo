#!/usr/bin/env bats
# Tests for shared/setup-workspace.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-workspace.bats

REPO_ROOT=""
REMOTE=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"

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
    export REMOTE

    cat > "$mocks/gh" << 'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  "auth setup-git") exit 0 ;;
  "repo clone")
    # gh repo clone wcjordan/REPO REPO  → args: $3=wcjordan/REPO $4=REPO
    git clone "$REMOTE" "$4" -q
    ;;
  "issue view")
    # gh issue view <num> --repo ... --comments --json comments
    echo '{"comments":[{"body":"Jira Epic: MDOMO-1"}]}'
    ;;
  *) echo "mock gh: unhandled: $*" >&2; exit 1 ;;
esac
MOCK
    chmod +x "$mocks/gh"

    # bd mock: returns beads JSON based on the task ID argument.
    # IS_FIRST_TASK_VAL controls whether Stage-level tasks have blocks deps.
    # Default: minordomo-abc.2 has a blocks dep (non-first); minordomo-abc.1 has none (first).
    cat > "$mocks/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  "dolt") exit 0 ;;
  "stats") exit 0 ;;
  "show")
    TASK_ID="$2"
    case "$TASK_ID" in
      "minordomo-abc.2")
        echo '[{"id":"minordomo-abc.2","title":"Stage 2: Test Stage","parent":"minordomo-abc","dependencies":[{"issue_id":"minordomo-abc.2","depends_on_id":"minordomo-abc.1","type":"blocks"}]}]'
        ;;
      "minordomo-abc.1")
        echo '[{"id":"minordomo-abc.1","title":"Stage 1: Test Stage","parent":"minordomo-abc","dependencies":[{"issue_id":"minordomo-abc.1","depends_on_id":"minordomo-abc","type":"parent-child"}]}]'
        ;;
      "minordomo-abc")
        echo '[{"id":"minordomo-abc","title":"Plan: Test Task","description":"GH Issue: https://github.com/wcjordan/minordomo/issues/54"}]'
        ;;
      *) echo "[]" ;;
    esac
    ;;
  *) exit 0 ;;
esac
MOCK
    chmod +x "$mocks/bd"

    export PATH="$mocks:$PATH"

    # Required env vars
    export BEADS_TASK_ID="minordomo-abc.2"
    export GH_TOKEN="fake-gh-token"
    export BASE_BRANCH="bootstrap"
    export BEADS_DOLT_SERVER_USER="minordomo"
    unset REPO EPIC_KEY FEATURE_BRANCH
}

@test "planning mode: exports REPO, EPIC_KEY, FEATURE_BRANCH correctly" {
    export BEADS_TASK_ID="minordomo-abc"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$REPO" = "minordomo" ]
    [ "$EPIC_KEY" = "MDOMO-1" ]
    [ "$FEATURE_BRANCH" = "feature/MDOMO-1" ]
}

@test "planning mode: creates feature branch on remote when absent" {
    export BEADS_TASK_ID="minordomo-abc"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    git ls-remote --exit-code "$REMOTE" "feature/MDOMO-1"
}

@test "planning mode: creates and checks out task branch" {
    export BEADS_TASK_ID="minordomo-abc"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/minordomo-abc" ]
}

@test "planning mode: resumes existing task branch instead of creating a new one" {
    # Pre-create the task branch on the remote so ls-remote finds it
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q
    git -C "$work" checkout -b "task/minordomo-abc" -q
    git -C "$work" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "prior work" -q
    git -C "$work" push origin task/minordomo-abc -q

    cd "$BATS_TEST_TMPDIR"
    export BEADS_TASK_ID="minordomo-abc"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/minordomo-abc" ]
}

@test "worker mode: checks out feature branch and creates fresh task branch" {
    # Pre-create feature branch on remote (worker assumes it exists)
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q

    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker
    [ "$(git branch --show-current)" = "task/minordomo-abc.2" ]
}

@test "worker mode: first task triggers merge of base branch into feature branch" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q

    # Advance the base branch with a new commit after feature branch was created
    git -C "$work" checkout bootstrap -q
    git -C "$work" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "base branch advance" -q
    git -C "$work" push origin bootstrap -q

    # Use Stage 1 task (no blocks deps — identified as first task)
    export BEADS_TASK_ID="minordomo-abc.1"
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker

    # Verify the feature branch on the remote now matches the bootstrap tip (merge was pushed)
    local bootstrap_sha after_sha
    bootstrap_sha=$(git ls-remote "$REMOTE" refs/heads/bootstrap | awk '{print $1}')
    after_sha=$(git ls-remote "$REMOTE" refs/heads/feature/MDOMO-1 | awk '{print $1}')
    [ "$after_sha" = "$bootstrap_sha" ]
}

@test "worker mode: non-first task skips base branch merge" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q
    local before_sha
    before_sha=$(git ls-remote "$REMOTE" refs/heads/feature/MDOMO-1 | awk '{print $1}')

    # BEADS_TASK_ID defaults to minordomo-abc.2 (has blocks deps — non-first task)
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker

    local after_sha
    after_sha=$(git ls-remote "$REMOTE" refs/heads/feature/MDOMO-1 | awk '{print $1}')
    [ "$before_sha" = "$after_sha" ]
}

@test "worker mode: merge that is already up to date succeeds without error" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/MDOMO-1" -q
    git -C "$work" push origin feature/MDOMO-1 -q
    # feature/MDOMO-1 and bootstrap are at the same commit — already up to date

    export BEADS_TASK_ID="minordomo-abc.1"
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker
    # Test passes if the script exits cleanly (exit 0 with "Already up to date.")
}
