# Implementation Plan: Add Additional Disallows to pre-bash-guard.sh and agent-settings.json

Epic: MDOMO-4
GitHub Issue: https://github.com/wcjordan/minordomo/issues/3

---

## Stage 1: Add 12 new blocked commands to shared/pre-bash-guard.sh and shared/agent-settings.json

### Description

Extend the agent security configuration with 12 new blocked commands specified in GitHub Issue #3. Changes land in two files:

1. **`shared/pre-bash-guard.sh`** — add `if matches` blocks for each new command using the existing regex guard pattern.
2. **`shared/agent-settings.json`** — add glob deny entries for each new command.

New commands to block: `mkfs`, `fdisk`, `diskutil`, `shutdown`, `reboot`, `nvram`, `csrutil`, `launchctl`, `systemsetup`, `networksetup`, `brew install` (including shorthand `brew i`), `npm install -g` (including `npm i -g` and `--global` variants).

Also create **`test/bats/pre-bash-guard.bats`** — the only shared script without a bats test file. Cover both the new blocks and the pre-existing ones (force push, sudo, rm -rf, IMDS, etc.).

### Acceptance Criteria

- `shared/pre-bash-guard.sh` blocks all 12 new commands: mkfs, fdisk, diskutil, shutdown, reboot, nvram, csrutil, launchctl, systemsetup, networksetup, brew install, npm install -g
- `shared/agent-settings.json` deny list includes entries for all 12 new commands
- `brew install` block also covers `brew i` (shorthand)
- `npm install -g` block also covers `npm i -g`, `npm install --global`, `npm i --global`
- `test/bats/pre-bash-guard.bats` exists and passes for all new blocks
- `make test` passes (shellcheck clean, bats suite green)
