# MDOMO-67 Research: Email me if a run fails

## Context

GitHub Issue #90 body is empty — title only: "Email me if a run fails".
Jira Epic MDOMO-67 description contains only the GitHub Issue URL.
No prior requirements or design notes exist.

## Answers from owner (GH Issue #90 comments, 2026-05-23)

1. **Email delivery**: Use Amazon SES. Owner will provide API credentials once given setup instructions.
2. **Recipient address**: Derive from domain — `${DOMAIN_ROOT}@gmail.com` (same convention as JENKINS_USERNAME).
3. **Which jobs**: All 4 jobs — `majordomo`, `minordomo-plan`, `minordomo-step`, `minordomo-container-builder`.
4. **Failure threshold**: Email on errors as well as hard failures. Email body = same output as build description.

## Jenkins Jobs ("runs") in scope

Four pipeline jobs will receive notifications:

| Job | Jenkinsfile | Trigger | Container |
|---|---|---|---|
| `majordomo` | `majordomo/Jenkinsfile` | Manual/cron | minordomo-image |
| `minordomo-plan` | `minordomo-plan/Jenkinsfile` | Triggered by Majordomo | minordomo-image |
| `minordomo-step` | `minordomo-step/Jenkinsfile` | Triggered by Majordomo | minordomo-image |
| `minordomo-container-builder` | `minordomo-container-builder/Jenkinsfile` | Weekly cron | docker:27-dind / jenkins-helm |

Note: `majordomo` has TWO stages — "Majordomo" (runs Claude) and "Beads Status" (runs bd). The "Beads Status" stage is skipped on hard failure of stage 1.

## Failure modes

1. **Jenkins FAILURE status** — `claude -p` exits non-zero (unrecoverable errors, timeout, container crash). All Jenkinsfiles use `set -euo pipefail`, so any non-zero exit propagates.
2. **Agent run log `"status": "failure"`** — agent emits JSON run log to stdout; exits 0 even when `"status": "failure"` or `"errors": [...]` is non-empty. Jenkins shows SUCCESS in this case.

Both modes must trigger notification.

## Current build description mechanism

All 3 agent Jenkinsfiles capture Claude output via `tee /tmp/prompt-output.txt` and in `post { always }` set `currentBuild.description = output`. The `majordomo` Jenkinsfile also appends beads status in stage 2's post block.

## Implementation design

### Notification infrastructure (Stage 1)
- `shared/notify-failure.py` — boto3 SES email sender
  - CLI: `--subject SUBJECT [--body-file FILE]`
  - Env: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SES_REGION` (default: us-east-1), `NOTIFICATION_EMAIL`, `SES_SENDER_EMAIL` (defaults to `NOTIFICATION_EMAIL`)
  - Always exits 0 (notification failures must not break builds)
  - Skip silently if `NOTIFICATION_EMAIL` not set
- `requirements.txt`: add `boto3>=1.34`
- `setup-env.sh`: export `NOTIFICATION_EMAIL="${DOMAIN_ROOT}@gmail.com"`
- `docs/setup/aws-ses-setup.md`: human-facing setup instructions

### Error detection (Stage 2)
- In each agent job's stage `post { always }` block, after setting description:
  - Parse `/tmp/prompt-output.txt` as JSON using `python3 -c`
  - If `status == "failure"` or `errors` list is non-empty, set `currentBuild.result = 'FAILURE'`
  - This causes the pipeline-level `post { failure }` (Stage 3) to fire

### Pipeline-level notification (Stage 3)
- Add `post { failure { script { podTemplate { node(POD_LABEL) { ... } } } } }` at pipeline level for all 4 jobs
- Spins up a minordomo-image pod (also works for container-builder which uses other images)
- Body: `currentBuild.description ?: "Build failed.\nURL: ${env.BUILD_URL}"`
- Body written via `writeFile` to workspace (after `checkout scm`), passed as `--body-file`
- Credentials: `aws-ses-access-key-id`, `aws-ses-secret-access-key` Jenkins credentials

### SES sender/recipient
- Both sender and recipient are `${DOMAIN_ROOT}@gmail.com`
- In SES sandbox: this email must be verified as a SES identity
- The same verification covers both sender and recipient since they're the same address

## Jenkins credential IDs to create

| Jenkins Credential ID | Type | Description |
|---|---|---|
| `aws-ses-access-key-id` | Secret text | AWS IAM Access Key ID |
| `aws-ses-secret-access-key` | Secret text | AWS IAM Secret Access Key |

`ROOT_DOMAIN` is already a Jenkins global env var.
`AWS_SES_REGION` can be a global env var or default to `us-east-1` in the script.
