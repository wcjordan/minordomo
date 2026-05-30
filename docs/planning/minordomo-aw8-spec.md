# Plan: Remove remaining Jira references after migration

## Summary

Clean up stale Jira references left in the codebase after the Jira→beads migration completed in #227. All changes are text/comment cleanup — no logic changes are needed.

The `.claude/settings.local.json` file mentioned in the issue is not tracked in git and cannot be cleaned up via a PR; the developer should handle that locally.

---

## Stage 1: Remove stale Jira references from system-prompt, docs, and config

### Description

Remove all remaining Jira references across three files:

1. **`majordomo/system-prompt.md`**:
   - Line 90: Rename `### Step 4: Sync PR Merge Status to Jira` → `### Step 4: Sync PR Merge Status`
   - Line 173: Change `After the Jira transition and Jenkins trigger, claim` → `After the Jenkins trigger, claim`
   - Line 177: Change `the Jira transition and Jenkins trigger already succeeded` → `the Jenkins trigger already succeeded`
   - Line 240: Remove the Jira-specific parts of the migration note. Replace the entire paragraph with a clean explanation that doesn't reference Jira.

2. **`docs/FUTURE_WORK.md`**:
   - Lines 80–82: Update the Worker Crash section to reflect beads-based recovery. Remove "posts a comment on the Jira ticket" and "transitions ticket to Ready/Needs Input" language. Replace with equivalent beads/GH terminology.

3. **`.beads/config.yaml`**:
   - Line 53: Remove the comment `# - jira.url, jira.project` from the integration settings comment block.

### Acceptance Criteria
- `grep -rn "Jira\|jira\|JIRA" majordomo/system-prompt.md docs/FUTURE_WORK.md .beads/config.yaml` returns no matches
- `make test` passes
- The Step 4 heading in `majordomo/system-prompt.md` reads `### Step 4: Sync PR Merge Status`
- Lines 173/177 in `majordomo/system-prompt.md` no longer reference "Jira transition"
- Step 7 note in `majordomo/system-prompt.md` no longer references "Jira→beads migration" or "Jira's Ready status"
- `docs/FUTURE_WORK.md` Worker Crash section describes beads/GH-based recovery without Jira references
