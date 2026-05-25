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
}

@test "copies agent-settings.json to ~/.claude/settings.json" {
    source shared/setup-claude.sh
    diff shared/agent-settings.json "$HOME/.claude/settings.json"
}

@test "copies pre-bash-guard.sh to ~/.claude/hooks/pre-bash-guard.sh" {
    source shared/setup-claude.sh
    diff shared/pre-bash-guard.sh "$HOME/.claude/hooks/pre-bash-guard.sh"
}
