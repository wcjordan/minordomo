# Research Notes: Planning Agent Failure Recovery (minordomo-zci)

## Scope
Covers planning agent controlled exits only — cases where the agent can self-report before
exiting. Jenkins-level crashes (container dies mid-run) are out of scope; covered by the
sweep job (separate issue). Mirrors the worker crash handling issue (minordomo-gzq).

## Current Planning Agent Exit Behaviour

### Questions Path (needs-input flow — already exists)
`minordomo-plan/system-prompt.md` has a "Questions Path" section:
1. Calls `shared/apply-needs-input.sh minordomo "${gh_issue_number}" "${BEADS_TASK_ID}" "<questions>"`
   - applies `needs-input` label to GH issue
   - posts questions to GH issue as a comment
   - resets beads task to open via `beads-write.sh`
2. Commits `docs/research/$EPIC_KEY/` and pushes
3. Emits run log and exits 0

**Gaps:**
- No Jira comment posted
- Commit of research happens AFTER apply-needs-input, so if apply-needs-input fails,
  research notes may not be committed

### Error/Crash Exit (does not exist)
The prompt says: "On any unrecoverable error, record it in errors, emit the log, and exit 1."
There is only one such generic instruction (no per-step exit 1s).

**Gaps:**
- Beads task left `in_progress` indefinitely
- No partial work committed
- No Jira comment posted

### Spec/PR Path (success — already exists)
1. Writes `docs/planning/$EPIC_KEY-spec.md`
2. Commits spec + research and pushes
3. Opens PR
4. Emits run log and exits 0

No changes needed to the success path.

## Key Scripts

### `shared/get-epic-key.sh <beads_task_id> <repo>`
Output (one per line):
1. Story bead ID (EPIC_KEY)
2. GH_ISSUE_NUMBER
3. JIRA_EPIC_KEY (e.g. MDOMO-133)

### `shared/apply-needs-input.sh <repo> <issue_number> <beads_task_id> <comment_body>`
3-step needs-input protocol: GH label + GH comment + beads reset. Already called by questions path.

### `shared/beads-write.sh update <id> --status open`
Resets beads task to open (dolt pull → bd update → dolt push).

### `shared/jira-transition.sh`
Pattern reference for `post-jira-comment.sh` — same `JIRA_URL`/`JIRA_EMAIL`/`JIRA_API_TOKEN`
auth, same `curl -sf -u` pattern, same `set -euo pipefail` shape.

## Environment Available to Planning Agent
- `$BEADS_TASK_ID` — the planning task bead ID (e.g. minordomo-zci.1)
- `$EPIC_KEY` — Story bead ID (e.g. minordomo-zci); exported by setup-workspace.sh
- `$FEATURE_BRANCH` — feature branch name; exported by setup-workspace.sh
- `$REPO` — repo name (e.g. minordomo); exported by setup-workspace.sh
- `$JIRA_URL`, `$JIRA_EMAIL`, `$JIRA_API_TOKEN` — Jira credentials from environment
- JIRA_EPIC_KEY NOT available as env var — must be derived via get-epic-key.sh line 3

## Key Design Decisions

### Asymmetry from worker: planner posts to Jira, worker posts to GH issue
The GH issue acceptance criteria explicitly say "posts a comment on the Jira ticket" for the
planner. The worker spec (minordomo-gzq) posts to the GH issue. This is intentional: the
planner is creating the plan for a Jira epic, so the Jira epic is where planning status belongs.
The specs are independent — the worker scripts (post-gh-issue-comment.sh, worker-error-exit.sh)
are not available yet and are not depended on here.

### New script: `shared/post-jira-comment.sh`
Atomic building block: posts a comment to a Jira issue via REST API.
Pattern from jira-transition.sh: curl -sf -u, JIRA_URL/rest/api/3/issue/{key}/comment POST.

### New script: `shared/planner-error-exit.sh`
Composite script for the crash exit path:
1. get-epic-key.sh → get JIRA_EPIC_KEY (best-effort; if fails, skip Jira comment, continue)
2. post-jira-comment.sh (best-effort; if fails, log, continue)
3. beads-write.sh update "$BEADS_TASK_ID" --status open (required; exits non-zero on failure)

### Questions Path Jira comment
The questions path already calls apply-needs-input.sh (which resets beads).
Adding a Jira comment after apply-needs-input.sh: call get-epic-key.sh inline to read
JIRA_EPIC_KEY, then call post-jira-comment.sh. Both are best-effort in this path.
Do NOT reuse planner-error-exit.sh in the questions path — its name implies error semantics
and it would double-reset beads (extra dolt pull/push with no benefit).

### Partial work commits
Commit message convention (matches worker spec): `[partial] <brief description>`
Skip commit if working tree is clean (no empty commits).
Cover: docs/research/$EPIC_KEY/ and docs/planning/$EPIC_KEY-spec.md (if it exists).
If commit or push fails, log failure and continue to the notification/reset steps.

### Stage 3 scope
The planning agent system prompt has only ONE generic "exit 1" instruction (not per-step),
plus two success exits. Stage 3 changes are:
1. Add "Error/Crash Exit Flow" section (new section, near Questions Path)
2. Replace generic exit 1 instruction with reference to Error/Crash Exit Flow
3. Questions Path: move commit step before apply-needs-input.sh call + add Jira comment step
4. Run log format update (commit_partial, jira_comment, beads_reset step names)
Budget: well within 30-60 min.
