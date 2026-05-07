# MDOMO-4 Spec: Add Additional Disallows to pre-bash-guard.sh and agent-settings.json

## Source

GitHub Issue #3 — https://github.com/wcjordan/minordomo/issues/3

## Goal

Extend the existing safety controls in two places:
- `hooks/pre-bash-guard.sh` — secondary regex-based guard (defence-in-depth)
- `majordomo/agent-settings.json` — primary Claude Code permission deny list

## Commands to Block

From GH Issue #3:
- `mkfs`
- `fdisk`
- `diskutil`
- `shutdown`
- `reboot`
- `nvram`
- `csrutil`
- `launchctl`
- `systemsetup`
- `networksetup`
- `brew install`
- `npm install -g`

---

## Implementation Plan

### Stage 1 — Add disallows to agent-settings.json and pre-bash-guard.sh

**Jira task:** MDOMO-6

**Description:**
Add the 12 new blocked commands to both safety layers.

**Changes:**

#### `majordomo/agent-settings.json`

Add to the `permissions.deny` array:

```json
"Bash(mkfs*)",
"Bash(fdisk*)",
"Bash(diskutil*)",
"Bash(shutdown*)",
"Bash(reboot*)",
"Bash(nvram*)",
"Bash(csrutil*)",
"Bash(launchctl*)",
"Bash(systemsetup*)",
"Bash(networksetup*)",
"Bash(brew install*)",
"Bash(npm install -g*)"
```

#### `hooks/pre-bash-guard.sh`

Add regex-based blocks for each command. Group the single-word commands together and handle multi-word patterns (`brew install`, `npm install -g`) separately.

Single-word system-destructive commands:
```bash
if matches '\b(mkfs|fdisk|diskutil|shutdown|reboot|nvram|csrutil|launchctl|systemsetup|networksetup)\b'; then
    block "system-destructive command not allowed"
fi
```

Package manager global installs:
```bash
if matches '\bbrew\s+install\b'; then
    block "brew install not allowed"
fi
if matches '\bnpm\s+install\s+(.*\s)?-g\b'; then
    block "npm install -g not allowed"
fi
```

**Acceptance Criteria:**
- All 12 commands are present in `agent-settings.json` deny list
- All 12 commands are blocked by `pre-bash-guard.sh` (test with representative inputs)
- Existing guards are unchanged and still pass
- No test suite failures (repo has no automated tests; manual spot-check sufficient)

**Estimated effort:** ~15 minutes

---

## Out of Scope

- Changes to network-level firewall rules
- Blocking variations like `sudo shutdown` (already covered by the existing `sudo` guard)
- Adding new allow-list entries
