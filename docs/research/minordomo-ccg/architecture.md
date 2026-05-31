# Research: Bug Fix — Bead IDs Get minordomo- Prefix for All Repos

## GH Issue
https://github.com/wcjordan/minordomo/issues/240

## Root Cause

`bd` always runs in the `minordomo` workspace, so all bead IDs it creates start with `minordomo-` regardless of which GitHub repo they represent. Example: a `gcp-setup` issue creates bead `minordomo-wkg`, not `gcp-setup-wkg`.

## Current Broken Pattern

`shared/setup-workspace.sh` (lines 15–28) and `majordomo/system-prompt.md` (multiple steps) both derive the target repo by longest-prefix-matching the bead ID against `config.yaml` repos:

```python
repos = sorted([p['repo'] for p in cfg['projects']], key=len, reverse=True)
for repo in repos:
    if beads_id.startswith(repo + '-'):
        print(repo)
```

This always resolves to `repo=minordomo` because every bead ID starts with `minordomo-`.

## Correct Approach

The GH issue URL is already stored in the Story bead's `description` field, e.g.:
`GH Issue: https://github.com/wcjordan/gcp-setup/issues/16`

The repo can be extracted from that URL: `gcp-setup`.

`shared/get-story-key.sh` already extracts the full GH URL (line 49) and GH issue number (line 56). It needs to also extract and output the repo name on a third line.

## Files to Change

### 1. `shared/get-story-key.sh`
- The `REPO` parameter (line 9–11) is currently accepted but never used (comment `# shellcheck disable=SC2034`). It should be made optional (no longer required).
- After extracting `GH_ISSUE_URL`, also extract the repo name from it.
- Output repo name on line 3: `echo "${REPO_FROM_URL}"`.
- The function signature change: `REPO` param becomes optional/removed since it's now derived from the URL.

### 2. `shared/setup-workspace.sh`
- Remove the prefix-match block (lines 15–28).
- Replace with: call `get-story-key.sh` and read 3 lines (EPIC_KEY, GH_ISSUE_NUMBER, REPO).
- Move the `get-story-key.sh` call earlier (before REPO is needed for `gh repo clone`).

### 3. `shared/sweep-stale-tasks.sh`
- Lines 54–68: Replace prefix-match with a call to `get-story-key.sh` (now outputs REPO on line 3).
- Lines 86–100: Currently calls `get-story-key.sh "$task_id" "$repo"` (with repo from prefix-match). Update to use new 3-line output.

### 4. `majordomo/system-prompt.md` — 5 occurrences of "Derive repo from beads task ID prefix":
- Step 4.3 (line 105): "Helper: derive repo from a beads task ID" — update to use `get-story-key.sh` (3rd output line)
- Step 5.1a (line 141): prefix-match → use `get-story-key.sh`
- Step 6.2a (line 199): prefix-match → use `get-story-key.sh`
- Step 8.4a (line 263): prefix-match → use `get-story-key.sh`
- Step 9.2b (line ~321): prefix-match → use `get-story-key.sh` (already calls `get-story-key.sh` for EPIC_KEY, just also read line 3 for repo)
- Step 10.2b (line ~427): prefix-match → use `get-story-key.sh`
- Note: Step 9.2b and 10.2b already call `get-story-key.sh` for EPIC_KEY — they just need to also capture line 3.

### 5. Tests
- `test/bats/get-story-key.bats`: Add tests for the 3rd output line (repo name). Update existing tests to verify `wc -l` is now 3 (or check for line 3 specifically).
- `test/bats/setup-workspace.bats`: Update fixtures if needed; test that REPO is derived from GH URL (not prefix-match).
- `test/bats/sweep-stale-tasks.bats`: Update to reflect new approach.

## Fixtures
- `test/fixtures/beads-parent-show.json` — Story bead with `"description": "GH Issue: https://github.com/wcjordan/minordomo/issues/1"` — REPO derived is `minordomo`. Current `setup-workspace.bats` test asserts `REPO=minordomo`, which would still pass with the new approach since the URL contains `minordomo`.

## Key Design Decision
`get-story-key.sh` will no longer take `REPO` as a required second parameter — it will derive REPO from the GH URL and output it. Callers that pass a repo argument can still do so for backward compatibility, OR we can make the param fully optional (since it was already unused). The clean approach is to remove it and update all callers.
