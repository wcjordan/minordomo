# MDOMO-79: Refactor minordomo-plan & minordomo-step with DRY & SOLID Principles

## Scope Note

The issue title names only `minordomo-plan` and `minordomo-step`, but the duplicate patterns (Beads Status stage, failure notification post block) also appear verbatim in `majordomo/Jenkinsfile`. Refactoring only plan+step would leave 2/3 of the duplication in place and make the shared abstractions pointless. This spec therefore includes `majordomo/Jenkinsfile` in all stages.

---

## Stage 1: Extract beads initialization into shared/beads-init.sh

### Description

The Beads Status stage in all three Jenkinsfiles (`minordomo-plan`, `minordomo-step`, `majordomo`) contains the same verbatim shell block:

```bash
gh auth setup-git
[ -d .beads ] && chmod 700 .beads
bd bootstrap
bd dolt show
bd dolt pull
{ bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
```

Extract this into `shared/beads-init.sh` and replace each duplicated block with `source shared/beads-init.sh`.

Also fix an existing inconsistency: `minordomo-step`'s Beads Status stage is missing the `BEADS_DOLT_PASSWORD` credential that `minordomo-plan` and `majordomo` both include. Add `BEADS_DOLT_PASSWORD = credentials('dolt-minordomo-password')` to `minordomo-step`'s Beads Status stage environment block.

Add `test/bats/beads-init.bats` covering:
- Script is sourceable and runs without error given mocked `gh` and `bd`
- Script sets/calls expected commands in order

### Acceptance Criteria
- `shared/beads-init.sh` exists and contains the beads setup sequence
- All three Jenkinsfiles' Beads Status stages source `shared/beads-init.sh` instead of repeating the inline block
- `minordomo-step` Beads Status stage now includes `BEADS_DOLT_PASSWORD` credential
- `test/bats/beads-init.bats` exists with at least 2 passing tests
- `make test` passes (shellcheck + bats + validate-prompts + dry-run)

---

## Stage 2: Extract agent run pattern into shared/run-agent.sh

### Description

Both `minordomo-plan` and `minordomo-step` main agent stages share this run pattern (differing only in the system-prompt path):

```bash
{ bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
CLAUDE_EXIT=0
claude -p "$(cat <system-prompt-file>)" --output-format json \
  > /tmp/claude-output.json || CLAUDE_EXIT=$?
bd dolt pull && bd dolt push
python3 ../shared/report-token-usage.py /tmp/claude-output.json 2>&1 | tee /tmp/prompt-output.txt || true
exit $CLAUDE_EXIT
```

Extract this into `shared/run-agent.sh` that accepts the system-prompt file path as its first argument (`$1`). The script captures the beads list, invokes claude, syncs dolt, reports token usage, and exits with claude's exit code.

Update `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile` to call `bash ../shared/run-agent.sh "../minordomo-plan/system-prompt.md"` and `bash ../shared/run-agent.sh "../minordomo-step/system-prompt.md"` respectively.

Note: `majordomo/Jenkinsfile` has a slightly different run sequence (no separate beads-list capture before claude, does git setup inline). Do not modify majordomo's main stage in this stage — only the Beads Status extraction from Stage 1 applies to majordomo.

Add `test/bats/run-agent.bats` covering:
- Script exits with the same code as the mocked `claude` binary
- Script writes `/tmp/beads-output.txt` and `/tmp/claude-output.json`
- Script calls `bd dolt pull` and `bd dolt push`

### Acceptance Criteria
- `shared/run-agent.sh` exists and accepts a system-prompt path as `$1`
- `minordomo-plan/Jenkinsfile` and `minordomo-step/Jenkinsfile` main stages call `run-agent.sh` instead of the inline block
- `test/bats/run-agent.bats` exists with at least 3 passing tests
- `make test` passes

---

## Stage 3: DRY post.always Groovy logic via shared/pipeline-lib.groovy

### Description

Both `minordomo-plan` and `minordomo-step` have an identical `post { always {} }` Groovy block in their main agent stage that:
1. Reads `/tmp/beads-output.txt` and `/tmp/prompt-output.txt`
2. Concatenates them and sets `currentBuild.description`
3. Runs `python3 shared/check-run-errors.py /tmp/prompt-output.txt` and sets `currentBuild.result = 'FAILURE'` if it returns 1

All three Jenkinsfiles also share an identical `post { always {} }` Groovy block in their Beads Status stages that reads `/tmp/beads-output.txt` and appends to `currentBuild.description`.

Create `shared/pipeline-lib.groovy` with two functions:
- `updateBuildDescription(List<String> outputFiles)` — reads each file (ignoring missing), concatenates, and sets `currentBuild.description`
- `checkRunErrors(String promptOutputFile)` — runs `check-run-errors.py` and marks build FAILURE if it returns 1

In each Jenkinsfile's `post { always { script { ... } } }` blocks, replace the inline Groovy with:
```groovy
def plib = load('shared/pipeline-lib.groovy')
plib.updateBuildDescription(['/tmp/beads-output.txt', '/tmp/prompt-output.txt'])
plib.checkRunErrors('/tmp/prompt-output.txt')
```

The Beads Status stage `post.always` uses only `updateBuildDescription` (appending behavior vs setting). Adjust `updateBuildDescription` to handle both cases with an optional `append` parameter (default `false`).

Note on mechanics: Declarative Pipeline stages with a Kubernetes agent automatically perform `checkout scm`, so the workspace contains `shared/pipeline-lib.groovy` and `load` works within `script {}` blocks in `post.always`.

### Acceptance Criteria
- `shared/pipeline-lib.groovy` exists with `updateBuildDescription` and `checkRunErrors` functions
- All three Jenkinsfiles' main stage `post.always` blocks use `plib.updateBuildDescription` + `plib.checkRunErrors`
- All three Jenkinsfiles' Beads Status `post.always` blocks use `plib.updateBuildDescription` (append mode)
- No inline Groovy duplication remains in any `post.always` block across the three files
- `make test` passes

---

## Stage 4: DRY the failure notification post block via shared/pipeline-lib.groovy

### Description

The `post { failure {} }` block is byte-for-byte identical in all three Jenkinsfiles. It:
1. Computes subject and body from `env.JOB_NAME`, `env.BUILD_NUMBER`, and `currentBuild.description`
2. Spins up a new notify pod via `podTemplate`
3. Does `checkout scm` inside the pod
4. Calls `python3 shared/notify-failure.py --subject ... --body-file ...` with SES credentials

Add a `sendFailureNotification(String garRepo, String subject, String body)` function to `shared/pipeline-lib.groovy`. The function creates the notify pod, does checkout, writes the body file, and calls `notify-failure.py`.

Replace each Jenkinsfile's `post { failure { script { ... } } }` with:
```groovy
post {
    failure {
        script {
            def GAR_REPO_NOTIFY = "${GAR_HOST}/${env.GCP_PROJECT}/default-gar"
            def subject = "${env.JOB_NAME} FAILED (Build #${env.BUILD_NUMBER})"
            def body = currentBuild.description ?: "Build failed.\nURL: ${env.BUILD_URL}"
            podTemplate(yaml: """
                apiVersion: v1
                kind: Pod
                spec:
                  containers:
                  - name: notify
                    image: ${GAR_REPO_NOTIFY}/minordomo-image:latest
                    command: [cat]
                    tty: true
                    resources:
                      requests:
                        cpu: "100m"
                        memory: "256Mi"
                      limits:
                        cpu: "200m"
                        memory: "512Mi"
            """) {
                node(POD_LABEL) {
                    checkout scm
                    def plib = load('shared/pipeline-lib.groovy')
                    plib.sendFailureNotification(subject, body)
                }
            }
        }
    }
}
```

Note: The `podTemplate` YAML stays inline in the Jenkinsfile because `readFile` is unavailable at pipeline-level post blocks (no workspace until the pod starts). The `load` happens after `checkout scm` inside the pod, where the workspace exists.

The `sendFailureNotification` function encapsulates: `writeFile`, `container('notify')`, `withCredentials`, `withEnv`, and the `sh` block for `notify-failure.py`.

### Acceptance Criteria
- `shared/pipeline-lib.groovy` has `sendFailureNotification(subject, body)` function
- All three Jenkinsfiles' `post { failure {} }` blocks call `plib.sendFailureNotification` after `checkout scm` + `load`
- No duplicated `writeFile` / `withCredentials` / SES invocation Groovy remains across the three files
- The pod YAML template remains in each Jenkinsfile (necessary — no workspace at pipeline post level)
- `make test` passes
