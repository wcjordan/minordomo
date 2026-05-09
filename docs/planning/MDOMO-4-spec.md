# MDOMO-4: Add Additional Disallows to pre-bash-guard.sh and agent-settings.json

## Background

The minordomo repo needs to include the agent security configuration files with an
expanded set of blocked commands. These files are deployed by
`majordomo/jenkins/shared/setup-claude.sh` before each agent run:

- `hooks/pre-bash-guard.sh` → copied to `~/.claude/hooks/pre-bash-guard.sh`
- `majordomo/agent-settings.json` → copied to `~/.claude/settings.json`

Both files currently exist on the `bootstrap_stage3` branch. This plan adds them to the
`main`-descended feature branch with 12 additional blocked commands from GitHub Issue #3.

---

## Stage 1: Add security disallow files with extended blocked-command lists

### Description

Introduce `hooks/pre-bash-guard.sh` and `majordomo/agent-settings.json` into the repo
(task branch based off `main` / `feature/MDOMO-4`) with all currently blocked patterns
plus the 12 new ones from GitHub Issue #3.

**Source content:** The current authoritative versions of both files are available in the
running workspace at `../hooks/pre-bash-guard.sh` and `../majordomo/agent-settings.json`
(one directory up from the repo root). Read those files, add the new disallows, then
write the results into the repo.

**New commands to block** (applies to both files):
- `mkfs` — formats filesystems
- `fdisk` — disk partition editor
- `diskutil` — macOS disk utility
- `shutdown` — system shutdown
- `reboot` — system reboot
- `nvram` — macOS NVRAM tool
- `csrutil` — macOS SIP toggle
- `launchctl` — macOS launchd service manager
- `systemsetup` — macOS system setup
- `networksetup` — macOS network config
- `brew install` — Homebrew package install
- `npm install -g` — global npm package install

**For `majordomo/agent-settings.json`:**
Add one deny entry per command using Claude Code glob syntax. Simple commands can use
`"Bash(<cmd> *)"` or `"Bash(<cmd>*)"`. For subcommand variants (`brew install`,
`npm install -g`) use `"Bash(brew install*)"` and `"Bash(npm install -g*)"`.

**For `hooks/pre-bash-guard.sh`:**
Add one `if matches ... ; then block "..."; fi` stanza per command (or group related
single-word commands into one stanza). Use `\b<cmd>\b` word-boundary regex for single
commands. For subcommand forms (`brew install`, `npm install -g`) use patterns that match
the full subcommand sequence.

Also create the required directory structure:
- `hooks/` directory with `pre-bash-guard.sh`
- `majordomo/` directory with `agent-settings.json`

### Acceptance Criteria

- `hooks/pre-bash-guard.sh` exists in the repo, is executable (`chmod +x`), and blocks
  each of the 12 new commands (the `matches` + `block` stanzas are present for all of
  them)
- `majordomo/agent-settings.json` exists in the repo and its `permissions.deny` array
  contains deny entries for all 12 new commands
- Both files retain all previously existing disallow rules (no regressions)
- All existing tests pass (or there are no tests yet — acceptable for this task)
- A PR is open from `task/MDOMO-6` targeting `feature/MDOMO-4`
