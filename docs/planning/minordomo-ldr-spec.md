# Implementation Plan: Remove Plan tasks separation from Majordomo in-progress task filter

## Stage 1: Remove Plan tasks bullet from Step 4 of majordomo/system-prompt.md

### Description
Remove the `- **Plan tasks**: title starts with `"Plan:"` (Planning Tasks)` bullet from Step 4's in-progress task separation list in `majordomo/system-prompt.md`. With only Stage tasks remaining in that list, also simplify the surrounding "Separate into:" prose to read cleanly without the two-category split. No other files need changes — Steps 5 and 6 query and filter for Plan tasks independently.

### Acceptance Criteria
- The line `- **Plan tasks**: title starts with `"Plan:"` (Planning Tasks)` no longer appears in `majordomo/system-prompt.md`.
- Step 4's sub-step 1 reads clearly with only Stage tasks identified (the "Separate into:" phrasing is updated or removed to match).
- Steps 5 and 6 are unchanged.
- `make test` passes.
