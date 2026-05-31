# Research: minordomo-jvb — Use jenkins-shared-library for dind bootstrap

## Current State

`minordomo-container-builder/Jenkinsfile` has two stages:

1. **"Build and Push"** — builds `minordomo-image:latest` using a dind pod with inline ~12-line bootstrap (apk install, gcloud SDK install, auth, docker wait loop, buildx build).
2. **"Build and Push Helm Image"** — builds `jenkins-helm:latest` from `Dockerfile.helm` using the same inline dind bootstrap pattern.

`minordomo-container-builder/Dockerfile.helm` — builds google-cloud-cli:alpine image with kubectl + helm v4.1.4 installed.

## Desired End State (from GH Issue #238)

- `Dockerfile.helm` is deleted (the shared library/gcp-setup weekly job handles publishing `jenkins-helm:latest` to GAR)
- "Build and Push Helm Image" stage removed from Jenkinsfile
- "Build and Push" stage's inline bootstrap replaced with `buildAndPushImage()` call from `jenkins-shared-library`
- `@Library('jenkins-shared-library') _` added at top of Jenkinsfile

## buildAndPushImage() signature

```groovy
buildAndPushImage(
    garHost: GAR_HOST,
    cacheRef: "${GAR_REPO}/minordomo-image-cache:latest",
    dockerfile: 'minordomo-container-builder/Dockerfile',
    imageTag: "${GAR_REPO}/minordomo-image:latest",
    builderName: 'majordomo-builder'
)
```

Parameters:
- `garHost` — GAR hostname for `gcloud auth configure-docker`
- `cacheRef` — registry ref for BuildKit cache
- `dockerfile` — path to Dockerfile
- `imageTag` — fully-qualified image tag to push
- `builderName` — (optional) buildx builder name, defaults to `default-builder`
- `credentialsId` — (optional) Jenkins credential ID, defaults to `jenkins-gke-sa`

## Kubernetes Agent Pod Spec

The current "Build and Push" stage has:
- container: dind, image: docker:27-dind, privileged: true
- requests: cpu 1000m, memory 2Gi / limits: cpu 2000m, memory 4Gi
- timeout: 30 minutes

The `buildAndPushImage()` shared library step presumably handles its own container setup via the dind pod spec defined in the shared library. The worker should verify whether the kubernetes agent block stays or is replaced by the library.

## Deploy Dolt Server Stage

Not present in this Jenkinsfile — GH issue notes it's unchanged and uses pre-built `jenkins-helm:latest`. The "Deploy Dolt Server" must live elsewhere (another Jenkinsfile). No changes needed here.

## Dependency Note

This change is safe to implement but should not be merged until `gcp-setup` "Add shared jenkins-helm image, weekly build job, and dind shared library" is merged and `jenkins-helm:latest` is published to GAR. The worker can open a PR; human merges when ready.
