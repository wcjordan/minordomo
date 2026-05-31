# Implementation Plan: Use jenkins-shared-library for dind bootstrap, remove local Dockerfile.helm

GH Issue: https://github.com/wcjordan/minordomo/issues/238

## Background

minordomo currently builds and pushes a `jenkins-helm` Docker image locally and uses an inline ~12-line dind bootstrap shell block in its container-builder Jenkinsfile. A shared library (`jenkins-shared-library`) from the `gcp-setup` repo encapsulates this pattern. This plan migrates minordomo to use the shared library and removes the duplicated local build.

---

## Stage 1: Migrate Jenkinsfile to buildAndPushImage shared library step and delete Dockerfile.helm

### Description

Update `minordomo-container-builder/Jenkinsfile` to:
1. Add `@Library('jenkins-shared-library') _` at the top of the file.
2. Remove the "Build and Push Helm Image" stage entirely (the shared library/gcp-setup weekly job now publishes `jenkins-helm:latest` to GAR).
3. Replace the inline dind bootstrap shell block in the "Build and Push" stage's `steps` with a call to `buildAndPushImage()`:
   ```groovy
   buildAndPushImage(
       garHost: GAR_HOST,
       cacheRef: "${GAR_REPO}/minordomo-image-cache:latest",
       dockerfile: 'minordomo-container-builder/Dockerfile',
       imageTag: "${GAR_REPO}/minordomo-image:latest",
       builderName: 'majordomo-builder'
   )
   ```
   The `withCredentials` wrapper and `container('dind')` block are no longer needed since the shared library step handles credentials and dind internally — remove them and replace with just the `buildAndPushImage()` call.

Delete `minordomo-container-builder/Dockerfile.helm`.

The kubernetes agent block (pod spec with dind container, resource requests, timeout) for the "Build and Push" stage should be kept as-is since the shared library step runs within the existing agent context.

### Acceptance Criteria
- `minordomo-container-builder/Jenkinsfile` begins with `@Library('jenkins-shared-library') _`
- "Build and Push Helm Image" stage is removed from the Jenkinsfile
- "Build and Push" stage `steps` block contains only the `buildAndPushImage(...)` call (no inline shell bootstrap, no `withCredentials` wrapper, no `container('dind')` wrapper)
- `minordomo-container-builder/Dockerfile.helm` is deleted
- PR is opened against `feature/minordomo-jvb` (not merged — blocked until `gcp-setup` shared library PR is merged and `jenkins-helm:latest` is published to GAR)
