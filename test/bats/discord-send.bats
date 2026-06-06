#!/usr/bin/env bats
# Tests for shared/discord-send.js

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/discord-send.js"
    STUB_DIR="$REPO_ROOT/test/fixtures/discord-stub"
    export SCRIPT STUB_DIR
}

@test "sends message to webhook when DISCORD_WEBHOOK_URL is set and argument is provided" {
    TMPOUT="$(mktemp)"
    run env DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/test-token" \
        NODE_PATH="$STUB_DIR" \
        DISCORD_STUB_OUT="$TMPOUT" \
        node "$SCRIPT" "Hello from discord-send"
    [ "$status" -eq 0 ]
    grep -qF "Hello from discord-send" "$TMPOUT"
    rm -f "$TMPOUT"
}

@test "exits 0 and emits warning when DISCORD_WEBHOOK_URL is unset" {
    run env -u DISCORD_WEBHOOK_URL NODE_PATH="$STUB_DIR" node "$SCRIPT" "test message"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "not set"
}

@test "exits 0 and emits warning when DISCORD_WEBHOOK_URL is empty" {
    run env DISCORD_WEBHOOK_URL="" NODE_PATH="$STUB_DIR" node "$SCRIPT" "test message"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "empty"
}

@test "exits 0 and emits warning when DISCORD_WEBHOOK_URL does not start with a valid Discord prefix" {
    run env DISCORD_WEBHOOK_URL="https://example.com/not-a-discord-url" \
        NODE_PATH="$STUB_DIR" node "$SCRIPT" "test message"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "does not look like a Discord webhook URL"
}

@test "exits 0 and emits warning when discord.js is unavailable" {
    TMPDIR_EMPTY="$(mktemp -d)"
    run env DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/123/test-token" \
        NODE_PATH="$TMPDIR_EMPTY" \
        node "$SCRIPT" "test message"
    rmdir "$TMPDIR_EMPTY"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "WARNING"
}
