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

    # Required by setup-claude.sh
    export JIRA_URL="https://api.atlassian.com/ex/jira/testcloud"
    export JIRA_EMAIL="test@example.com"
    export JIRA_API_TOKEN="jira-fake-token"
}

@test "copies agent-settings.json to ~/.claude/settings.json" {
    source shared/setup-claude.sh
    diff shared/agent-settings.json "$HOME/.claude/settings.json"
}

@test "copies pre-bash-guard.sh to ~/.claude/hooks/pre-bash-guard.sh" {
    source shared/setup-claude.sh
    diff shared/pre-bash-guard.sh "$HOME/.claude/hooks/pre-bash-guard.sh"
}

@test "calls claude mcp add atlassian with JIRA env vars" {
    source shared/setup-claude.sh
    grep -q "mcp add atlassian" "$CLAUDE_CALLS_LOG"
    grep -q "JIRA_URL=https://api.atlassian.com/ex/jira/testcloud" "$CLAUDE_CALLS_LOG"
    grep -q "JIRA_EMAIL=test@example.com" "$CLAUDE_CALLS_LOG"
    grep -q "JIRA_API_TOKEN=jira-fake-token" "$CLAUDE_CALLS_LOG"
}

@test "calls claude mcp list after registering the server" {
    source shared/setup-claude.sh
    grep -q "mcp list" "$CLAUDE_CALLS_LOG"
}

@test "writes beads server config to ~/.config/beads/server.json" {
    source shared/setup-claude.sh
    [ -f "$HOME/.config/beads/server.json" ]
    grep -q "dolt-server.minordomo.svc.cluster.local" "$HOME/.config/beads/server.json"
    grep -q "3306" "$HOME/.config/beads/server.json"
    grep -q "server" "$HOME/.config/beads/server.json"
}
