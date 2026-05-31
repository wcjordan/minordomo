#!/usr/bin/env bats
# Tests for shared/setup-claude.sh
# Prereq: bats-core (brew install bats-core)
# Run from repo root: bats test/bats/setup-claude.bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$REPO_ROOT"

    # Isolate HOME so writes go to a throwaway directory
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"

    # Mock claude binary: logs all args to a file and exits 0
    MOCK_DIR="$BATS_TEST_TMPDIR/mocks"
    mkdir -p "$MOCK_DIR"
    export CLAUDE_CALLS_LOG="$BATS_TEST_TMPDIR/claude-calls.log"
    cat > "$MOCK_DIR/claude" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$CLAUDE_CALLS_LOG"
exit 0
MOCK
    chmod +x "$MOCK_DIR/claude"
    export PATH="$MOCK_DIR:$PATH"

}

@test "copies agent-settings.json to ~/.claude/settings.json" {
    source shared/setup-claude.sh
    diff shared/agent-settings.json "$HOME/.claude/settings.json"
}

@test "copies pre-bash-guard.sh to ~/.claude/hooks/pre-bash-guard.sh" {
    source shared/setup-claude.sh
    diff shared/pre-bash-guard.sh "$HOME/.claude/hooks/pre-bash-guard.sh"
}

