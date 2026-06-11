# Spec: Fix spurious Discord notification from apply-needs-input.bats

**Epic:** minordomo-28s
**Issue:** https://github.com/wcjordan/minordomo/issues/373

## Overview

A real Discord notification `"Human input requested: https://github.com/wcjordan/myrepo/issues/42"` was sent to the team channel. The URL contains literal test fixture values (`myrepo`, `42`) from `test/bats/apply-needs-input.bats`.

Root cause: the `happy path` test calls the real `discord-send.js` instead of the stub because `setup()` never assigns `DISCORD_SEND_SCRIPT`. The test calls `"$SCRIPT"` directly (inheriting the developer's environment), so if `DISCORD_WEBHOOK_URL` is exported in the developer's shell, the test sends a real Discord notification. GitHub Actions CI does not set `DISCORD_WEBHOOK_URL`, so this is silent in CI and only fires locally.

Fix: set `DISCORD_SEND_SCRIPT` to the stub in `setup()` and add a real assertion to the `happy path` test so this coverage gap cannot recur.

See `docs/research/minordomo-28s/research.md` for full evidence chain.

---

## Stage 1: Fix test isolation in apply-needs-input.bats

### Description

Update `test/bats/apply-needs-input.bats` to isolate all tests from the real Discord notifier by default:

1. In `setup()`, after the existing `DISCORD_SEND_STUB` assignment, add:
   ```bash
   export DISCORD_SEND_SCRIPT="$DISCORD_SEND_STUB"
   export DISCORD_STUB_OUT="$BATS_TEST_TMPDIR/discord-out.txt"
   unset DISCORD_WEBHOOK_URL
   ```
   - `DISCORD_SEND_SCRIPT` makes all tests default to the stub. Tests that pass `DISCORD_SEND_SCRIPT=...` via `env` in their body override this (the explicit-stub and explicit-failing-stub tests are unaffected).
   - `DISCORD_STUB_OUT` gives every test a writable output path so assertions can check the stub's capture file.
   - `unset DISCORD_WEBHOOK_URL` is belt-and-suspenders: even if the stub override is bypassed, the real notifier finds no webhook URL and exits silently.

2. Update the `happy path` test to verify the stub was called with the correct message:
   ```bash
   @test "happy path: all three steps succeed" {
       run "$SCRIPT" myrepo 42 beads-123 "Please clarify X"
       [ "$status" -eq 0 ]
       grep -qF "Human input requested: https://github.com/wcjordan/myrepo/issues/42" \
           "$DISCORD_STUB_OUT"
   }
   ```

3. Remove the local `DISCORD_STUB_OUT` variable from the `"sends Discord notification..."` test (it now inherits from `setup()`), keeping its explicit `DISCORD_WEBHOOK_URL` and `DISCORD_SEND_SCRIPT` overrides.

### Acceptance Criteria

- `make test` passes when `DISCORD_WEBHOOK_URL` is set in the environment — no real Discord call is made during tests.
- `make test` passes when `DISCORD_WEBHOOK_URL` is unset.
- The `happy path` test asserts the stub captured `"Human input requested: https://github.com/wcjordan/myrepo/issues/42"`.
- The `sends Discord notification when DISCORD_WEBHOOK_URL is set` test still passes.
- The `required steps run even when Discord send fails` test still passes.
- The `does not fail when DISCORD_WEBHOOK_URL is unset` test still passes.
