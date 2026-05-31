#!/usr/bin/env bats
# Tests for spec-update git machinery: verifies that spec doc changes are captured in commits

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT

    WORK_DIR="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$WORK_DIR/docs/planning"

    git -C "$BATS_TEST_TMPDIR" init repo -q
    git -C "$WORK_DIR" -c user.email="t@t.com" -c user.name="T" \
        commit --allow-empty -m "Initial commit" -q

    # Create initial spec doc
    echo "# Spec: My Feature" > "$WORK_DIR/docs/planning/PROJ-1-spec.md"
    echo "## Stage 1: Do something" >> "$WORK_DIR/docs/planning/PROJ-1-spec.md"
    git -C "$WORK_DIR" add docs/planning/PROJ-1-spec.md
    git -C "$WORK_DIR" -c user.email="t@t.com" -c user.name="T" \
        commit -m "Add spec doc" -q

    export WORK_DIR
}

@test "spec doc modification is captured by git add -A and commit" {
    # Simulate a worker updating the spec doc
    echo "### Updated content" >> "$WORK_DIR/docs/planning/PROJ-1-spec.md"

    # Worker commits using git add -A
    git -C "$WORK_DIR" add -A
    git -C "$WORK_DIR" -c user.email="t@t.com" -c user.name="T" \
        commit -m "Stage 1: implement feature" -q

    # Verify the commit captured the spec doc change
    run git -C "$WORK_DIR" show --name-only HEAD
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "docs/planning/PROJ-1-spec.md"
}

@test "commit history shows spec doc was modified" {
    # Simulate a worker modifying the spec doc alongside implementation
    echo "### Updated guidance for later stages" >> "$WORK_DIR/docs/planning/PROJ-1-spec.md"
    echo "some_code()" > "$WORK_DIR/implementation.sh"

    git -C "$WORK_DIR" add -A
    git -C "$WORK_DIR" -c user.email="t@t.com" -c user.name="T" \
        commit -m "Stage 1: implement with spec update" -q

    # Verify git log --all-files shows the spec doc in commit history
    run git -C "$WORK_DIR" log --oneline --name-only HEAD
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "docs/planning/PROJ-1-spec.md"
}

@test "spec doc change is not committed when not staged" {
    # Simulate a worker making changes but NOT staging the spec doc
    echo "### Unstaged change" >> "$WORK_DIR/docs/planning/PROJ-1-spec.md"
    echo "some_code()" > "$WORK_DIR/implementation.sh"

    # Stage only the implementation file
    git -C "$WORK_DIR" add implementation.sh
    git -C "$WORK_DIR" -c user.email="t@t.com" -c user.name="T" \
        commit -m "Stage 1: implement without spec doc" -q

    # Verify the spec doc is NOT in the commit (still modified locally)
    run git -C "$WORK_DIR" show --name-only HEAD
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "docs/planning/PROJ-1-spec.md"

    # Confirm spec doc is still dirty
    run git -C "$WORK_DIR" status --porcelain
    echo "$output" | grep -q "docs/planning/PROJ-1-spec.md"
}
