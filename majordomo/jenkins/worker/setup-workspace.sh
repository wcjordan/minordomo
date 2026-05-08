#!/usr/bin/env bash
# Workspace setup for the worker agent. Source this script — do not execute it.
# After sourcing, the shell's working directory is the root of the cloned repo.
# Requires: JIRA_TASK_ID, JIRA_URL, JIRA_EMAIL, JIRA_API_TOKEN, GH_TOKEN env vars
# Exports:  REPO, EPIC_KEY, FEATURE_BRANCH
source majordomo/jenkins/shared/setup-workspace.sh worker
