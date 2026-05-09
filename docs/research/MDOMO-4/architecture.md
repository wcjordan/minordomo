# MDOMO-4 Architecture Research

## Repository Structure

The minordomo repo at `github.com/wcjordan/minordomo` has two relevant branches:

- **`main`**: Bootstrap state — only contains `README.md` (12 bytes, "# minordomo")
- **`bootstrap_stage3`**: Contains full pipeline infrastructure with the files we need

The Jenkins planning-agent job checks out the workspace at `bootstrap_stage3`, then
clones the repo again into a `minordomo/` subdirectory on the feature/task branch.

## Files to Add

Both files exist on `bootstrap_stage3` at the workspace root and need to be introduced
to the `main`-descended feature branch with the additional disallows:

### `hooks/pre-bash-guard.sh`

Shell hook that runs before every Bash tool invocation. Uses regex matching (`matches()`)
to block dangerous patterns. Exits 0 to allow, 1 to block.

Located at: `hooks/pre-bash-guard.sh` (relative to repo root)

Referenced in `majordomo/agent-settings.json` via:
```json
"hooks": { "PreBashCommand": "~/.claude/hooks/pre-bash-guard.sh" }
```

Deployed by `majordomo/jenkins/shared/setup-claude.sh`:
```bash
cp hooks/pre-bash-guard.sh ~/.claude/hooks/pre-bash-guard.sh
```

### `majordomo/agent-settings.json`

Claude Code settings file deployed to `~/.claude/settings.json`. Contains:
- `permissions.allow` — broad allow list (Bash, Read, Edit, Write, mcp__atlassian__*)
- `permissions.deny` — glob-pattern deny list
- `hooks.PreBashCommand` — path to pre-bash-guard.sh

Deployed by `majordomo/jenkins/shared/setup-claude.sh`:
```bash
cp majordomo/agent-settings.json ~/.claude/settings.json
```

## Current Disallows (bootstrap_stage3 versions)

### In agent-settings.json deny list:
- `Bash(git push --force*)`
- `Bash(git push -f *)`
- `Bash(git commit --no-verify*)`
- `Bash(git rebase*)`
- `Bash(sudo *)`
- `Bash(rm -rf /*)`
- `Bash(curl *metadata.google.internal*)`
- `Bash(curl *169.254.169.254*)`

### In pre-bash-guard.sh:
- Force push (`git push` with `--force` or `-f`)
- `git commit --no-verify`
- `git rebase`
- `sudo`
- Recursive rm on system paths
- Access to 169.254.169.254 (AWS IMDS)
- Access to metadata.google.internal (GCP)
- curl/wget piped to shell interpreter
- Process substitution shell execution (`bash <(...)`)
- Dynamic eval with variable expansion

## New Disallows Required (from GitHub Issue #3)

```
mkfs, fdisk, diskutil, shutdown, reboot, nvram, csrutil,
launchctl, systemsetup, networksetup, brew install, npm install -g
```

## Implementation Approach

The worker should:
1. Copy both files from the running environment (`../hooks/pre-bash-guard.sh` and
   `../majordomo/agent-settings.json`) into the minordomo task branch, or recreate them
   based on the bootstrap_stage3 content
2. Add the 12 new disallow patterns to both files
3. Commit to `task/MDOMO-6`, push, and open a PR targeting `feature/MDOMO-4`

The simplest approach is to read the files from `../` (the workspace root, which is the
bootstrap_stage3 checkout) and copy + modify them into the minordomo subdir.
