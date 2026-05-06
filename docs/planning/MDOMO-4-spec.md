# MDOMO-4 Spec: Add Additional Disallows to pre-bash-guard.sh and agent-settings.json

## Background

GitHub Issue #3 identified 12 commands that should be blocked in the minordomo agent
harness as additional safety measures. These need to be added to both the Claude Code
permission deny list (`majordomo/agent-settings.json`) and the defence-in-depth bash
guard hook (`hooks/pre-bash-guard.sh`).

## Commands to Block

1. `mkfs` — creates filesystems; destructive to storage devices
2. `fdisk` — partitions disks; destructive to storage devices
3. `diskutil` — macOS disk utility; destructive to storage devices
4. `shutdown` — powers off or reboots the system
5. `reboot` — reboots the system
6. `nvram` — reads/writes NVRAM/PRAM; can corrupt firmware settings
7. `csrutil` — macOS SIP control; modifies system integrity protection
8. `launchctl` — macOS launchd control; can start/stop system services
9. `systemsetup` — macOS system configuration; changes system-level settings
10. `networksetup` — macOS network configuration; can disrupt network access
11. `brew install` — installs packages; global side effects, supply chain risk
12. `npm install -g` — installs global npm packages; global side effects

## Implementation Plan

### Stage 1 (single stage — scope is narrow and self-contained)

**Estimated effort:** ~15 minutes

#### 1. `majordomo/agent-settings.json` — deny list additions

Add entries to `permissions.deny` for each of the 12 commands. Use glob patterns
consistent with existing entries:

- Single-word commands: `Bash(<cmd>*)` to catch bare invocations and with arguments
- Multi-word commands: `Bash(<prefix> <subcommand>*)` to catch the subcommand pattern

#### 2. `hooks/pre-bash-guard.sh` — regex guard additions

Add two new guard blocks:

- **System commands block**: one regex covering all 10 single-word commands using
  alternation, anchored to word boundaries and start-of-command positions
- **Package install block**: separate regex covering `brew install` and
  `npm install -g` patterns

## Acceptance Criteria

- [ ] All 12 commands appear in `permissions.deny` in `majordomo/agent-settings.json`
- [ ] All 12 commands are matched by guards in `hooks/pre-bash-guard.sh`
- [ ] The existing guards in `pre-bash-guard.sh` are unchanged
- [ ] The existing allow/deny entries in `agent-settings.json` are unchanged
