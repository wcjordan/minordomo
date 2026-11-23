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

@test "copies .claude.json.example to ~/.claude.json" {
    source shared/setup-claude.sh
    diff shared/.claude.json.example "$HOME/.claude.json"
}

# The interactive worker runs claude in each repo's workspace. Without a
# pre-accepted trust entry, claude blocks on the "trust this folder?" dialog
# (hidden, since PTY output goes to /dev/null) and never writes a transcript.
@test "every repo in config.yaml is pre-trusted for the worker workspace" {
    source shared/setup-claude.sh
    run python3 - "$HOME/.claude.json" << 'PY'
import json, sys, yaml
cfg = yaml.safe_load(open('shared/config.yaml'))
projects = json.load(open(sys.argv[1])).get('projects', {})
missing = []
for p in cfg.get('projects', []):
    path = f"/home/jenkins/agent/workspace/minordomo-step_main/{p['repo']}"
    entry = projects.get(path, {})
    if not (entry.get('hasTrustDialogAccepted') and entry.get('hasCompletedProjectOnboarding')):
        missing.append(path)
if missing:
    print("Repos missing a trust entry in shared/.claude.json.example:")
    print("\n".join(missing))
    sys.exit(1)
PY
    echo "$output"
    [ "$status" -eq 0 ]
}
