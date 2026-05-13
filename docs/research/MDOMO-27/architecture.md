# Research: MDOMO-27 — Show Prompt Output on Jenkins Job Description

## Goal

Update the Jenkins run description to contain the output from the `claude -p` invocation
for the three agent jobs: majordomo, plan (minordomo-plan), and step (minordomo-step).

## Current Structure

### Three Jenkinsfiles

Each job runs `claude -p "$(cat <system-prompt.md>)"` inside a shell step within a
Kubernetes container. All environment setup uses `source` to export variables in the
same shell process, so setup and the `claude` call must stay in the same `sh` block.

- `majordomo/Jenkinsfile` — orchestrator job, disableConcurrentBuilds
- `minordomo-plan/Jenkinsfile` — planning agent, parameterized (JIRA_TASK_ID)
- `minordomo-step/Jenkinsfile` — worker agent, parameterized (JIRA_TASK_ID)

### Claude Output

Each agent emits a single JSON run log to stdout at the end of its run. This is the
"prompt output" that the feature wants to surface. Example shape (majordomo):

```json
{
  "run_id": "jenkins-majordomo-main-42",
  "timestamp": "2026-05-11T00:00:00Z",
  "status": "success",
  "steps": [...],
  "errors": []
}
```

## Implementation Approach

### Capturing Output

Since `source` exports env vars only within the same shell process, all setup and the
`claude` invocation must remain in a single `sh` block. The cleanest capture mechanism
is `tee`:

```sh
claude -p "$(cat system-prompt.md)" | tee /tmp/prompt-output.txt
```

With `set -o pipefail` (already set in all Jenkinsfiles), this preserves `claude`'s
exit code: if `claude` exits non-zero, the pipe exits non-zero and the build fails.

### Setting the Description

Jenkins declarative pipelines support a `post { always { script { ... } } }` block at
the stage level. This runs after the stage completes, regardless of success or failure.
Within the `script` block, `currentBuild.description` can be set.

To read `/tmp/prompt-output.txt` (written by the shell step in the same K8s container),
use `sh(returnStdout: true, ...)` within the `script` block. The file lives in the
container's ephemeral filesystem and is accessible across steps within the same stage.

Pattern (from Stage 1 implementation in majordomo/Jenkinsfile):
```groovy
post {
    always {
        container('worker') {
            script {
                def output = sh(
                    script: 'cat /tmp/prompt-output.txt 2>/dev/null || true',
                    returnStdout: true
                ).trim()
                if (output) {
                    currentBuild.description = output
                }
            }
        }
    }
}
```

`|| true` prevents the `sh` step from failing if the file doesn't exist (e.g., if
`claude` crashed before producing any output).

Note: the `container('worker')` wrapper is required for plan and step Jenkinsfiles
because the agent uses `agent none` at the pipeline level; the container context must
be re-specified in the `post` block. In majordomo, the container is named `majordomo`.

## Stage Completion Status

- **Stage 1 (majordomo/Jenkinsfile):** Complete. Merged via PR #48 (commit 977116d).
- **Stage 2 (minordomo-plan/Jenkinsfile, minordomo-step/Jenkinsfile):** Spec confirmed,
  ready for worker implementation.

## Test Impact

The existing test suite (`make test`) runs:
- shellcheck on `shared/*.sh` — Jenkinsfiles are Groovy, not checked
- validate-prompts.py — checks system-prompt.md files only
- dry-run.sh — tests shared shell scripts, not Jenkinsfiles
- bats unit tests — test shared scripts

No existing tests cover Jenkinsfiles, so the changes will not break the test suite.
New tests for Jenkinsfile content would require a Groovy/JenkinsUnit test framework
not currently present; no new test infrastructure is needed for this feature.
