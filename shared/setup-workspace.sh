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

# Pin BEADS_DIR and SHARED to the workspace root before cd-ing into the target repo.
# Both are used by infrastructure scripts and system prompts; they must not resolve
# relative to the target repo (which may be on a feature branch or lack shared/ entirely).
export BEADS_DIR SHARED
BEADS_DIR="$(pwd)/.beads"
SHARED="$(pwd)/shared"

# Initialize the minordomo beads workspace so we can look up task details before cloning target.
[ -d .beads ] && chmod 700 .beads
bd bootstrap -- --silent
bd dolt show
bd dolt pull

# Derive EPIC_KEY, GH_ISSUE_NUMBER, and REPO from the Story bead via get-story-key.sh.
export EPIC_KEY REPO GH_ISSUE_NUMBER
{ read -r EPIC_KEY; read -r GH_ISSUE_NUMBER; read -r REPO; } \
    < <("$(dirname "${BASH_SOURCE[0]}")/get-story-key.sh" "${BEADS_TASK_ID}")

# Wire up git credential helper so plain git commands can auth via GH_TOKEN.
gh auth setup-git

# Set git committer identity (required for merge commits).
# Use env vars rather than --global so local test runs don't overwrite the user's git config.
export GIT_AUTHOR_NAME="minordomo"
export GIT_COMMITTER_NAME="minordomo"
export GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL
GIT_AUTHOR_EMAIL="$(echo "${ROOT_DOMAIN}" | cut -d. -f1)@gmail.com"
GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL}"

# Clone the target repo and cd into it.
gh repo clone "wcjordan/${REPO}" "${REPO}"
cd "${REPO}"

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
