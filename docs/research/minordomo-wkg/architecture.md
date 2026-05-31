# Research: Add shared jenkins-helm image, weekly build job, and dind shared library

## Context

This is Task 1 of a 3-repo effort to deduplicate the `jenkins-helm` Docker image and dind bootstrap pattern.
Full planning doc: https://github.com/wcjordan/minordomo/blob/docs/deduplicate-jenkins-helm-image/docs/planning/deduplicate-jenkins-helm-image.md

The work happens in the **gcp-setup** repo (wcjordan/gcp-setup), not minordomo.

## Current State of gcp-setup Repo

- Root contains only `terraform/` and `README.md` (no `jenkins/` directory yet)
- `terraform/jenkins.tf` — main Jenkins configuration via Helm + JCasC
- `terraform/charts/jenkins/values.yaml` — Jenkins Helm values (plugin list, basic config)
- No `jenkins/` or `jenkins-shared-library/` directories yet

## Dockerfile.helm (identical in both repos)

Both `minordomo/minordomo-container-builder/Dockerfile.helm` and `chalk/jenkins/gcloud_helm.Dockerfile` contain identical content:
- Base: `us.gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine`
- Installs: `kubectl` (via gcloud components), `helm v4.1.4`
- SHA256-verified helm download

## dind Bootstrap Pattern

The ~12-line bootstrap block (identical across build stages in both repos):
```sh
apk add --no-cache bash curl python3
curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts
export PATH="$HOME/google-cloud-sdk/bin:$PATH"
gcloud auth activate-service-account --key-file "$GKE_SA_FILE"
gcloud auth configure-docker ${GAR_HOST} --quiet
while ! docker stats --no-stream 2>/dev/null; do
    echo "Waiting for Docker to launch..."
    sleep 1
done
docker buildx create --driver docker-container --name <builder-name> --use || true
docker buildx build --push \
    --cache-to  type=registry,ref=${cacheRef},mode=max \
    --cache-from type=registry,ref=${cacheRef} \
    -f ${dockerfile} \
    -t ${imageTag} \
    .
```

## JCasC Structure (jenkins.tf)

The current JCasC `configScripts.jenkins-casc-configs` block defines:
- `credentials:` — GKE SA, BrowserStack, GitHub App, string secrets, username/password
- `jenkins:` — authorizationStrategy, clouds (kubernetes), globalNodeProperties (GCP_PROJECT, ROOT_DOMAIN, etc.), numExecutors, primaryView, securityRealm, views
- `security:` — queueItemAuthenticator
- `unclassified:` — defaultFolderConfiguration, location, throttleJobProperty, timestamper

**globalLibraries would go under `unclassified:` in JCasC.**
**Pipeline jobs require the `job-dsl` plugin; defined in a `jobs:` section of JCasC.**

## Existing Jenkins Plugins (values.yaml)

Currently installed: authorize-project, blueocean, browserstack-integration, build-failure-analyzer, configuration-as-code, docker-workflow, eddsa-api, github-checks, google-container-registry-auth, google-login, git, kubernetes, kubernetes-credentials-provider, matrix-auth, throttle-concurrents, timestamper, workflow-aggregator

`job-dsl` is NOT currently installed — must be added for JCasC `jobs:` section.

## GAR Configuration

- GAR_HOST: `us-east4-docker.pkg.dev`
- GAR_REPO: `${GAR_HOST}/${GCP_PROJECT}/default-gar` (env var injected via globalNodeProperties)
- Credential: `jenkins-gke-sa` (secret file, `GKE_SA_FILE` in scripts)
- Cache ref pattern: `${GAR_REPO}/jenkins-helm-cache:latest`
- Image tag: `${GAR_REPO}/jenkins-helm:latest`

## Trigger Scheduling

- minordomo container builder: `cron('H 2 * * 0')` (Sundays ~2 AM)
- New helm-image job: `cron('H 3 * * 0')` (Sundays, offset to avoid resource contention)

## Sequencing Note

After this PR merges, the new Jenkins job must be triggered manually (or wait for Sunday) to publish `jenkins-helm:latest` to GAR before Tasks 2/3 (chalk and minordomo) can safely remove their build stages.
