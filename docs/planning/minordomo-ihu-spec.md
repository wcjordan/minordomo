# Implementation Plan: Add GitHub Action for `make test` on PRs

**Epic:** minordomo-ihu  
**Source:** GH Issue #297 (title only: "Add a Github action to ensure make test passes on PRs")

## Summary

Add a single GitHub Actions workflow file that runs `make test` on every pull request. The test suite (`test/run-all.sh`) uses `brew` to install missing tools, but all checks are guarded by `command -v`; pre-installing shellcheck, bats, and pyyaml on the Ubuntu runner makes those brew blocks no-ops, so `test/run-all.sh` needs no modification.

**Trigger choice:** `pull_request` only (issue says "on PRs"; push-to-main coverage is not requested).

---

## Stage 1: Add GitHub Actions CI workflow

### Description

Create `.github/workflows/ci.yml` that triggers on pull requests, installs the three test dependencies (shellcheck, bats, pyyaml), and runs `make test`.

Steps in the workflow job:
1. `actions/checkout@v4`
2. Install deps: `sudo apt-get update && sudo apt-get install -y shellcheck bats` + `pip3 install pyyaml`
3. `make test`

No secrets are needed; the test suite is fully self-contained (dry-run mocks `gh`, `claude`, and `bd` locally).

### Acceptance Criteria

- `.github/workflows/ci.yml` exists and is valid YAML
- The workflow triggers on `pull_request` events
- The workflow job runs on `ubuntu-latest`
- Shellcheck, bats, and pyyaml are installed before `make test` runs
- The final step executes `make test`
- No changes are made to `test/run-all.sh` or any other existing file
