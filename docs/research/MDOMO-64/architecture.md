# MDOMO-64 Research: dolt-server Resource Limits

## Problem

`dolt-server-0` pod in the `minordomo` namespace is being OOMKilled. The current memory limit of 64Mi is too low.

## Resource Configuration Location

Single source of truth: `helm/dolt-server/values.yaml`

Deployed via Helm in `minordomo-container-builder/Jenkinsfile` (lines 157-159):
```bash
helm upgrade --install --namespace minordomo dolt-server helm/dolt-server/
```

No environment-specific overrides exist; values.yaml is used for all environments.

## Current Resource Values

```yaml
resources:
  limits:
    memory: 64Mi
    cpu: 100m
  requests:
    memory: 32Mi
    cpu: 10m
```

## Required Changes (from GitHub issue #94)

1. Remove `limits.memory` — stop imposing a memory ceiling so OOMKills can't happen
2. Set `limits.cpu` to 4× current: `100m → 400m`
3. `limits.memory` removed; `requests.memory` (32Mi) and `requests.cpu` (10m) left unchanged

## Resulting values.yaml resources section

```yaml
resources:
  limits:
    cpu: 400m
  requests:
    memory: 32Mi
    cpu: 10m
```
