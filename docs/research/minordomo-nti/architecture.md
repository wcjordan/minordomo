# Research: Remove Remaining Jira Integration (minordomo-nti)

## Scope Summary

All Jira integration remaining in the codebase is at the Epic level. The issue (#216) lists the
full set of items to remove. This doc maps each item to the exact files/lines affected.

---

## Files to Delete

- `shared/jira-transition.sh` — transitions a Jira issue to a named status; only used for Epics
- `shared/get-epic-key.sh` — parses `"Jira Epic:"` from GH comments; called by Majordomo Steps 4, 9, 10 and by Worker "Needs Input Flow"
- `test/bats/get-epic-key.bats` — all tests for get-epic-key.sh
- `test/bats/jira-transition.bats` — all tests for jira-transition.sh
- `test/fixtures/jira-task-response.json` — orphaned fixture used only by `test/dry-run.sh` curl mock

---

## Files to Modify

### `majordomo/system-prompt.md`

**Step 3** — remove the entire Jira Epic creation block:
  - Sub-step 4: skip issues with `jira-epic-created` label (idempotency gate on Jira)
  - Sub-step 5a: `mcp__atlassian__createJiraIssue` call
  - Sub-step 5b: post `"Jira Epic: <KEY>"` comment
  - Sub-step 5c: apply `jira-epic-created` label
  - Step 3 `config` validation now only needs `repo` (not `jira_key`)
  - Run log: remove `jira_key` from projects list

**Step 4** — `shared/get-epic-key.sh` call:
  - Remove `JIRA_EPIC_KEY` output (3rd line) and all `jira_epic_key` usage
  - The script still needs to derive `EPIC_KEY` (Story bead ID) and `GH_ISSUE_NUMBER` — this logic
    should be inlined (or moved to a new `shared/get-story-key.sh` helper) since get-epic-key.sh is deleted

**Step 6 (PR sync, sub-step n)** — remove `shared/jira-transition.sh "${JIRA_EPIC_KEY}" "In Review"` call

**Step 9 (Close Completed Epics, sub-step f and i)** — remove `JIRA_EPIC_KEY` derivation and `shared/jira-transition.sh "${EPIC_KEY}" "Done"` call

**Step 1 (Load Config validation)** — remove `jira_key` from required fields per project entry

**Run log** — remove `jira_key` from projects list in config section

### `minordomo-step/system-prompt.md`

**Needs Input Flow Step 1** — remove `_JIRA_EPIC_KEY` variable extraction from `shared/get-epic-key.sh`; the script only needs `GH_ISSUE_NUMBER`. Since get-epic-key.sh is deleted, need a replacement approach.

### `shared/get-epic-key.sh` → replacement helper

The Jira Epic lookup logic should be removed, but the underlying beads traversal (Task → Story bead → GH Issue URL → GH Issue Number) is still needed by:
- Majordomo Step 4 helper
- Majordomo Step 9 (get GH_ISSUE_NUMBER for epic PR derivation)
- Majordomo Step 10 (get EPIC_KEY and GH_ISSUE_NUMBER)
- Worker Needs Input Flow

**Recommended**: Create `shared/get-story-key.sh` that:
  - Outputs Story bead ID on line 1
  - Outputs GH_ISSUE_NUMBER on line 2
  - Does NOT output Jira Epic key (removed)

Callers that captured 3 lines now capture 2 lines. Update all callers accordingly.

### `shared/config.yaml`

Remove `jira_key` field from each project entry:
```yaml
projects:
  - repo: minordomo
  - repo: chalk
  - repo: gcp-setup
  - repo: forester
```

### `shared/setup-env.sh`

Remove derivation of:
- `JIRA_URL`
- `JIRA_EMAIL`
- `JIRA_API_TOKEN`

Also remove the `JIRA_CLOUD_ID` reference. Keep `GH_TOKEN`, `GH_APP_PSW`, `JENKINS_USERNAME`, `BASE_BRANCH`, `DOMAIN_ROOT`.

### `shared/setup-claude.sh`

Remove the `claude mcp add atlassian` call (and the `claude mcp list` call after it). The JIRA env vars it passed are also being removed from setup-env.sh. Remove the docstring references to JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN requirements.

### `shared/agent-pipeline.Jenkinsfile`

Remove:
- `usernamePassword(credentialsId: 'jira-api-key', ...)` from main stage withCredentials block
- `usernamePassword(credentialsId: 'jira-api-key', ...)` from Beads Status stage withCredentials block

### `majordomo/Jenkinsfile`

Remove:
- `JIRA_ACCT = credentials('jira-api-key')` from Majordomo stage environment block
- `JIRA_ACCT = credentials('jira-api-key')` from Beads Status stage environment block

### `test/dry-run.sh`

Remove:
- `export JIRA_ACCT_PSW`, `JIRA_ACCT_USR`, `JIRA_CLOUD_ID` fake credential setup
- `[ -n "$JIRA_URL" ]` validation check
- The `curl` mock (which serves `jira-task-response.json`) — only needed for Jira calls
- The `"issue view"` mock in `gh` mock that returns a Jira Epic comment — may need to be retained for other uses but the Jira Epic part can be stripped

### `test/bats/setup-claude.bats`

Remove tests:
- "calls claude mcp add atlassian with JIRA env vars"
- "calls claude mcp list after registering the server"

Remove setup fixtures:
- `export JIRA_URL`, `export JIRA_EMAIL`, `export JIRA_API_TOKEN`

### `test/bats/setup-env.bats`

Remove tests:
- "exports JIRA_URL using JIRA_CLOUD_ID"
- "exports JIRA_EMAIL and JIRA_API_TOKEN from JIRA_ACCT credentials"

Remove setup:
- `export JIRA_ACCT_PSW`, `export JIRA_ACCT_USR`, `export JIRA_CLOUD_ID`

### `minordomo-plan/system-prompt.md`

Line 14: remove `- **Jira:** write-only via REST API...` from Environment section.

### Documentation Files

- `README.md`: Remove Jira prereqs, credential table entries, pipeline step references, config example jira_key
- `CLAUDE.md`: Remove Jira Access section, jira-transition.sh docs, jira_key from Task Identity section, setup-env.sh Jira var derivation note
- `docs/WORKFLOWS.md`: Remove Jira Ticket Hierarchy section, update descriptions
- `docs/GETTING_AROUND.md`: Remove Jira references from stage overview table and file comments
- `docs/agent-workflow-spec.md`: Update pipeline description to remove Jira Epic creation and transitions

---

## Labels to Clean Up

The `jira-epic-created` label on GH issues: the issue says to "stop applying it going forward" (don't strip from existing issues). This means:
- Remove Step 3 sub-step 5c (apply label) from Majordomo
- Remove Step 3 sub-step 4 (skip if labeled) — since we no longer apply it, there's no idempotency concern for Jira. But we still need idempotency for beads task creation! Check: beads ingestion uses `beads-ingested` label already.

Looking at Step 3: issues are skipped if `jira-epic-created` but NOT if `beads-ingested`. After removal of Jira, the `beads-ingested` label becomes the sole idempotency gate. This needs to be reflected in the updated Step 3.

---

## Key Design Decision: get-story-key.sh vs inlining

**Option A**: Create `shared/get-story-key.sh` as a 2-output replacement for get-epic-key.sh
- Pro: Matches existing pattern, easy to test, clean callers
- Con: New file introduced

**Option B**: Inline the story traversal in each caller
- Pro: No new file
- Con: Repetition in 4+ places

**Recommendation**: Option A (get-story-key.sh). The traversal logic is used in 4+ places and has its own bats test suite worth preserving. Rename the test file to `get-story-key.bats` and update the test cases to remove Jira Epic output assertions.

---

## Stage Split Rationale

The work can be split into 3 stages of roughly equal size:

**Stage 1** (~30 min): Replace get-epic-key.sh with get-story-key.sh (new helper + updated callers + test rename)
- This is the foundational change that unblocks stages 2 and 3

**Stage 2** (~45 min): Remove Jira from scripts and system prompts
- setup-env.sh, setup-claude.sh, Jenkinsfiles, majordomo system-prompt, minordomo-step system-prompt, minordomo-plan system-prompt, config.yaml
- Remove jira-transition.sh, dry-run.sh cleanup, bats test cleanup (setup-claude, setup-env)

**Stage 3** (~30 min): Update documentation
- README.md, CLAUDE.md, docs/WORKFLOWS.md, docs/GETTING_AROUND.md, docs/agent-workflow-spec.md
