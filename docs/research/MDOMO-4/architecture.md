# MDOMO-4 Research: Security Disallow Architecture

## Files to Modify

Two files control what commands agents can run:

1. **`shared/pre-bash-guard.sh`** — bash hook that runs before every `Bash` tool invocation. Uses `matches()` (which wraps `grep -qE`) to block commands via regex. Exits 1 to block, 0 to allow.

2. **`shared/agent-settings.json`** — Claude Code permissions config. The `deny` list uses glob patterns like `Bash(git push --force*)`. This is the primary control; `pre-bash-guard.sh` is defence-in-depth.

Both files are deployed into agent containers at startup by `shared/setup-claude.sh`:
- `agent-settings.json` → `~/.claude/settings.json`
- `pre-bash-guard.sh` → `~/.claude/hooks/pre-bash-guard.sh`

## Existing Deny Patterns

### pre-bash-guard.sh
- `git push --force` / `git push -f`
- `git commit --no-verify`
- `git rebase`
- `sudo`
- `rm -rf` on system paths
- Access to `169.254.169.254` (AWS IMDS)
- Access to `metadata.google.internal` (GCP)
- `curl/wget | bash/sh/python/...` (remote code execution)
- `bash <(...)` (process substitution)
- `eval $...` (dynamic eval)

### agent-settings.json
- `git push --force*`, `git push -f *`
- `git commit --no-verify*`
- `git rebase*`
- `sudo *`
- `rm -rf /*`
- `curl *metadata.google.internal*`, `curl *169.254.169.254*`

## New Commands to Block (GitHub Issue #3)

| Command | Rationale |
|---|---|
| mkfs | Filesystem formatting |
| fdisk | Disk partitioning |
| diskutil | macOS disk utility |
| shutdown | System shutdown |
| reboot | System reboot |
| nvram | macOS NVRAM firmware access |
| csrutil | macOS SIP (System Integrity Protection) control |
| launchctl | macOS service/daemon manager |
| systemsetup | macOS system configuration |
| networksetup | macOS network configuration |
| brew install | Homebrew package installation |
| npm install -g | Global npm package installation |

## Pattern Design

### pre-bash-guard.sh regex patterns

Simple commands (block any use):
- `\bmkfs\b` — covers mkfs, mkfs.ext4, mkfs.vfat, etc.
- `\bfdisk\b`
- `\bdiskutil\b`
- `\bshutdown\b`
- `\breboot\b`
- `\bnvram\b`
- `\bcsrutil\b`
- `\blaunchctl\b`
- `\bsystemsetup\b`
- `\bnetworksetup\b`

Compound commands (block specific subcommands):
- `brew\s+(install|i)\b` — blocks `brew install` and shorthand `brew i`
- `npm\s+(install|i)\s+.*(-g\b|--global\b)` — blocks `npm install -g`, `npm i -g`, `npm install --global`

### agent-settings.json glob patterns

- `Bash(mkfs*)` — covers `mkfs`, `mkfs.ext4`, etc.
- `Bash(fdisk*)`, `Bash(diskutil*)`, `Bash(shutdown*)`, `Bash(reboot*)`
- `Bash(nvram*)`, `Bash(csrutil*)`, `Bash(launchctl*)`, `Bash(systemsetup*)`, `Bash(networksetup*)`
- `Bash(brew install*)`, `Bash(brew i *)` — brew install shorthand
- `Bash(npm install -g*)`, `Bash(npm install --global*)`, `Bash(npm i -g*)`, `Bash(npm i --global*)` — global npm install variants

## Testing

No `pre-bash-guard.bats` exists yet. Tests for the other shared scripts live in `test/bats/` and follow a consistent pattern. A `pre-bash-guard.bats` should be added covering both existing and new blocks.

Test runner: `make test` → `test/run-all.sh` (runs shellcheck, validate-prompts, dry-run, bats).

## Previous PR

PR #12 was closed without merge. It referenced wrong paths (`hooks/pre-bash-guard.sh`, `majordomo/agent-settings.json`) and proposed copying files from a bootstrap stage rather than editing the existing files in `shared/`. The new spec should edit `shared/pre-bash-guard.sh` and `shared/agent-settings.json` directly.
