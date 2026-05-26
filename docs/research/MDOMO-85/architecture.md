# MDOMO-85 Research: Extract Jira Transition Logic

## Problem

The two-step Jira transition dance (GET transitions list → find by `to.name` → POST) appears inline in three files, five call sites total:

| File | Call site | Target status |
|------|-----------|---------------|
| `minordomo-plan/system-prompt.md` | Spec Path Step 5 | `In Review` |
| `minordomo-step/system-prompt.md` | Step 7 | `In Review` |
| `majordomo/system-prompt.md` | Step 4 (Stage tasks) | `Done` |
| `majordomo/system-prompt.md` | Step 4 (Plan tasks) | `Approved` |
| `majordomo/system-prompt.md` | Step 8 | `In Progress` |
| `majordomo/system-prompt.md` | Step 9 | `In Review` |

Each copy is ~15 lines of curl+Python.

## Proposed Script: `shared/jira-transition.sh`

Interface:
```bash
shared/jira-transition.sh <issue_key> <status_name>
```

Reads from env: `JIRA_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`

Behavior:
- GET `${JIRA_URL}/rest/api/3/issue/<issue_key>/transitions`
- Find entry where `to.name == <status_name>`
- POST `{"transition": {"id": "<id>"}}`
- Exit non-zero if status name not found or HTTP failures

## Conventions from Existing Code

Existing shared scripts (`pipeline-helpers.sh`, `pre-bash-guard.sh`) use:
- `#!/usr/bin/env bash` shebang
- `set -euo pipefail`
- Inline Python3 for JSON parsing (no `jq` dependency)
- Self-contained: no sourcing required

## Bats Test Pattern

Tests in `test/bats/` mock external CLI tools (bd, gh) via `$TMP_DIR` on `$PATH`.
For `jira-transition.sh`, mock `curl` similarly.

## Call Site Replacement

Each inline block like:
```bash
TRANSITIONS=$(curl -s -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  "${JIRA_URL}/rest/api/3/issue/${issue_key}/transitions")
TRANSITION_ID=$(echo "$TRANSITIONS" | python3 -c "...")
curl -s -X POST -u "${JIRA_EMAIL}:${JIRA_API_TOKEN}" \
  -H "Content-Type: application/json" \
  "${JIRA_URL}/rest/api/3/issue/${issue_key}/transitions" \
  -d "{\"transition\": {\"id\": \"${TRANSITION_ID}\"}}"
```

Becomes:
```bash
shared/jira-transition.sh "${issue_key}" "StatusName"
```

## Notes on System Prompt Call Sites

The system prompts contain bash code blocks that agents are instructed to run.
The replacement just needs to swap the multi-line block with the one-liner.
In majordomo Step 4, the transition call appears in prose (not a code block) — update as inline instructions.
