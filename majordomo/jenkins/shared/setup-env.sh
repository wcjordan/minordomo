#!/usr/bin/env bash
# Derives runtime environment variables from Jenkins-injected credentials.
# Source this script; do not execute it directly.
#
# Requires: ROOT_DOMAIN, GH_APP_PSW, JIRA_TOKEN env vars (set by Jenkins credentials binding)

set -euo pipefail

export JIRA_DOMAIN="${ROOT_DOMAIN%%.*}"
export JENKINS_USERNAME="${JIRA_DOMAIN}@gmail.com"
export JIRA_USERNAME="${JIRA_DOMAIN}@gmail.com"
export JIRA_EMAIL="$JIRA_USERNAME"
export GH_TOKEN="${GH_APP_PSW}"
