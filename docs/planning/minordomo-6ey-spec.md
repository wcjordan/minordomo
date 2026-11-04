# Plan: Update all interactions w/ Jenkins to use https

## Overview

There are exactly two places in the codebase where Jenkins is addressed via HTTP:

1. `shared/jenkins-trigger.sh` — the curl invocation that triggers Jenkins jobs
2. `majordomo/system-prompt.md` — the documentation line stating the Jenkins URL

Both need to be updated from `http://` to `https://`. A test assertion for the URL scheme should also be added to `test/bats/jenkins-trigger.bats`.

---

## Stage 1: Change jenkins-trigger.sh and system-prompt.md to use https

### Description

Update the two HTTP Jenkins URL references to HTTPS:

1. In `shared/jenkins-trigger.sh` line 17: change `http://jenkins.${ROOT_DOMAIN}/...` to `https://jenkins.${ROOT_DOMAIN}/...`
2. In `majordomo/system-prompt.md` line 11: change `http://jenkins.${ROOT_DOMAIN}/` to `https://jenkins.${ROOT_DOMAIN}/`

Also add a test to `test/bats/jenkins-trigger.bats` that verifies the URL passed to curl uses the `https://` scheme (by recording curl args and asserting the URL argument starts with `https://`).

Run `make test` to verify all tests pass.

### Acceptance Criteria
- `shared/jenkins-trigger.sh` constructs a URL starting with `https://`
- `majordomo/system-prompt.md` documents the Jenkins base URL as `https://`
- A bats test in `test/bats/jenkins-trigger.bats` asserts the curl invocation uses `https://`
- `make test` passes with no errors
