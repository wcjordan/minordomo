#!/usr/bin/env bats
# Tests for the spec-update git workflow path

setup() {
    REPO_DIR="$BATS_TEST_TMPDIR/testrepo"
    mkdir -p "$REPO_DIR/docs/planning"

    # Initialize a bare git repo with a spec doc
    cd "$REPO_DIR"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"

    cat > "docs/planning/feature-abc-spec.md" << 'EOF'
# Spec: Feature ABC

## Stage 1: Do something

### Description
Initial description.

### Acceptance Criteria
- Works
EOF

    git add -A
    git commit -q -m "Initial commit with spec doc"
}

teardown() {
    rm -rf "$REPO_DIR"
}

@test "spec doc changes are captured in commit when worker modifies spec" {
    cd "$REPO_DIR"

    # Simulate worker updating the spec doc
    cat > "docs/planning/feature-abc-spec.md" << 'EOF'
# Spec: Feature ABC

## Stage 1: Do something

### Description
Updated description after implementation revealed a better approach.

### Acceptance Criteria
- Works correctly
- Uses updated approach
EOF

    git add -A
    git commit -q -m "Stage 1: implement feature, update spec"

    # Spec doc must appear in the commit's changed files
    run git show --name-only --format="" HEAD
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "docs/planning/feature-abc-spec.md"
}

@test "commit history shows spec doc was modified" {
    cd "$REPO_DIR"

    # Simulate worker updating the spec doc alongside code changes
    mkdir -p src
    echo "implementation" > src/feature.sh
    sed -i 's/Initial description/Updated description/' "docs/planning/feature-abc-spec.md"

    git add -A
    git commit -q -m "Stage 1: implement feature with spec update"

    # Both files must appear in the commit diff-stat
    run git diff --name-only HEAD~1 HEAD
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "docs/planning/feature-abc-spec.md"
    echo "$output" | grep -q "src/feature.sh"
}
