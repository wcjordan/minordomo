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

# Derive REPO from the beads task ID prefix via config.yaml.
# Beads task IDs are <repo>-<hash>[.<subtask-num>], where the repo name comes first.
export REPO
REPO=$(python3 -c "
import yaml, sys
cfg = yaml.safe_load(open('shared/config.yaml'))
repos = [p['repo'] for p in cfg['projects']]
bid = '${BEADS_TASK_ID}'
for repo in repos:
    if bid.startswith(repo + '-'):
        print(repo)
        sys.exit()
sys.exit('No repo found for BEADS_TASK_ID: ' + bid)
")

# Derive EPIC_KEY by navigating: beads task → parent planning task → GH Issue URL
# → GH Issue comments → "Jira Epic:" comment.
#
# First, find the beads planning task (parent for subtasks, self for planning tasks).
BEADS_PARENT_ID=$(bd show "${BEADS_TASK_ID}" --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
task = data[0]
parent = task.get('parent', '')
print(parent if parent else task['id'])
")

# Get GH Issue URL from the planning task description.
GH_ISSUE_URL=$(bd show "${BEADS_PARENT_ID}" --json | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
desc = data[0].get('description', '')
m = re.search(r'GH Issue: (https://\S+)', desc)
if not m:
    sys.exit('No GH Issue URL in beads planning task description for ${BEADS_PARENT_ID}')
print(m.group(1))
")

GH_ISSUE_NUM=$(echo "$GH_ISSUE_URL" | grep -oE '/issues/[0-9]+' | grep -oE '[0-9]+')

# Find the Jira Epic key from GH Issue comments (Majordomo posts "Jira Epic: <KEY>" as comment).
export EPIC_KEY
EPIC_KEY=$(gh issue view "$GH_ISSUE_NUM" --repo "wcjordan/${REPO}" --comments --json comments | python3 -c "
import json, sys, re
data = json.load(sys.stdin)
for comment in data.get('comments', []):
    m = re.search(r'Jira Epic: (\w+-[0-9]+)', comment.get('body', ''))
    if m:
        print(m.group(1))
        sys.exit()
sys.exit('No Jira Epic key found in GH Issue ${GH_ISSUE_NUM} comments')
")
export FEATURE_BRANCH="feature/${EPIC_KEY}"

echo "Derived REPO=${REPO} EPIC_KEY=${EPIC_KEY} FEATURE_BRANCH=${FEATURE_BRANCH}"

# Wire up git credential helper so plain git commands can auth via GH_TOKEN.
gh auth setup-git

# Clone the target repo and cd into it.
gh repo clone "wcjordan/${REPO}" "${REPO}"
cd "${REPO}"

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

    # Detect if this is the first (stage-1) implementation task of the Epic.
    # If so, merge origin/${BASE_BRANCH} into the feature branch before creating the task branch.
    # A task is Stage 1 if it has no "blocks"-type sibling dependencies (only parent-child).
    IS_FIRST_TASK=$(bd show "${BEADS_TASK_ID}" --json | python3 -c "
import json, sys
data = json.load(sys.stdin)
task = data[0]
deps = task.get('dependencies', [])
blocks_deps = [d for d in deps if d.get('type') == 'blocks']
# Stage 1 has no blocking sibling dependencies
print('yes' if not blocks_deps else 'no')
")

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

# Initialize the beads workspace against the central Dolt server.
# metadata.json is committed but the Dolt DB is not — bd init --server connects and pulls it.
[ -d .beads ] && chmod 700 .beads
bd dolt show
bd stats
