# Research: Add GitHub Action for `make test` on PRs

## Requirement
Issue #297 (title only, no body): "Add a Github action to ensure make test passes on PRs"

## What `make test` runs

`Makefile` target `test` runs `bash test/run-all.sh`, which:

1. Installs missing deps (via `brew` on macOS, guarded by `command -v` checks)
2. Runs `shellcheck shared/*.sh`
3. Runs `python3 test/validate-prompts.py`
4. Runs `bash test/dry-run.sh`
5. Runs `make check-safety` (generates safety rules from `shared/safety-rules.yaml` using pyyaml)
6. Runs `bats test/bats/`

## Dependencies needed on CI

| Tool | Ubuntu apt package | Notes |
|------|-------------------|-------|
| shellcheck | `shellcheck` | available in apt |
| bats | `bats` | apt provides bats-core 1.11.1 — compatible with test suite |
| pyyaml | pip3 package | needed by generate-safety-rules.sh and validate-prompts.py |
| python3 | pre-installed on ubuntu-latest | — |
| git | pre-installed on ubuntu-latest | needed by dry-run.sh |
| make | pre-installed on ubuntu-latest | — |

## Key findings

- `test/run-all.sh` uses `brew install` guards with `command -v` checks — pre-installing tools on Ubuntu makes those blocks no-ops; script does NOT need modification
- `test/dry-run.sh` creates a local bare git repo as a mock remote; no real network access or external secrets needed
- `test/dry-run.sh` sets `user.email` and `user.name` inline; no global git config needed in workflow
- Bats tests use `$BATS_TEST_DIRNAME` and `@test` syntax — compatible with bats-core 1.x
- No bats 1.x-specific flags (--separate-stderr, bats_require_minimum_version) used
- No GitHub secrets needed; test suite is fully self-contained
- `.github/` only has `CODEOWNERS`; no existing workflows

## Workflow design decisions

- Runner: `ubuntu-latest` (faster, free-tier; macOS not needed since we pre-install deps)
- Trigger: `pull_request` only — issue says "on PRs"; not expanding to push events
- Single step for deps: `apt-get install shellcheck bats` + `pip3 install pyyaml`
