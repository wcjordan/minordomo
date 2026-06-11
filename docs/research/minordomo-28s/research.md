# Research: Unexpected Discord notification (minordomo-28s)

GH Issue #373: "Unexpected 'Human input requested: https://github.com/wcjordan/myrepo/issues/42' line published to discord"

---

## Root Cause

The URL in the issue title — `https://github.com/wcjordan/myrepo/issues/42` — is not a production URL. It matches the literal test fixture values used in `test/bats/apply-needs-input.bats`:

```bash
run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
```

This maps to `https://github.com/wcjordan/${repo}/issues/${issue_number}` = `myrepo/issues/42`.

### Why it fires

`shared/apply-needs-input.sh` sends a Discord notification as its final step:

```bash
discord_send_script="${DISCORD_SEND_SCRIPT:-${SCRIPT_DIR}/discord-send.js}"
node "${discord_send_script}" "Human input requested: https://github.com/wcjordan/${repo}/issues/${issue_number}" || true
```

The `happy path` test in `apply-needs-input.bats` does not set `DISCORD_SEND_SCRIPT`:

```bash
@test "happy path: all three steps succeed" {
    run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
    [ "$status" -eq 0 ]
}
```

`setup()` exports `DISCORD_SEND_STUB` as a variable name but never assigns it to `DISCORD_SEND_SCRIPT`. The other tests that want to use the stub explicitly pass:
```bash
run env DISCORD_WEBHOOK_URL="..." DISCORD_SEND_SCRIPT="$DISCORD_SEND_STUB" ...
```

But the `happy path` test calls `"$SCRIPT"` directly, inheriting the full shell environment. If `DISCORD_WEBHOOK_URL` is set in the developer's environment (e.g. exported in their shell profile or a local `.env`), `discord-send.js` will successfully send a real Discord notification with the test placeholder values.

### Evidence chain

1. The Discord message text (`Human input requested: https://github.com/wcjordan/myrepo/issues/42`) can ONLY come from `apply-needs-input.sh`.
2. Production runs use real repo names and issue numbers derived from `setup-workspace.sh`; they never produce `myrepo/42`.
3. The bats test for `apply-needs-input.sh` uses exactly `myrepo 42` as positional args.
4. The `happy path` test does not override `DISCORD_SEND_SCRIPT`, so the real `discord-send.js` fires when `DISCORD_WEBHOOK_URL` is in the environment.
5. GitHub Actions CI does not set `DISCORD_WEBHOOK_URL`, so this does not trigger in CI — only when a developer runs `make test` locally with the webhook URL exported.

### Why the `happy path` test also has weak coverage

The `happy path` test only asserts `[ "$status" -eq 0 ]`. It does not verify that the Discord notification was sent. Adding an assertion against the stub output would have caught this gap at test-authoring time.

---

## Other bats files: clean

- `discord-send.bats`: uses `NODE_PATH="$STUB_DIR"` to load a stub discord.js library in every test — no real HTTP calls possible.
- `claude-stop-hook.bats`: uses `setup_fake_cwd` to create a stub `apply-needs-input.sh` — the real script never runs.

---

## Fix

In `test/bats/apply-needs-input.bats`:

1. Add `export DISCORD_SEND_SCRIPT="$DISCORD_SEND_STUB"` to `setup()` so all tests default to the stub. Tests that already pass `DISCORD_SEND_SCRIPT` explicitly via `env` are unaffected (env overrides the inherited value). Tests that want the stub but currently don't set it (i.e. `happy path`) will now use it automatically.

2. Update the `happy path` test to verify the stub was called with the correct message — this adds real coverage of the Discord notification path and would detect a future regression.

3. To be belt-and-suspenders, also add `unset DISCORD_WEBHOOK_URL` in `setup()` (or `export DISCORD_WEBHOOK_URL=""`) so tests that accidentally skip the stub override cannot fire the real notifier.
