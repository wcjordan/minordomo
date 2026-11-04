# Research: Update all interactions w/ Jenkins to use https

## Summary

The issue asks to update all HTTP URLs for Jenkins interactions to use HTTPS instead.

## Locations to Change

### 1. `shared/jenkins-trigger.sh` (line 17)
```
url="http://jenkins.${ROOT_DOMAIN}/job/${job_name}/job/${BASE_BRANCH}/buildWithParameters?BEADS_TASK_ID=${beads_task_id}"
```
This is the primary functional change — the curl POST that triggers Jenkins jobs.

### 2. `majordomo/system-prompt.md` (line 11)
```
- **Jenkins URL:** `http://jenkins.${ROOT_DOMAIN}/`.  Authenticate w/ the `JENKINS_USERNAME` and `JENKINS_API_KEY` env vars
```
This is documentation in the Majordomo agent's system prompt — it references the base Jenkins URL.

## Tests

The `test/bats/jenkins-trigger.bats` tests mock `curl` entirely. No test asserts the URL scheme (http vs https), so no test changes are needed for correctness. However, it would be good to add a test that verifies the URL passed to curl uses `https://`.

## No Other Jenkins HTTP References

The other scripts (`shared/setup-env.sh`, `shared/setup-workspace.sh`, `test/dry-run.sh`) reference `ROOT_DOMAIN` for other purposes but don't construct Jenkins URLs.

The Jenkinsfiles themselves contain no hardcoded Jenkins URLs.

## Scope: 2 files, minimal change

- `shared/jenkins-trigger.sh`: change `http://` to `https://` on line 17
- `majordomo/system-prompt.md`: change `http://` to `https://` on line 11
- Optionally add a bats test asserting the URL scheme is `https://`
