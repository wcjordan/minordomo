# Deduplicate `jenkins-helm` Docker Image and dind Bootstrap Pattern

## Problem

Both chalk and minordomo independently build and push a `jenkins-helm` Docker image
(gcloud-cli + kubectl + helm) and contain an identical ~12-line dind bootstrap shell block
(install gcloud SDK, authenticate, wait for Docker, create buildx builder). This duplication
means version updates must be applied in two repos, and the bootstrap pattern will drift
over time.

**Desired end state:**
- `Dockerfile.helm` lives in `gcp-setup`; a weekly Jenkins job builds and pushes
  `jenkins-helm:latest` to GAR
- A Jenkins shared library in `gcp-setup` provides a `buildAndPushImage` step that
  encapsulates the dind bootstrap pattern
- chalk and minordomo remove their local copies and call the shared library step

---

## Repos Affected

| Repo | Change |
|---|---|
| `gcp-setup` | Add `Dockerfile.helm`, weekly build job, Jenkins shared library, update JCasC to register library |
| `chalk` | Remove `Dockerfile.helm` + "Build and Push Helm Image" stage; update remaining build stages to use shared library step |
| `minordomo` | Same as chalk |

---

## Task 1 — `gcp-setup`: Add shared image + shared library

### 1a. Move `Dockerfile.helm` to `gcp-setup/jenkins/Dockerfile.helm`

Exact content from minordomo (gcloud-cli alpine + kubectl + helm). Pin to same version
currently used in both repos. No change to the image itself.

### 1b. Add weekly Jenkins job to build and push `jenkins-helm:latest`

Create `gcp-setup/jenkins/Jenkinsfile.helm-image` that:
- Triggers on `cron('H 3 * * 0')` (Sundays, offset from chalk's existing weekly job)
- Uses a `dind` pod
- Authenticates to GAR, builds `gcp-setup/jenkins/Dockerfile.helm`, pushes
  `${GAR_REPO}/jenkins-helm:latest` with `${GAR_REPO}/jenkins-helm-cache:latest`

Register this as a new Jenkins pipeline job in `gcp-setup/terraform/jenkins.tf` (JCasC).

### 1c. Create Jenkins shared library at `gcp-setup/jenkins-shared-library/`

Directory structure (Jenkins convention):
```
gcp-setup/jenkins-shared-library/
  vars/
    buildAndPushImage.groovy
```

`buildAndPushImage.groovy`:
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

### 1d. Register shared library in Jenkins JCasC (`gcp-setup/terraform/jenkins.tf`)

Add to the Jenkins configuration YAML (in the JCasC block):
```yaml
globalLibraries:
  libraries:
    - name: "jenkins-shared-library"
      retriever:
        modernSCM:
          scm:
            git:
              remote: "https://github.com/wcjordan/gcp-setup.git"
              includes: "*"
          libraryPath: "jenkins-shared-library/"
```

---

## Task 2 — `chalk`: Use shared library, remove local `Dockerfile.helm`

**Files to modify:**
- `Jenkinsfile` (or wherever the helm image build stage lives)
- Delete `jenkins/gcloud_helm.Dockerfile` (or equivalent)

**Changes:**
1. Add `@Library('jenkins-shared-library') _` at the top of the Jenkinsfile
2. Remove the "Build and Push Helm Image" stage entirely (image now published from
   `gcp-setup` weekly job)
3. In remaining `dind`-based build stages, replace the inline bootstrap block with
   `buildAndPushImage(...)` calls:
   ```groovy
   buildAndPushImage(
       garHost: GAR_HOST,
       cacheRef: "${GAR_REPO}/<image>-cache:latest",
       dockerfile: 'path/to/Dockerfile',
       imageTag: "${GAR_REPO}/<image>:latest",
       builderName: '<builder-name>'
   )
   ```

**Depends on:** Task 1 merged and the weekly job run at least once to publish
`jenkins-helm:latest`.

---

## Task 3 — `minordomo`: Use shared library, remove local `Dockerfile.helm`

**Files to modify:**
- `minordomo-container-builder/Jenkinsfile`
- Delete `minordomo-container-builder/Dockerfile.helm`

**Changes to `Jenkinsfile`:**
1. Add `@Library('jenkins-shared-library') _` at top
2. Remove "Build and Push Helm Image" stage entirely
3. Replace "Build and Push" stage inline bootstrap with:
   ```groovy
   buildAndPushImage(
       garHost: GAR_HOST,
       cacheRef: "${GAR_REPO}/minordomo-image-cache:latest",
       dockerfile: 'minordomo-container-builder/Dockerfile',
       imageTag: "${GAR_REPO}/minordomo-image:latest",
       builderName: 'majordomo-builder'
   )
   ```
4. "Deploy Dolt Server" stage is unchanged (uses pre-built `jenkins-helm:latest`, no dind)

**Depends on:** Task 1 merged and the weekly job run at least once.

---

## Sequencing

1. **Task 1** (gcp-setup PR) — prerequisite; must be merged and weekly job run at least
   once before Tasks 2/3 can safely remove their build stages
2. **Tasks 2 and 3** — independent of each other; can be separate PRs in parallel after
   Task 1

---

## Verification

- After Task 1: trigger the new Jenkins job manually; confirm `jenkins-helm:latest`
  appears in GAR
- After Task 2: chalk's container-builder pipeline succeeds with no local
  `Dockerfile.helm` build
- After Task 3: minordomo's container-builder pipeline succeeds; "Deploy Dolt Server"
  stage still works (pulls `jenkins-helm:latest` from GAR)
- Monthly version pin updates only need to happen in `gcp-setup/jenkins/Dockerfile.helm`
