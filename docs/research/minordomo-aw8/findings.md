# Research: Remove remaining Jira references after migration

## Findings

All remaining Jira references are straightforward text/comment cleanup. No logic changes needed.

### `majordomo/system-prompt.md`

**Line 90** — Step heading: `### Step 4: Sync PR Merge Status to Jira`
- The step body is already fully beads-based (no Jira calls). Only the heading title is stale.
- Fix: rename to `### Step 4: Sync PR Merge Status`

**Lines 173, 177** — Dead references to "Jira transition":
- Line 173: `3. After the Jira transition and Jenkins trigger, claim the beads Plan bead:`
- Line 177: `If the claim fails, log a warning and continue — the Jira transition and Jenkins trigger already succeeded.`
- There is no Jira transition step anymore (Step 5 goes directly to Jenkins trigger + beads claim).
- Fix: remove "Jira transition and" from both lines.

**Line 240** — Stale migration note in Step 7:
- `⚠️ **Removed in Stage 5 of the Jira→beads migration.** The beads dependency graph ... Jira's \`Ready\` status is populated by the worker agent itself when it picks up a task.`
- Fix: Remove references to "Jira→beads migration" and "Jira's Ready status". Keep the functional explanation.

### `docs/FUTURE_WORK.md`

**Lines 80–82** — Worker Crash section still describes Jira-based recovery flow:
- "Worker posts a comment on the Jira ticket describing where it stopped and why"
- "Worker transitions ticket to **Ready** (can retry) or **Needs Input** (human answer required)"
- Fix: Update to reflect beads-based recovery (worker posts on GH issue / updates beads task).

### `.beads/config.yaml`

**Line 53** — Commented-out jira config keys:
- `# - jira.url, jira.project`
- Fix: Remove this comment line. The surrounding comment block can stay (it documents integration pattern).

### `.claude/settings.local.json`

- **Not tracked in git** — this file has never been committed and is presumably git-ignored.
- Cannot be cleaned up via a PR. The issue author should remove the Jira MCP entries from their local machine.
- Out of scope for this implementation.
