#!/usr/bin/env bash
# Shared workspace setup for majordomo agents.
# Source from an agent-specific wrapper — do not source directly.
# Usage: source shared/setup-workspace.sh <mode>
#   worker   — feature branch must exist; always creates a fresh task branch
#   planning — creates feature branch if missing; resumes task branch if it exists
#
# Requires: BEADS_TASK_ID, GH_TOKEN, BASE_BRANCH env vars
# Exports:  REPO, EPIC_KEY, FEATURE_BRANCH

set -euo pipefail

MODE="${1:?Usage: source setup-workspace.sh <worker|planning>}"

# Derive REPO from BEADS_TASK_ID prefix by longest-match against known repos in config.yaml.
# e.g. "minordomo-856.2" → "minordomo", "gcp-setup-12.1" → "gcp-setup"
export REPO
REPO=$(python3 -c "
import yaml, sys
cfg = yaml.safe_load(open('shared/config.yaml'))
repos = sorted([p['repo'] for p in cfg['projects']], key=len, reverse=True)
beads_id = sys.argv[1]
for repo in repos:
    if beads_id.startswith(repo + '-'):
        print(repo)
        sys.exit(0)
sys.exit('No repo found for BEADS_TASK_ID ' + beads_id)
" "${BEADS_TASK_ID}")

# Wire up git credential helper so plain git commands can auth via GH_TOKEN.
gh auth setup-git

# Set git committer identity (required for merge commits).
git config --global user.name "minordomo"
git config --global user.email "$(echo "${ROOT_DOMAIN}" | cut -d. -f1)@gmail.com"

# Clone the target repo and cd into it.
gh repo clone "wcjordan/${REPO}" "${REPO}"
cd "${REPO}"

# Initialize the beads workspace so we can look up task details
[ -d .beads ] && chmod 700 .beads
git config beads.role maintainer
bd bootstrap
bd dolt show
bd dolt pull

# Derive EPIC_KEY from the beads task via shared/get-epic-key.sh.
export EPIC_KEY
EPIC_KEY=$("$(dirname "${BASH_SOURCE[0]}")/get-epic-key.sh" "${BEADS_TASK_ID}" "${REPO}" | head -1)

export FEATURE_BRANCH="feature/${EPIC_KEY}"

# Derive PARENT_ID for the CLOSED_SIBLINGS check in worker mode.
PARENT_ID=$(bd show "${BEADS_TASK_ID}" --json | python3 -c "import json,sys; t=json.load(sys.stdin); print(t[0].get('parent') or '')")

echo "Derived REPO=${REPO} EPIC_KEY=${EPIC_KEY} FEATURE_BRANCH=${FEATURE_BRANCH}"

# Reset HEAD to avoid conflicts when switching branches. This is a no-op if the repo is already clean.
git reset --hard

# Feature branch: planning creates it from main if missing; worker assumes it exists.
if [[ "$MODE" == "planning" ]]; then
    if git ls-remote --exit-code origin "${FEATURE_BRANCH}" > /dev/null 2>&1; then
        git checkout "${FEATURE_BRANCH}"
    else
        git checkout -b "${FEATURE_BRANCH}" "origin/${BASE_BRANCH}"
        git push -u origin "${FEATURE_BRANCH}"
    fi
else
    git checkout "${FEATURE_BRANCH}"

    # Detect if this is the first implementation task of the Epic.
    # Check whether any sibling stage beads are already closed — if none, this is the first task
    # and we merge the base branch to pick up the latest changes before creating the task branch.
    CLOSED_SIBLINGS=0
    if [ -n "$PARENT_ID" ]; then
        CLOSED_SIBLINGS=$(bd list --parent "$PARENT_ID" --status=closed --json 2>/dev/null \
            | python3 -c "
import json, sys
tasks = json.load(sys.stdin)
stage_tasks = [t for t in tasks if t.get('title', '').startswith('Stage')]
print(len(stage_tasks))
" 2>/dev/null || echo "0")
    fi
    IS_FIRST_TASK=$([[ "${CLOSED_SIBLINGS}" -eq 0 ]] && echo "yes" || echo "no")

    if [[ "$IS_FIRST_TASK" == "yes" ]]; then
        git fetch origin "${BASE_BRANCH}"
        git merge "origin/${BASE_BRANCH}" -m "chore: merge ${BASE_BRANCH} into ${FEATURE_BRANCH} before first implementation stage"
        git push origin "${FEATURE_BRANCH}"
    fi
fi

# Task branch: planning resumes an existing branch because the Needs Input cycle re-triggers
# it on the same task (research notes from the first run must survive). Workers have no
# re-run cycle yet — each Implementation Task is expected to complete in one shot — so
# always creating fresh keeps things simple. If worker re-runs are added later, resume
# logic will need to be introduced here.
if [[ "$MODE" == "planning" ]]; then
    if git ls-remote --exit-code origin "task/${BEADS_TASK_ID}" > /dev/null 2>&1; then
        git checkout "task/${BEADS_TASK_ID}"
        git pull
    else
        git checkout -b "task/${BEADS_TASK_ID}"
    fi
else
    git checkout -b "task/${BEADS_TASK_ID}"
fi

bd stats
