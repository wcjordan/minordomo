# Implementation Plan: MDOMO-99

Close issues when PR is merged by using "Resolves #123" in the PR description.

## Stage 1: Replace "Implements" with "Resolves" in majordomo PR body template

### Description
In `majordomo/system-prompt.md`, the `check_story_completion` step builds a PR body
that includes `Implements: <GH Issue URL>`. GitHub does not recognize `Implements` as
a closing keyword, so the linked issue is never auto-closed when the PR merges.

Change the PR body template to use `Resolves: <GH Issue URL>` instead. GitHub
recognizes `resolves` as a closing keyword and will auto-close the linked issue when
the PR is merged into the base branch.

### Acceptance Criteria
- In `majordomo/system-prompt.md`, the PR body template line `Implements: <GH Issue URL>` is replaced with `Resolves: <GH Issue URL>`
- `make test` passes without any other changes
