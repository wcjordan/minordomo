#!/usr/bin/env bats
# Tests for shared/setup-workspace.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-workspace.bats

REPO_ROOT=""
REMOTE=""
BEADS_TASK_FIXTURE=""
BEADS_PARENT_FIXTURE=""
BEADS_SIBLINGS_FIXTURE=""

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    BEADS_TASK_FIXTURE="$REPO_ROOT/test/fixtures/beads-task-show.json"
    BEADS_PARENT_FIXTURE="$REPO_ROOT/test/fixtures/beads-parent-show.json"
    BEADS_SIBLINGS_FIXTURE="$REPO_ROOT/test/fixtures/beads-siblings-none-closed.json"

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
    export REMOTE BEADS_TASK_FIXTURE BEADS_PARENT_FIXTURE BEADS_SIBLINGS_FIXTURE

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

    cat > "$mocks/bd" << 'MOCK'
#!/usr/bin/env bash
case "$1" in
  show)
    # bd show <ID> --json
    # Called by get-story-key.sh (for EPIC_KEY derivation) and directly (for PARENT_ID lookup).
    case "$2" in
      *".1"|*".2"|*".3")
        # Stage bead (has .N suffix)
        cat "$BEADS_TASK_FIXTURE"
        ;;
      *)
        # Parent/Plan bead — get-epic-key.sh falls back here when task description has no GH URL
        cat "$BEADS_PARENT_FIXTURE"
        ;;
    esac
    ;;
  list)
    if [[ "$*" == *"--status=closed"* ]]; then
        cat "$BEADS_SIBLINGS_FIXTURE"
    else
        echo "[]"
    fi
    ;;
  bootstrap|dolt|stats) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
    chmod +x "$mocks/bd"

    export PATH="$mocks:$PATH"

    # Required env vars
    export BEADS_TASK_ID="minordomo-100.1"
    export GH_TOKEN="fake-gh-token"
    export BASE_BRANCH="bootstrap"
    export ROOT_DOMAIN="test.example.com"
    unset REPO EPIC_KEY FEATURE_BRANCH
}

@test "planning mode: exports REPO, EPIC_KEY, FEATURE_BRANCH correctly" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$REPO" = "minordomo" ]
    [ "$EPIC_KEY" = "minordomo-100" ]
    [ "$FEATURE_BRANCH" = "feature/minordomo-100" ]
}

@test "planning mode: creates feature branch on remote when absent" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    git ls-remote --exit-code "$REMOTE" "feature/minordomo-100"
}

@test "planning mode: creates and checks out task branch" {
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/minordomo-100.1" ]
}

@test "planning mode: resumes existing task branch instead of creating a new one" {
    # Pre-create the task branch on the remote so ls-remote finds it
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/minordomo-100" -q
    git -C "$work" push origin feature/minordomo-100 -q
    git -C "$work" checkout -b "task/minordomo-100.1" -q
    git -C "$work" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "prior work" -q
    git -C "$work" push origin task/minordomo-100.1 -q

    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" planning
    [ "$(git branch --show-current)" = "task/minordomo-100.1" ]
}

@test "worker mode: checks out feature branch and creates fresh task branch" {
    # Pre-create feature branch on remote (worker assumes it exists)
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/minordomo-100" -q
    git -C "$work" push origin feature/minordomo-100 -q

    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker
    [ "$(git branch --show-current)" = "task/minordomo-100.1" ]
}

@test "worker mode: first task triggers merge of base branch into feature branch" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/minordomo-100" -q
    git -C "$work" push origin feature/minordomo-100 -q

    # Advance the base branch with a new commit after feature branch was created
    git -C "$work" checkout bootstrap -q
    git -C "$work" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "base branch advance" -q
    git -C "$work" push origin bootstrap -q

    # No closed siblings → IS_FIRST_TASK=yes (default fixture has none closed)
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker

    # Verify the feature branch on the remote now matches the bootstrap tip (merge was pushed)
    local bootstrap_sha after_sha
    bootstrap_sha=$(git ls-remote "$REMOTE" refs/heads/bootstrap | awk '{print $1}')
    after_sha=$(git ls-remote "$REMOTE" refs/heads/feature/minordomo-100 | awk '{print $1}')
    [ "$after_sha" = "$bootstrap_sha" ]
}

@test "worker mode: non-first task skips base branch merge" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/minordomo-100" -q
    git -C "$work" push origin feature/minordomo-100 -q
    local before_sha
    before_sha=$(git ls-remote "$REMOTE" refs/heads/feature/minordomo-100 | awk '{print $1}')

    # Use the fixture that returns closed siblings → IS_FIRST_TASK=no
    BEADS_SIBLINGS_FIXTURE="$REPO_ROOT/test/fixtures/beads-siblings-has-closed.json"
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker

    local after_sha
    after_sha=$(git ls-remote "$REMOTE" refs/heads/feature/minordomo-100 | awk '{print $1}')
    [ "$before_sha" = "$after_sha" ]
}

@test "worker mode: merge that is already up to date succeeds without error" {
    local work="$BATS_TEST_TMPDIR/pre"
    git clone "$REMOTE" "$work" -q
    git -C "$work" checkout -b "feature/minordomo-100" -q
    git -C "$work" push origin feature/minordomo-100 -q
    # feature/minordomo-100 and bootstrap are at the same commit — already up to date

    # No closed siblings → IS_FIRST_TASK=yes, but merge is a no-op
    cd "$BATS_TEST_TMPDIR"
    source "$REPO_ROOT/shared/setup-workspace.sh" worker
    # Test passes if the script exits cleanly (exit 0 with "Already up to date.")
}
