# Implementation Plan: Remove Remaining Jira Integration

Epic: minordomo-nti  
GH Issue: https://github.com/wcjordan/minordomo/issues/216

---

## Stage 1: Replace get-epic-key.sh with get-story-key.sh

### Description

`shared/get-epic-key.sh` outputs three lines: Story bead ID, GH issue number, and Jira Epic key. The Jira Epic key (line 3) will no longer exist after Jira is removed. This stage creates a 2-output replacement (`shared/get-story-key.sh`) and updates **all** callers in the same PR so the 3-line contract is fully replaced atomically.

Callers that must be updated in this stage:
- `shared/setup-workspace.sh` — reads 3 lines (`EPIC_KEY`, `_GH_ISSUE_NUMBER`, `_JIRA_EPIC_KEY`); update to 2 lines
- `majordomo/system-prompt.md` Step 4 helper — reads 3 lines (`EPIC_KEY`, `GH_ISSUE_NUMBER`, `JIRA_EPIC_KEY`); update to 2 lines and remove `JIRA_EPIC_KEY` usage throughout Steps 4, 9, 10
- `minordomo-step/system-prompt.md` Needs Input Flow Step 1 — reads 3 lines (`_EPIC_KEY`, `GH_ISSUE_NUMBER`, `_JIRA_EPIC_KEY`); update to 2 lines

Steps:
1. Create `shared/get-story-key.sh` as a copy of `shared/get-epic-key.sh` with the Jira Epic lookup block removed. The script outputs exactly 2 lines: Story bead ID and GH issue number.
2. Create `test/bats/get-story-key.bats` as an updated copy of `test/bats/get-epic-key.bats` — remove all tests that assert on the 3rd output line (Jira Epic key) and update happy-path tests to assert on 2 output lines only. Remove the test "failure: no Jira Epic comment in GH issue" (no longer applicable). Remove the gh mock that returns a Jira Epic comment (gh is no longer called by the new script).
3. Update `shared/setup-workspace.sh` to call `get-story-key.sh` instead of `get-epic-key.sh` and read only 2 output lines.
4. Update `majordomo/system-prompt.md` Step 4 helper, Step 9 sub-step f, and Step 10 sub-step f to call `shared/get-story-key.sh` and read only 2 lines. Remove all `JIRA_EPIC_KEY` variables and usages.
5. Update `minordomo-step/system-prompt.md` Needs Input Flow Step 1 to call `shared/get-story-key.sh` and read only 2 lines.
6. Update `test/bats/setup-workspace.bats` to mock `get-story-key.sh` instead of `get-epic-key.sh`, remove the Jira Epic comment from the gh mock response, and update comment references.
7. Do NOT delete `shared/get-epic-key.sh` or `test/bats/get-epic-key.bats` yet — those are removed in Stage 2.

### Acceptance Criteria
- `shared/get-story-key.sh` exists and outputs exactly 2 lines (Story bead ID, GH issue number)
- `test/bats/get-story-key.bats` exists with tests covering the same beads traversal cases, minus the Jira Epic assertion
- No caller of `get-epic-key.sh` reads a 3rd line (JIRA_EPIC_KEY)
- All callers in `setup-workspace.sh`, `majordomo/system-prompt.md`, and `minordomo-step/system-prompt.md` call `get-story-key.sh`
- `make test` passes

---

## Stage 2: Remove Jira from Majordomo System Prompt and Delete Jira Scripts

### Description

Remove all Jira Epic management from `majordomo/system-prompt.md` and delete `shared/jira-transition.sh` and `shared/get-epic-key.sh` along with their test files.

Changes to `majordomo/system-prompt.md`:

**Step 1 (Load Config)**: Remove `jira_key` from the required fields per project entry validation. Update the run log example to remove `jira_key` from project entries.

**Step 3 (Poll GH Issues)**: 
- Remove sub-step 4 (skip if `jira-epic-created` label). The new idempotency gate is `beads-ingested` (already checked in sub-step 5f of the original). Rewrite the idempotency check: skip issues that already have the `beads-ingested` label.
- Remove sub-step 5a (`mcp__atlassian__createJiraIssue` call — creating the Jira Epic).
- Remove sub-step 5b (posting `"Jira Epic: <KEY>"` comment on GH issue).
- Remove sub-step 5c (applying the `jira-epic-created` label).
- Renumber and clean up the remaining sub-steps so they are coherent.

**Step 6 (Plan Approval Spinoff)**, sub-step n: Remove the `shared/jira-transition.sh "${JIRA_EPIC_KEY}" "In Review"` call entirely. Remove the note about Jira credentials at the top of Step 6.

**Step 9 (Open Feature → Main PRs)**: Remove the note "Use `${JIRA_EMAIL}:${JIRA_API_TOKEN}` basic auth and `${JIRA_URL}` for Jira REST writes in this step." Sub-step f already updated in Stage 1 (no `JIRA_EPIC_KEY`); confirm clean.

**Step 10 (Close Completed Epics)**: Remove the note "Use `${JIRA_EMAIL}:${JIRA_API_TOKEN}` basic auth...". Sub-step f already updated in Stage 1; sub-step i `shared/jira-transition.sh "${EPIC_KEY}" "Done"` — remove this call entirely (the sub-step collapses to just closing the Story bead).

**Environment section**: Remove the Jira instance line (`${JIRA_URL}`) and references to `JIRA_EMAIL` and `JIRA_API_TOKEN`.

Files to delete:
- `shared/jira-transition.sh`
- `shared/get-epic-key.sh`
- `test/bats/jira-transition.bats`
- `test/bats/get-epic-key.bats`
- `test/fixtures/jira-task-response.json`

Update `shared/config.yaml`: remove the `jira_key` field from every project entry.

### Acceptance Criteria
- `shared/jira-transition.sh` does not exist
- `shared/get-epic-key.sh` does not exist
- `test/bats/jira-transition.bats` does not exist
- `test/bats/get-epic-key.bats` does not exist
- `test/fixtures/jira-task-response.json` does not exist
- `shared/config.yaml` has no `jira_key` fields
- `majordomo/system-prompt.md` contains no `jira-transition.sh` calls, no `createJiraIssue`, no `jira-epic-created` label application, no `JIRA_EPIC_KEY` variable, and no Jira REST API credential references
- The idempotency gate in Majordomo Step 3 uses `beads-ingested` (not `jira-epic-created`)
- `make test` passes

---

## Stage 3: Remove Jira from Setup Scripts, Jenkinsfiles, and Remaining Tests

### Description

Remove Jira credentials and the Atlassian MCP server registration from the setup layer, Jenkinsfiles, and test harness.

**`shared/setup-env.sh`**: Remove derivation of `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`. Remove the `JIRA_CLOUD_ID` reference. Remove the `JIRA_ACCT_PSW`/`JIRA_ACCT_USR` input variable requirements from the script header comment.

**`shared/setup-claude.sh`**: Remove the `claude mcp add atlassian` call and the `claude mcp list` call after it. Remove the docstring requirement lines for `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`.

**`shared/agent-pipeline.Jenkinsfile`**: Remove both occurrences of `usernamePassword(credentialsId: 'jira-api-key', ...)`.

**`majordomo/Jenkinsfile`**: Remove both `JIRA_ACCT = credentials('jira-api-key')` environment entries (Majordomo stage and Beads Status stage).

**`minordomo-plan/system-prompt.md`**: Remove the Environment section line `- **Jira:** write-only via REST API...`.

**`test/bats/setup-claude.bats`**: 
- Remove setup fixture lines `export JIRA_URL`, `export JIRA_EMAIL`, `export JIRA_API_TOKEN`
- Remove test "calls claude mcp add atlassian with JIRA env vars"
- Remove test "calls claude mcp list after registering the server"

**`test/bats/setup-env.bats`**: 
- Remove setup fixture lines `export JIRA_ACCT_PSW`, `export JIRA_ACCT_USR`, `export JIRA_CLOUD_ID`
- Remove test "exports JIRA_URL using JIRA_CLOUD_ID"
- Remove test "exports JIRA_EMAIL and JIRA_API_TOKEN from JIRA_ACCT credentials"

**`test/dry-run.sh`**:
- Remove the `curl` mock binary (used only to serve `jira-task-response.json` for Jira API responses)
- Remove the fake Jira credential setup: `export JIRA_ACCT_PSW`, `export JIRA_ACCT_USR`, `export JIRA_CLOUD_ID`
- Remove the `[ -n "$JIRA_URL" ]` validation check
- In the `gh` mock: remove `"issue view"` case that returned a Jira Epic comment (if `gh issue view` is still needed elsewhere in the test, replace with a comment-free response; otherwise remove the case entirely)

### Acceptance Criteria
- `shared/setup-env.sh` exports no `JIRA_URL`, `JIRA_EMAIL`, or `JIRA_API_TOKEN` variables
- `shared/setup-claude.sh` makes no `claude mcp add` calls
- Neither Jenkinsfile references `jira-api-key` credentials
- `test/bats/setup-claude.bats` has no Jira-related tests or setup
- `test/bats/setup-env.bats` has no Jira-related tests or setup
- `test/dry-run.sh` has no `JIRA_URL` validation or curl mock
- `minordomo-plan/system-prompt.md` has no Jira reference
- `make test` passes

---

## Stage 4: Update Documentation

### Description

Remove all Jira references from documentation files. Each file should describe the pipeline as beads-only for task coordination, with no references to Jira Epics, Jira transitions, or Jira credentials.

**`README.md`**:
- Remove "Jira Cloud instance with projects..." from prerequisites
- Remove `jira-api-key` row from the Jenkins credentials table
- Remove the `JIRA_CLOUD_ID` global env var instruction
- Remove "creates Jira Epics" from the pipeline step descriptions
- Remove `jira_key` from the config example and the instruction "To add a new repo: add an entry to `projects` and create the corresponding Jira project"

**`CLAUDE.md`**:
- Remove the entire "Jira Access" section (MCP tools vs REST API)
- Remove `shared/jira-transition.sh` documentation
- Remove Jira var derivation from the Agent Startup Sequence `setup-env.sh` description
- Remove `(Jira project: MDOMO)` from the "What This Repo Is" section
- Remove the reference to `docs/WORKFLOWS.md` "for Jira status flows" (update to "for branching model and task prioritization")

**`docs/WORKFLOWS.md`**:
- Remove the "Jira Ticket Hierarchy" section entirely
- Update the intro paragraph to remove Jira references
- Anywhere Epic transitions (→ "In Review", → "Done") are described, remove or replace with a note that completion is tracked in beads only

**`docs/GETTING_AROUND.md`**:
- Update the stage overview table to remove "creates Jira Epics" and "Auto-transitions Jira" entries
- Remove "(parameterized: JIRA_TASK_ID)" from Jenkinsfile comments
- Update the `shared/` directory comments to remove jira-transition.sh and get-epic-key.sh references; add get-story-key.sh

**`docs/agent-workflow-spec.md`**:
- Update the GH Issue ingestion step description to remove "creates a Jira Epic"
- Remove references to Jira Epic → Story → Task hierarchy
- Remove "Majordomo auto-transitions the Jira Epic" references
- Update the beads coordination section to remove the Jira hierarchy comparison

### Acceptance Criteria
- `grep -ri "jira" README.md CLAUDE.md docs/` returns no results (except any historical/context references in FUTURE_WORK.md, which is acceptable)
- All documentation accurately reflects the beads-only pipeline
- `make test` passes
