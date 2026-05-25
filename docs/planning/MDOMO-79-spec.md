# Plan: DRY / SOLID Cleanup of Pipeline Infrastructure

Reduces duplication and maintenance surface across `majordomo`, `minordomo-container-builder`,
`minordomo-plan`, `minordomo-step`, and `shared`. Four stages, each leaving all pipelines in a
working state and openable as an independent PR.

---

## Stage 1: Add `shared/bootstrap.sh`

### Description

Both `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile` source the same three setup
scripts in the same order:

```bash
source shared/setup-env.sh
source shared/setup-claude.sh
source shared/setup-workspace.sh <mode>
```

Create `shared/bootstrap.sh` that accepts a mode argument (`planning` or `worker`) and runs this
sequence. Update both Jenkinsfiles to replace the three source lines with a single call:

```bash
source shared/bootstrap.sh planning   # or worker
```

No logic changes — pure refactor. If a future setup step is added it goes in one file.

### Acceptance Criteria

- `shared/bootstrap.sh planning` sources all three scripts in order, passing `planning` to
  `setup-workspace.sh`
- `shared/bootstrap.sh worker` sources all three scripts in order, passing `worker` to
  `setup-workspace.sh`
- `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile` each have one `source
  shared/bootstrap.sh` call where the three individual source lines were
- A test run of each pipeline produces identical behavior to before

---

## Stage 2: Add `shared/pipeline-helpers.sh` and update system prompts

### Description

Three bash patterns are copy-pasted across steps in `majordomo/system-prompt.md` and the agent
system prompts. Extract them into named functions in a new `shared/pipeline-helpers.sh`:

- **`beads_task_id_by_title <title>`** — replaces 6+ inline `bd list --json | jq -r --arg t "$TITLE"
  '[.[] | select(.title == $t)] | first | .id // empty'` calls; must also search
  `--status=in_progress` so claimed tasks are found (see CLAUDE.md `bd list` note)
- **`has_needs_input <repo> <issue_number>`** — replaces 3 identical
  `gh issue view | jq '.labels[].name' | grep -q needs-input` chains; returns exit code 0 if label
  present, 1 if not
- **`extract_priority <labels_json>`** — replaces 3 P0–P4 label-extraction loops; prints matched
  label or `P2` as default; accepts the JSON array from `gh issue view --json labels`

Update all three system-prompt files to instruct agents to `source shared/pipeline-helpers.sh`
early in their run and call these functions by name.

Add bats tests in `test/bats/pipeline-helpers.bats` covering: title-not-found, title-found-open,
title-found-in-progress, needs-input-present, needs-input-absent, priority-matched, priority-default.

### Acceptance Criteria

- `shared/pipeline-helpers.sh` defines the three functions and is sourceable without side effects
- Each function is covered by at least two bats test cases
- `make test` passes
- All three system-prompt files reference `source shared/pipeline-helpers.sh` and use the function
  names instead of the inlined one-liners

---

## Stage 3: Merge `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile`

### Description

The two agent Jenkinsfiles are ~95% identical. The only runtime differences are:
- Stage name ("Planning Agent" vs "Worker")
- System prompt path (`minordomo-plan/system-prompt.md` vs `minordomo-step/system-prompt.md`)

Create `shared/agent-pipeline.Jenkinsfile` that contains the full pipeline and resolves both values
from an `AGENT_MODE` parameter (`planning` or `worker`). Replace each agent's Jenkinsfile with a
minimal wrapper:

```groovy
// minordomo-plan/Jenkinsfile
AGENT_MODE = 'planning'
load 'shared/agent-pipeline.Jenkinsfile'
```

The shared pipeline calls `shared/bootstrap.sh` (Stage 1) rather than sourcing the three setup
scripts individually. The Beads Status stage and token-reporting logic live once, in the shared file.

### Acceptance Criteria

- `shared/agent-pipeline.Jenkinsfile` contains the full agent and beads-status pipeline logic
- `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile` are each ≤ 5 lines
- A test build of each pipeline (planning and worker mode) succeeds end-to-end
- No change in stage names, timeout values, resource requests, or beads sync behavior

---

## Stage 4: Extract failure notification and unify safety deny rules

### Description

Two independent cleanup items in one PR.

**4a — Failure notification shared library**

The `post { failure { ... } }` block — spin up a notification pod, checkout, run `notify-failure.py`
— appears verbatim in all four Jenkinsfiles (`majordomo`, `minordomo-container-builder`,
`minordomo-plan`, `minordomo-step`). Move it into a Jenkins shared library function
`vars/notifyFailure.groovy`. Each Jenkinsfile's post block becomes:

```groovy
post {
    failure { notifyFailure() }
}
```

The shared library function reads `GAR_HOST`, `GCP_PROJECT`, and `NOTIFICATION_EMAIL` from the
environment (already set by `setup-env.sh` or the enclosing pipeline).

**4b — Safety rules single source of truth**

`shared/agent-settings.json` deny list and `shared/pre-bash-guard.sh` enforce overlapping rules in
two different formats. Extract the shared entries to `shared/safety-rules.yaml`:

```yaml
rules:
  - description: force push not allowed
    deny_glob: "git push --force*"
    bash_pattern: 'git[[:space:]]+push[[:space:]].*--force'
  - description: sudo not allowed
    deny_glob: "sudo *"
    bash_pattern: '(^|[;&|[:space:]])sudo[[:space:]]'
  # ...
```

Add `shared/generate-safety-rules.sh` that reads `safety-rules.yaml` and writes the deny-list
entries into the `deny` array in `agent-settings.json` and the regex blocks into the generated
section of `pre-bash-guard.sh`. Patterns exclusive to the shell guard (shell-injection
defense-in-depth patterns not expressible as deny-glob entries) stay hardcoded in `pre-bash-guard.sh`
below a `# --- hardcoded guard-only rules below ---` marker and are not touched by the generator.

Run the generator and commit its output alongside `safety-rules.yaml`. Add a `make check-safety`
target that re-runs the generator and fails if the output differs from what is committed (catches
out-of-sync edits in CI).

### Acceptance Criteria

- `vars/notifyFailure.groovy` exists and is registered as a shared library in the Jenkins instance
- All four Jenkinsfiles use `notifyFailure()` in their `post { failure }` block; the inline pod
  template is removed from each
- A test failure in any pipeline triggers the notification correctly
- `shared/safety-rules.yaml` exists and covers all rules that appear in both `agent-settings.json`
  and `pre-bash-guard.sh`
- `shared/generate-safety-rules.sh` produces the currently-committed deny list and guard section
  when run from scratch
- `make check-safety` passes (generated output matches committed output)
- `make test` passes (shellcheck, bats)
