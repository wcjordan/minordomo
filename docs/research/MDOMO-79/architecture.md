# MDOMO-79 Research: Architecture & DRY/SOLID Analysis

## Codebase Structure

- `minordomo-plan/` — Planning Agent Jenkinsfile + system-prompt.md
- `minordomo-step/` — Worker Agent Jenkinsfile + system-prompt.md
- `majordomo/` — Majordomo Jenkinsfile + system-prompt.md
- `shared/` — Shell scripts sourced by all three pipelines
- `test/bats/` — bats unit tests for shared/*.sh scripts
- `test/validate-prompts.py` — validates static paths + Jenkins job names in prompts
- `test/dry-run.sh` — smoke-tests setup-env.sh → setup-claude.sh → setup-workspace.sh chain
- `test/shellcheck.sh` — runs shellcheck on shared/*.sh

## Duplication Identified

### 1. Beads Status Stage (3× duplicated)
All three Jenkinsfiles (plan, step, majordomo) have an identical "Beads Status" stage. The shell steps are verbatim the same:
```bash
gh auth setup-git
[ -d .beads ] && chmod 700 .beads
bd bootstrap
bd dolt show
bd dolt pull
{ bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
```
The `post.always` Groovy logic for updating `currentBuild.description` is also identical.

**Env var discrepancy:** `minordomo-step` Beads Status stage is missing `BEADS_DOLT_PASSWORD` (present in plan + majordomo). This is likely a bug — `bd dolt pull` presumably needs it to authenticate.

### 2. Failure Notification Post Block (3× duplicated)
The entire `post { failure {} }` block is byte-for-byte identical across all three Jenkinsfiles. It spins up a new notify pod, checkouts SCM, and runs `python3 shared/notify-failure.py`.

### 3. Agent Run Pattern (2× duplicated: plan + step)
Both plan and step have the same pattern after workspace setup:
```bash
{ bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
CLAUDE_EXIT=0
claude -p "$(cat <system-prompt-file>)" --output-format json > /tmp/claude-output.json || CLAUDE_EXIT=$?
bd dolt pull && bd dolt push
python3 ../shared/report-token-usage.py /tmp/claude-output.json 2>&1 | tee /tmp/prompt-output.txt || true
exit $CLAUDE_EXIT
```
Only difference: the path to the system-prompt file.

### 4. Post.always Agent Stage Logic (2× duplicated: plan + step)
Both plan and step have identical `post { always {} }` Groovy for reading `/tmp/beads-output.txt` + `/tmp/prompt-output.txt`, updating `currentBuild.description`, and running `check-run-errors.py`.

## Scope Decision

The issue title names only "minordomo-plan & minordomo-step" but the worst duplication involves `majordomo/Jenkinsfile` too. Refactoring only plan+step would leave 2/3 of the duplication in place, defeating the purpose. The shared abstractions (beads-init.sh, run-agent.sh, pipeline-lib.groovy) are worthless unless all three consumers use them. Therefore the implementation WILL include majordomo even though the title doesn't name it.

## Refactoring Approach

### Shell Scripts (safe, testable)
- `shared/beads-init.sh` — beads bootstrap + list sequence for Beads Status stage
- `shared/run-agent.sh <prompt-file>` — claude invocation + dolt sync + token reporting

### Groovy Shared File (higher risk — no Jenkins test loop)
- `shared/pipeline-lib.groovy` — Groovy functions callable via `load()`:
  - `updateBuildDescription(outputFiles)` — updates currentBuild.description
  - `checkRunErrors(promptFile)` — fails build if errors detected
  - `sendFailureNotification(garRepo, subject, body)` — runs the notify pod

### Jenkins Mechanics
- In stage `post.always` blocks: `load` works because Kubernetes agents auto-checkout SCM (workspace has the file)
- In pipeline-level `post.failure` block: the existing code does `checkout scm` inside the pod; we can `load` after that checkout
- `podTemplate` inside a Groovy function called within `node()` is valid Jenkins Scripted Pipeline

## Test Coverage Plan
- `shared/beads-init.sh` → add `test/bats/beads-init.bats`
- `shared/run-agent.sh` → add `test/bats/run-agent.bats`
- `test/shellcheck.sh` covers all new `shared/*.sh` automatically (glob: `shared/*.sh`)
- Groovy helpers have no unit test path without Jenkins — risk acknowledged, mitigated by keeping functions minimal
