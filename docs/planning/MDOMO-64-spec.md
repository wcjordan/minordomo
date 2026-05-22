# MDOMO-64: dolt-server is sometimes OOMKilled

## Overview

The `dolt-server-0` pod is being OOMKilled due to a 64Mi memory limit that is too restrictive. This plan removes the memory limit and quadruples the CPU limit per the requirements in GitHub issue #94.

---

## Stage 1: Adjust dolt-server resource limits in Helm values

### Description

Update `helm/dolt-server/values.yaml` to remove the memory limit (preventing future OOMKills) and raise the CPU limit from 100m to 400m (4×). Memory and CPU requests are left unchanged. No other files require modification — `values.yaml` is the single source of truth used by the Helm deployment in `minordomo-container-builder/Jenkinsfile`.

### Acceptance Criteria
- `helm/dolt-server/values.yaml` no longer contains a `limits.memory` key
- `limits.cpu` in `helm/dolt-server/values.yaml` is set to `400m`
- `requests.memory` remains `32Mi` and `requests.cpu` remains `10m`
- `make test` passes (shellcheck, bats, prompt validation)
- A PR is opened targeting `feature/MDOMO-64`
