# Research: Remove Plan tasks from Majordomo in-progress filter

## Context

GH Issue #180 / MDOMO-123. This is a cleanup task following PR #178
("Remove Jira Plan task interactions from Majordomo").

## Change Location

`majordomo/system-prompt.md`, Step 4 ("Sync PR Merge Status to Jira"), sub-step 1.

Lines 105–107 currently read:

```
   Separate into:
   - **Stage tasks**: title starts with `"Stage"` (Implementation Tasks)
   - **Plan tasks**: title starts with `"Plan:"` (Planning Tasks)
```

The Plan tasks bullet (line 107) must be removed. With only one category remaining,
the "Separate into:" phrasing is also misleading — it should be simplified to just
identify Stage tasks.

## What Step 4 Does With Each Category

- **Stage tasks**: processed in sub-step 4 ("For each Stage task…") — check PR merged, transition Jira to Done, close beads subtask.
- **Plan tasks**: were identified here but NOT processed in Step 4. They are handled exclusively by Step 5 ("Evaluate Planning Tasks") and Step 6 ("Plan Approval Spinoff"), both of which query `bd list --status=in_progress --json` independently and filter for `Plan:` prefix themselves.

Removing the Plan tasks bullet from Step 4's separation list does not affect Steps 5 or 6 — they are self-contained.

## Minimal Edit

Remove the Plan tasks bullet and clean up the "Separate into:" line so Step 4 reads clearly with only Stage tasks. No other files need changes.
