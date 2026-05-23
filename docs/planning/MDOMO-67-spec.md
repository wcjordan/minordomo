# MDOMO-67 Implementation Spec: Email me if a run fails

Send an email notification via Amazon SES when any of the four pipeline jobs fails or when an agent's run log reports errors.

## Background

- Delivery: Amazon SES (owner will provide credentials after receiving setup instructions)
- Recipient: `$JENKINS_USERNAME` (already an email address; exported by `setup-env.sh`)
- Trigger: Jenkins `FAILURE` state OR agent run log `"status": "failure"` / non-empty `"errors"` array
- Scope: all 4 jobs — `majordomo`, `minordomo-plan`, `minordomo-step`, `minordomo-container-builder`
- Email body: same content set as `currentBuild.description` (the Claude run log / build output)

---

## Stage 1: Add SES notification script and infrastructure

### Description

Add the boto3-based notification script, update Python dependencies, export the recipient address from `setup-env.sh`, and create a human-readable setup guide for the AWS SES configuration (IAM policy, email identity verification, Jenkins credential IDs). This stage has no Jenkinsfile changes — it ships the tool that later stages wire in.

**Files to create/modify:**

- `minordomo-container-builder/requirements.txt` — add `boto3>=1.34`
- `shared/notify-failure.py` — new script:
  - CLI: `notify-failure.py --subject SUBJECT [--body-file FILE]`
  - Reads env: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SES_REGION` (default: `us-east-1`), `NOTIFICATION_EMAIL`, `SES_SENDER_EMAIL` (defaults to `NOTIFICATION_EMAIL`)
  - If `NOTIFICATION_EMAIL` is unset or empty, prints a warning and exits 0 (so missing config is a no-op)
  - Always exits 0 — notification failures must never break a build
- `shared/setup-env.sh` — add `export NOTIFICATION_EMAIL="${JENKINS_USERNAME}"` (JENKINS_USERNAME is already a global Jenkins env var available in all sh steps)
- `docs/setup/aws-ses-setup.md` — setup instructions for the human:
  - Required IAM permission: `ses:SendEmail` on the sending identity ARN
  - How to verify the sender email address in SES; `SES_SENDER_EMAIL` defaults to `NOTIFICATION_EMAIL` (`$JENKINS_USERNAME`), so sender and recipient are the same address — one verification covers both
  - Note on SES sandbox: in sandbox mode you must verify both sender and recipient; since they're the same address, one verification suffices; request production access to remove the sandbox restriction for general use
  - Jenkins credential IDs to create: `aws-ses-access-key-id` (Secret text), `aws-ses-secret-access-key` (Secret text)
  - Recommended region: `us-east-1`

### Acceptance Criteria

- `python3 shared/notify-failure.py --help` exits 0 and shows usage
- When `NOTIFICATION_EMAIL` is unset, script exits 0 with a warning message, no exception
- When `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are set to valid SES credentials, script sends email to `$JENKINS_USERNAME` (manual integration test after credential setup)
- `pip install -r minordomo-container-builder/requirements.txt` includes boto3
- `make test` passes (shellcheck on setup-env.sh, existing bats tests)
- `docs/setup/aws-ses-setup.md` exists and covers IAM policy, email verification, sandbox note, and Jenkins credential IDs

---

## Stage 2: Add run-log error detection to agent job stage post blocks

### Description

For the three Claude-agent jobs (`majordomo`, `minordomo-plan`, `minordomo-step`), parse the run log JSON after each Claude run and mark the build as `FAILURE` if the agent reported errors. This surfaces the "exits 0 with errors" case to Jenkins so the pipeline-level `post { failure }` (added in Stage 3) fires correctly.

**Logic to add** in each agent stage's `post { always { container('...') { script { } } } }` block, immediately after the `currentBuild.description = output` line:

```groovy
// Detect agent-reported errors and surface them as a build failure
def hasErrors = sh(
    script: '''
        python3 -c "
import json, sys
try:
    lines = open('/tmp/prompt-output.txt').read().splitlines()
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
            sys.exit(1 if d.get('status') == 'failure' or d.get('errors') else 0)
        except (json.JSONDecodeError, ValueError):
            continue
    sys.exit(0)
except Exception:
    sys.exit(0)
"
    ''',
    returnStatus: true
) == 1
if (hasErrors) {
    currentBuild.result = 'FAILURE'
}
```

Notes:
- Scan lines in reverse order, parsing each as JSON, stopping at the first valid JSON object — handles cases where Claude appends a text summary after the JSON or where output contains no JSON at all
- Wrap in try/except so malformed output never causes a parse error → set `currentBuild.result`
- Setting `currentBuild.result = 'FAILURE'` in a stage's `post` block does not skip subsequent stages (the stage itself succeeded); subsequent stages still run, then the pipeline-level `post { failure }` fires

**Files to modify:** `majordomo/Jenkinsfile`, `minordomo-plan/Jenkinsfile`, `minordomo-step/Jenkinsfile`

### Acceptance Criteria

- When a planning or worker agent emits a run log with `"status": "failure"`, the Jenkins build is marked FAILURE (not SUCCESS)
- When a run log has `"status": "success"` and `"errors": []`, the build result is unchanged
- For `majordomo`, after stage 1 marks the build FAILURE, stage 2 ("Beads Status") still runs and appends its output to `currentBuild.description`
- `make test` passes (shellcheck)
- No regressions on successful builds

---

## Stage 3: Add pipeline-level SES failure notification to all 4 Jenkinsfiles

### Description

Add a pipeline-level `post { failure { ... } }` block to all four Jenkinsfiles. When the build is FAILURE (either from a hard Jenkins failure or from Stage 2's error detection), this block spins up a minordomo-image pod and sends an SES email via `shared/notify-failure.py`.

**Pattern to add** at the end of each Jenkinsfile's top-level `pipeline { }` block (inside `post { failure { script { ... } } }`):

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
                    writeFile file: 'notify-body.txt', text: body
                    container('notify') {
                        withCredentials([
                            string(credentialsId: 'aws-ses-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws-ses-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            withEnv(["NOTIFY_SUBJECT=${subject}"]) {
                                sh '''
                                    source shared/setup-env.sh
                                    python3 shared/notify-failure.py \
                                        --subject "$NOTIFY_SUBJECT" \
                                        --body-file notify-body.txt
                                '''
                            }
                        }
                    }
                }
            }
        }
    }
}
```

**Notes:**
- `GAR_HOST` is already defined at the top of each Jenkinsfile; use it directly for `GAR_REPO_NOTIFY`
- `ROOT_DOMAIN` is a Jenkins global env var, available in all `sh` steps — `source shared/setup-env.sh` derives `NOTIFICATION_EMAIL` from it
- For `minordomo-container-builder`, the 3 existing stages use non-minordomo images (dind, jenkins-helm); the notification pod uses minordomo-image without conflicting
- The `aws-ses-access-key-id` and `aws-ses-secret-access-key` credentials must be created in Jenkins before this feature is active (see `docs/setup/aws-ses-setup.md`)
- If the credentials are not yet configured in Jenkins, the `withCredentials` step will fail gracefully (build already FAILURE); consider wrapping with `catchError(buildResult: 'FAILURE', stageResult: 'FAILURE')` if credential absence should not add a second error

**Files to modify:** `majordomo/Jenkinsfile`, `minordomo-plan/Jenkinsfile`, `minordomo-step/Jenkinsfile`, `minordomo-container-builder/Jenkinsfile`

### Acceptance Criteria

- All 4 Jenkinsfiles have a pipeline-level `post { failure { ... } }` block using the podTemplate pattern
- When `aws-ses-access-key-id` and `aws-ses-secret-access-key` credentials exist in Jenkins and the build fails, an email is sent to `$JENKINS_USERNAME`
- The email subject contains the job name and build number
- The email body contains `currentBuild.description` (run log) or the build URL when description is empty
- A successful build does not trigger any notification
- `make test` passes (shellcheck)
- No regressions on existing pipeline behavior
