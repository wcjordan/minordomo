#!/usr/bin/env bats
# Tests for shared/notify-pr-discord.js

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export REPO_ROOT
    SCRIPT="$REPO_ROOT/shared/notify-pr-discord.js"
    STUB_DIR="$REPO_ROOT/test/fixtures/discord-stub"
    export SCRIPT STUB_DIR
}

@test "sends Discord message for pr_url in steps" {
    TMPLOG="$(mktemp)"
    TMPOUT="$(mktemp)"
    cat > "$TMPLOG" <<'BATSEOF'
```json
{
  "status": "success",
  "steps": [
    {"step": "open_pr", "status": "ok", "pr_url": "https://github.com/example/repo/pull/1"}
  ],
  "errors": []
}
```
BATSEOF
    run env DISCORD_WEBHOOK_URL="https://discord.test/webhook" \
        NODE_PATH="$STUB_DIR" \
        DISCORD_STUB_OUT="$TMPOUT" \
        node "$SCRIPT" "$TMPLOG"
    rm -f "$TMPLOG"
    [ "$status" -eq 0 ]
    grep -qF "New PR opened: https://github.com/example/repo/pull/1" "$TMPOUT"
    rm -f "$TMPOUT"
}

@test "sends Discord messages for pr_urls array in steps" {
    TMPLOG="$(mktemp)"
    TMPOUT="$(mktemp)"
    cat > "$TMPLOG" <<'BATSEOF'
```json
{
  "status": "success",
  "steps": [
    {"step": "check_story_completion", "status": "ok", "pr_urls": ["https://github.com/example/repo/pull/2", "https://github.com/example/repo/pull/3"]}
  ],
  "errors": []
}
```
BATSEOF
    run env DISCORD_WEBHOOK_URL="https://discord.test/webhook" \
        NODE_PATH="$STUB_DIR" \
        DISCORD_STUB_OUT="$TMPOUT" \
        node "$SCRIPT" "$TMPLOG"
    rm -f "$TMPLOG"
    [ "$status" -eq 0 ]
    grep -qF "New PR opened: https://github.com/example/repo/pull/2" "$TMPOUT"
    grep -qF "New PR opened: https://github.com/example/repo/pull/3" "$TMPOUT"
    rm -f "$TMPOUT"
}

@test "exits 0 with no messages when no PR URLs in run log" {
    TMPLOG="$(mktemp)"
    TMPOUT="$(mktemp)"
    cat > "$TMPLOG" <<'BATSEOF'
```json
{
  "status": "success",
  "steps": [
    {"step": "load_config", "status": "ok"}
  ],
  "errors": []
}
```
BATSEOF
    run env DISCORD_WEBHOOK_URL="https://discord.test/webhook" \
        NODE_PATH="$STUB_DIR" \
        DISCORD_STUB_OUT="$TMPOUT" \
        node "$SCRIPT" "$TMPLOG"
    rm -f "$TMPLOG"
    [ "$status" -eq 0 ]
    [ ! -s "$TMPOUT" ]
    rm -f "$TMPOUT"
}

@test "exits 0 with warning when DISCORD_WEBHOOK_URL is unset" {
    TMPLOG="$(mktemp)"
    echo '{"status":"success","steps":[],"errors":[]}' > "$TMPLOG"
    run env -u DISCORD_WEBHOOK_URL NODE_PATH="$STUB_DIR" node "$SCRIPT" "$TMPLOG"
    rm -f "$TMPLOG"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "WARNING"
}

@test "exits 0 with warning when run-log file is missing" {
    run env DISCORD_WEBHOOK_URL="https://discord.test/webhook" \
        NODE_PATH="$STUB_DIR" \
        node "$SCRIPT" "/nonexistent/path/to/prompt-output.txt"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "WARNING"
}

@test "exits 0 with warning when discord.js is unavailable" {
    TMPLOG="$(mktemp)"
    TMPDIR_EMPTY="$(mktemp -d)"
    cat > "$TMPLOG" <<'BATSEOF'
```json
{
  "status": "success",
  "steps": [
    {"step": "open_pr", "status": "ok", "pr_url": "https://github.com/example/repo/pull/4"}
  ],
  "errors": []
}
```
BATSEOF
    run env DISCORD_WEBHOOK_URL="https://discord.test/webhook" \
        NODE_PATH="$TMPDIR_EMPTY" \
        node "$SCRIPT" "$TMPLOG"
    rm -f "$TMPLOG"
    rmdir "$TMPDIR_EMPTY"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "WARNING"
}
