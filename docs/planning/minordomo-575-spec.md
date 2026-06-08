# Implementation Plan: Evaluate & Delete Dead Code at helm/minordomo-cd-setup

## Background

`helm/minordomo-cd-setup` is a Helm chart that creates Kubernetes secrets (`dolt-root-password`
and `dolt-minordomo-password`) for a Dolt SQL server. The Dolt server was removed in commit
`58c00c9` ("Switch bd to embedded mode"), but `helm/minordomo-cd-setup` was not cleaned up at
that time. It is confirmed dead code: the secrets it creates are not referenced anywhere in the
current codebase, and the `make setup-cd` target that deploys it is called from no pipeline or
script.

This plan removes the chart and all related artifacts in a single stage.

---

## Stage 1: Delete helm/minordomo-cd-setup and related dead artifacts

### Description

Remove the `helm/minordomo-cd-setup` Helm chart directory and all artifacts that exist solely
to support it: the `setup-cd` Makefile target, the `.env` Makefile target (which only generates
passwords for `setup-cd`), and the `DOLT_ROOT_PASSWORD` / `DOLT_MINORDOMO_PASSWORD` entries
in `.env.example`.

Specific changes:
1. Delete the entire `helm/minordomo-cd-setup/` directory (3 files: `Chart.yaml`, `values.yaml`,
   `templates/secrets.yaml`)
2. Remove the `.env` Makefile target (lines 21–27) — it only populates dolt passwords for `setup-cd`
3. Remove the `setup-cd` Makefile target (lines 29–45) — it only deploys the deleted helm chart
4. Remove `DOLT_ROOT_PASSWORD=` and `DOLT_MINORDOMO_PASSWORD=` from `.env.example` — if
   `.env.example` becomes empty after this, delete the file too; otherwise keep it
5. Run `make test` to confirm nothing is broken

### Acceptance Criteria

- `helm/minordomo-cd-setup/` directory no longer exists in the repo
- `Makefile` contains no `setup-cd` target
- `Makefile` contains no `.env` target
- `.env.example` no longer contains `DOLT_ROOT_PASSWORD` or `DOLT_MINORDOMO_PASSWORD`; if
  the file is now empty, it is deleted
- `make test` passes with no failures
- A PR is opened targeting `feature/minordomo-575`
