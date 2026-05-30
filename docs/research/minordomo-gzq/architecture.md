# Research Notes: Worker Failure Recovery (minordomo-gzq)

## Scope
Covers worker-controlled exits only — cases where the agent process can self-report before exiting.
Jenkins-level crashes (container dies) are out of scope and handled by a separate sweep job.

## Current Worker Exit Behaviour

### Needs Input Flow (already exists)
`minordomo-step/system-prompt.md` has a "Needs Input Flow" section:
1. Calls `shared/get-epic-key.sh` to get GH_ISSUE_NUMBER
2. Calls `shared/apply-needs-input.sh "$REPO" "$GH_ISSUE_NUMBER" "$BEADS_TASK_ID" "<message>"`
   - Step 1: `gh issue edit` → applies `needs-input` label to GH issue
   - Step 2: `gh issue comment` → posts explanation to GH issue
   - Step 3: `shared/beads-write.sh update <task_id> --status open` → resets beads task
3. Exits with `status: "failure"` and error entry

**Gaps:**
- Does not commit/push partial work before exiting

### Error/Crash Exit (does not exist)
When the worker fails with a hard error (not a needs-input blocker), it:
- Just exits 1 with errors populated in the run log
- Leaves the beads task `in_progress` indefinitely
- Posts no comments anywhere

## Key Scripts

### `shared/get-epic-key.sh <beads_task_id> <repo>`
Output (one per line):
1. Story bead ID (EPIC_KEY)  
2. GH_ISSUE_NUMBER
3. JIRA_EPIC_KEY

### `shared/apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>`
3-step needs-input protocol. Exits non-zero and logs to stderr on failure.

### `shared/beads-write.sh update <id> --status open`
Resets beads task to open (dolt pull → bd update → dolt push).

### `shared/apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>`
Pattern reference for posting to GH issues via `gh issue comment`. Used in the Needs Input flow.

## Design Decisions

### New script: `shared/post-gh-issue-comment.sh`
Per CLAUDE.md: "Any shell command that fetches data, checks state, or calls an API belongs in a file under shared/."
This script takes `gh_issue_number`, `repo`, and `comment_body` and posts a GH issue comment.
Follows the same pattern as `apply-needs-input.sh` (uses `gh issue comment`).

### Worker system prompt changes
Two exit paths need updating:

1. **Needs Input path** — add before apply-needs-input.sh:
   - Commit and push partial work (with `[partial]` prefix in commit message)
   - `apply-needs-input.sh` already handles the GH issue comment; no additional notification needed

2. **New error/crash path** — add new section for hard failures:
   - Commit and push any partial/completed work
   - Call get-epic-key.sh to get GH_ISSUE_NUMBER (line 2)
   - Post GH comment via post-gh-issue-comment.sh describing what stopped
   - Reset beads task to open via `shared/beads-write.sh update "$BEADS_TASK_ID" --status open`

### Partial work commits
Commit message prefix `[partial]` makes it clear the branch is mid-implementation.
Worker instructions should say: "git add -A && git commit -m '[partial] <brief description of what was completed' && git push".
If nothing is staged, skip the commit (don't create empty commits).

## Test Patterns
- `test/bats/apply-needs-input.bats` — reference for mocking `gh` CLI calls in post-gh-issue-comment.sh tests
