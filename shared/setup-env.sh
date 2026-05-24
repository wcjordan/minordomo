#!/usr/bin/env bash
# Derives runtime environment variables from Jenkins-injected credentials and config.
# Source this script; do not execute it directly.
#
# Requires: ROOT_DOMAIN, GH_APP_PSW, JIRA_ACCT_PSW, JIRA_ACCT_USR env vars (set by Jenkins credentials binding)

set -euo pipefail

export DOMAIN_ROOT="${ROOT_DOMAIN%%.*}"
export JIRA_URL="https://api.atlassian.com/ex/jira/${JIRA_CLOUD_ID}"
export JENKINS_USERNAME="${DOMAIN_ROOT}@gmail.com"
export JIRA_EMAIL="${JIRA_ACCT_USR}"
export JIRA_API_TOKEN="${JIRA_ACCT_PSW}"
export GH_TOKEN="${GH_APP_PSW}"
export NOTIFICATION_EMAIL="${JENKINS_USERNAME}"

export BASE_BRANCH
BASE_BRANCH=$(python3 -c "
import yaml
cfg = yaml.safe_load(open('shared/config.yaml'))
print(cfg.get('base_branch', 'main'))
")
