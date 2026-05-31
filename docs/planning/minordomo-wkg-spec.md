# Implementation Plan: Add shared jenkins-helm image, weekly build job, and dind shared library

**Epic:** minordomo-wkg  
**GH Issue:** https://github.com/wcjordan/gcp-setup/issues/16  
**Target repo:** wcjordan/gcp-setup  
**Feature branch:** feature/minordomo-wkg

This is Task 1 of a 3-repo deduplication effort. All changes land in `gcp-setup`.
After this PR merges, trigger the new Jenkins job manually to confirm `jenkins-helm:latest`
appears in GAR before Tasks 2 and 3 (chalk and minordomo) proceed.

---

## Stage 1: Add Dockerfile.helm, Jenkinsfile.helm-image, and shared library to gcp-setup

### Description

Create three new files in the `gcp-setup` repo that form the foundation of the shared
image and shared library:

1. `jenkins/Dockerfile.helm` — exact copy of the content from
   `minordomo/minordomo-container-builder/Dockerfile.helm` (gcloud-cli alpine + kubectl +
   helm v4.1.4). No changes to the image itself.

2. `jenkins/Jenkinsfile.helm-image` — a new pipeline that:
   - Triggers on `cron('H 3 * * 0')` (Sundays, offset from minordomo's `H 2 * * 0`)
   - Declares `GAR_HOST = 'us-east4-docker.pkg.dev'` and `GAR_REPO = "${GAR_HOST}/${env.GCP_PROJECT}/default-gar"`
   - Uses a `dind` pod (docker:27-dind, privileged, 500m–1000m CPU, 1–2 Gi mem)
   - In the `dind` container step: authenticates to GAR, waits for Docker, then runs
     `docker buildx build --push` with cache-to/cache-from `${GAR_REPO}/jenkins-helm-cache:latest`
     targeting `jenkins/Dockerfile.helm` and pushing to `${GAR_REPO}/jenkins-helm:latest`
   - Uses the `jenkins-gke-sa` credential (file, `GKE_SA_FILE`)
   - Has no `post` block (`notifyFailure()` is a minordomo-specific helper not available in
     gcp-setup; omit it entirely rather than leaving a broken reference)
   - Uses the **inline** dind bootstrap (not the `buildAndPushImage` shared library step),
     because the Jenkinsfile.helm-image is the canonical source of the pattern — the
     shared library is extracted from it, not the other way around; dog-fooding would add
     circular complexity
   - Wraps `withCredentials([file(credentialsId: 'jenkins-gke-sa', variable: 'GKE_SA_FILE')])`
     around the full bootstrap+build shell block

3. `jenkins-shared-library/vars/buildAndPushImage.groovy` — as specified in the GH issue:
   ```groovy
   def call(Map config) {
       withCredentials([file(credentialsId: config.get('credentialsId', 'jenkins-gke-sa'), variable: 'GKE_SA_FILE')]) {
           sh """
               set -euo pipefail
               apk add --no-cache bash curl python3
               curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
               export PATH="\$HOME/google-cloud-sdk/bin:\$PATH"
               gcloud auth activate-service-account --key-file "\$GKE_SA_FILE"
               gcloud auth configure-docker ${config.garHost} --quiet
               while ! docker stats --no-stream 2>/dev/null; do
                   echo "Waiting for Docker to launch..."
                   sleep 1
               done
               docker buildx create --driver docker-container --name ${config.get('builderName', 'default-builder')} --use || true
               docker buildx build --push \\
                   --cache-to  type=registry,ref=${config.cacheRef},mode=max \\
                   --cache-from type=registry,ref=${config.cacheRef} \\
                   -f ${config.dockerfile} \\
                   -t ${config.imageTag} \\
                   .
           """
       }
   }
   ```

### Acceptance Criteria
- `jenkins/Dockerfile.helm` exists in the repo with identical content to `minordomo/minordomo-container-builder/Dockerfile.helm` (gcloud-cli:alpine base, kubectl, helm v4.1.4)
- `jenkins/Jenkinsfile.helm-image` exists with a `cron('H 3 * * 0')` trigger, a dind pod agent, inline dind bootstrap (not calling `buildAndPushImage`), and a build-and-push step targeting `${GAR_REPO}/jenkins-helm:latest` with cache; no `post { notifyFailure() }` block
- `jenkins-shared-library/vars/buildAndPushImage.groovy` exists with the `def call(Map config)` signature encapsulating the full dind bootstrap + buildx build pattern
- All three files are committed and the PR is openable

---

## Stage 2: Register job and shared library in Jenkins JCasC (terraform)

### Description

Update `terraform/jenkins.tf` and `terraform/charts/jenkins/values.yaml` to register the
new pipeline job and shared library in Jenkins via JCasC.

**1. Add `job-dsl` plugin to `terraform/charts/jenkins/values.yaml`**

Append `- job-dsl` to the `installPlugins` list (alphabetically between `git` and
`kubernetes`, or at the end). This enables the `jobs:` section in JCasC.

**2. Add `globalLibraries` to the JCasC `unclassified:` block in `terraform/jenkins.tf`**

In the existing `unclassified:` section of the JCasC configScript, add:
```yaml
globalLibraries:
  libraries:
    - name: "jenkins-shared-library"
      defaultVersion: "main"
      retriever:
        modernSCM:
          scm:
            git:
              remote: "https://github.com/wcjordan/gcp-setup.git"
              includes: "*"
          libraryPath: "jenkins-shared-library/"
```

**3. Add a `jobs:` section to the JCasC configScript**

Add a top-level `jobs:` key in the JCasC configScript YAML to define the new pipeline job
using Job DSL syntax:
```yaml
jobs:
  - script: >
      pipelineJob('jenkins-helm-image') {
        triggers {
          cron('H 3 * * 0')
        }
        definition {
          cpsScm {
            scm {
              git {
                remote { url('https://github.com/wcjordan/gcp-setup') }
                branch('*/main')
              }
            }
            scriptPath('jenkins/Jenkinsfile.helm-image')
          }
        }
      }
```

**4. Add `jenkins-helm-image` to the Mainline view `jobNames` list** in the JCasC
`jenkins:` > `primaryView:` section and the duplicate `views:` entry.

### Acceptance Criteria
- `terraform/charts/jenkins/values.yaml` includes `job-dsl` in the plugin list
- The `unclassified:` section of the JCasC configScript includes a `globalLibraries:` block pointing to `gcp-setup/jenkins-shared-library/` on the `main` branch
- The JCasC configScript includes a `jobs:` section defining the `jenkins-helm-image` pipeline job pointed at `jenkins/Jenkinsfile.helm-image` in gcp-setup
- `jenkins-helm-image` is listed in the Mainline view `jobNames`
- Changes are committed and the PR is openable
