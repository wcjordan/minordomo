# MDOMO-58: Beads Hierarchy Research

## Feature Request Summary

GitHub Issue: https://github.com/wcjordan/minordomo/issues/86

**Current hierarchy:**
```
Plan: <story title>   ← top-level beads task
  ├── Stage 1: <title>
  ├── Stage 2: <title>
  └── Stage 3: <title>
```

**Desired hierarchy:**
```
Story: <title>   ← new top-level beads task (Epic equivalent)
  ├── Plan: <title>   ← planning task is now a child
  ├── Stage 1: <title>
  ├── Stage 2: <title>
  └── Stage 3: <title>
```

The motivating problem: the Plan task is currently the parent, but it gets closed once the plan PR merges — leaving stages orphaned from a closed parent.

---

## Current Implementation

All changes are in `majordomo/system-prompt.md`.

### Step 3 (Issue Ingestion) — beads creation
Line ~66:
```bash
bd create "Plan: <issue title>" --priority <priority> --description "GH Issue: <issue url>"
```
Creates a top-level Plan bead. No parent.

### Step 5 (Evaluate Planning) — claims Plan bead
Line ~157-159:
```bash
BEADS_PLAN_ID=$(bd list --json | jq -r --arg title "<fields.summary>" '[.[] | select(.title == $title)] | first | .id // empty')
bd update "$BEADS_PLAN_ID" --claim
```
Matches by exact title. No parent-related change needed.

### Step 6 (Plan Approval Spinoff) — creates Stage beads
Lines ~185-199:
```bash
BEADS_PLAN_ID=$(bd list --json | jq -r '[.[] | select(.title == "Plan: <issue title>")] | first | .id // empty')
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_PLAN_ID" --json | jq -r '.id')
bd dep add "$BEADS_STAGE_N_ID" "$BEADS_STAGE_N_MINUS_1_ID"
```
**Stages are currently parented to Plan.** This is the key thing to change.

### Step 9 (Story Completion) — checks beads children
Lines ~319-324:
```bash
BEADS_PLAN_ID=$(bd list --json | jq -r --arg title "Plan: <epic_summary>" \
  '[.[] | select(.title == $title)] | first | .id // empty')
bd list --parent "$BEADS_PLAN_ID" --json | jq 'all(.status == "done")'
```
Checks Plan's children. **Should check Story's children instead.**

---

## Changes Required

### Step 3 — Create Story bead first, then nest Plan under it
```bash
BEADS_STORY_ID=$(bd create "Story: <issue title>" --priority <priority> --description "GH Issue: <issue url>" --json | jq -r '.id')
bd create "Plan: <issue title>" --parent "$BEADS_STORY_ID" --priority <priority> --description "GH Issue: <issue url>"
```

### Step 6 — Find Story bead, create Stages as children of Story
```bash
BEADS_STORY_ID=$(bd list --json | jq -r '[.[] | select(.title == "Story: <issue title>")] | first | .id // empty')
BEADS_STAGE_N_ID=$(bd create "Stage N: <title>" --parent "$BEADS_STORY_ID" --json | jq -r '.id')
```

### Step 9 — Check Story's children instead of Plan's children
```bash
BEADS_STORY_ID=$(bd list --json | jq -r --arg title "Story: <epic_summary>" \
  '[.[] | select(.title == $title)] | first | .id // empty')
bd list --parent "$BEADS_STORY_ID" --json | jq 'all(.status == "done")'
```

---

## Steps NOT Requiring Changes

- **Step 4**: Closes Plan and Stage beads by title match (Plan: exact, Stage: strip prefix) — no parent dependency
- **Step 5**: Claims Plan bead by exact title match — no parent dependency
- **Step 8**: `bd ready` filter excludes Plan-prefixed tasks — unaffected since Plan is still prefixed `Plan:`

---

## Naming Decision

Using `"Story:"` prefix for the new top-level bead because:
1. Consistent with `"Plan:"` and `"Stage N:"` naming conventions
2. Makes pattern matching reliable across all steps
3. Distinguishable from Jira's "Epic" concept (beads mirrors Jira hierarchy but at the story/task level)
