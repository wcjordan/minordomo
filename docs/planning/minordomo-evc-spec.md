# Implementation Plan: Update `bd bootstrap` calls to `bd bootstrap -- --silent`

## Summary

Replace all 5 occurrences of `bd bootstrap` with `bd bootstrap -- --silent` across 4 files to suppress verbose chunk-download progress output in CI logs.

---

## Stage 1: Replace `bd bootstrap` with `bd bootstrap -- --silent` in all pipeline files

### Description

Find and replace every bare `bd bootstrap` call with `bd bootstrap -- --silent` in the four affected files:
- `majordomo/Jenkinsfile` (2 occurrences, lines 59 and 155)
- `shared/setup-workspace.sh` (1 occurrence, line 21)
- `shared/agent-pipeline.Jenkinsfile` (1 occurrence, line 153)
- `minordomo-sweep/Jenkinsfile` (1 occurrence, line 57 — `bd bootstrap && bd dolt pull` becomes `bd bootstrap -- --silent && bd dolt pull`)

Run `make test` after the changes to confirm shellcheck and bats tests pass.

### Acceptance Criteria
- `grep -r "bd bootstrap" .` returns only results containing `bd bootstrap -- --silent` (no bare `bd bootstrap` calls remain)
- `make test` passes with no errors
- The change is committed and a PR is opened targeting `feature/minordomo-evc`
