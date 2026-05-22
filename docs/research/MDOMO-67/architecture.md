# MDOMO-67 Research: Email me if a run fails

## Context

GitHub Issue #90 body is empty — title only: "Email me if a run fails".
Jira Epic MDOMO-67 description contains only the GitHub Issue URL.
No prior requirements or design notes exist.

## Jenkins Jobs ("runs") in scope

Three pipeline jobs send agents to do work:

| Job | Jenkinsfile | Trigger |
|---|---|---|
| `majordomo` | `majordomo/Jenkinsfile` | Manual/cron |
| `minordomo-plan` | `minordomo-plan/Jenkinsfile` | Triggered by Majordomo |
| `minordomo-step` | `minordomo-step/Jenkinsfile` | Triggered by Majordomo |

A fourth job (`minordomo-container-builder`) builds the Docker image on a weekly cron — it is unclear whether this counts as "a run" for notification purposes.

## Failure modes

1. **Jenkins FAILURE status** — `claude -p` exits non-zero (unrecoverable errors, timeout, container crash). This is the canonical "build failed" state visible in Jenkins UI.
2. **Agent run log `"status": "failure"`** — the Claude agent exits non-zero when a fatal error occurs. Since all Jenkinsfiles use `set -euo pipefail`, any non-zero exit propagates to Jenkins FAILURE. However, partial failures (per-issue errors, per-task errors) are logged in the run log `errors` array but still exit 0 — Jenkins would show SUCCESS in this case.

## Existing email infrastructure

No email-sending code or credentials exist in the repo. The only email-related patterns are:

- `JIRA_EMAIL` — used for Jira API basic auth (not a sending address)
- `JENKINS_USERNAME` — derived as `${DOMAIN_ROOT}@gmail.com` (e.g., `flipperkid@gmail.com` if ROOT_DOMAIN is `flipperkid.com`)
- No SMTP credential, no mail plugin configuration, no emailext usage anywhere

## Design questions (see Jira/GH comments)

### 1. Email delivery mechanism
Options:
- **Jenkins built-in `mail()` step** — runs on Jenkins controller node, requires SMTP configured globally in Jenkins global settings (outside this repo). Zero new code in the container.
- **Jenkins `emailext` plugin** — more configurable, also requires Jenkins SMTP.
- **Container-side Python smtplib** — requires adding a new SMTP credential to Jenkins + code in the container's post block.
- **External service** (SendGrid, Gmail API) — requires a new credential + more complex code.

### 2. Recipient email address
Options:
- New `notification_email` field in `shared/config.yaml`
- New Jenkins global env var (like `JIRA_CLOUD_ID`)
- Derive from existing `JENKINS_USERNAME` / `ROOT_DOMAIN` convention (`${DOMAIN_ROOT}@gmail.com`)

### 3. Which jobs count as "a run"
- Just `majordomo`, `minordomo-plan`, `minordomo-step`?
- Also `minordomo-container-builder`?

### 4. Failure threshold / content
- Only Jenkins `FAILURE` state, or also when agent's run log has errors but exits 0?
- Content: minimal subject + build URL, or include the run log excerpt (available in `currentBuild.description`)?
- Rate limiting: if Majordomo runs hourly and fails repeatedly, suppress duplicates?

## Implementation sketch (pending answers)

If Jenkins `mail()` + `NOTIFICATION_EMAIL` env var:
- Add `NOTIFICATION_EMAIL` global Jenkins env var (documented in README)
- Add `post { failure { mail(to: env.NOTIFICATION_EMAIL, ...) } }` at pipeline level in each Jenkinsfile
- ~10 lines per Jenkinsfile, no container or image changes needed

If container-side sender:
- Add SMTP credential to Jenkins + helm secrets
- Add Python email helper script
- Add to `requirements.txt` if needed
- More involved (~2-3 stages)
