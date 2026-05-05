#!/usr/bin/env bash
# Deploys Claude agent permissions and registers the Atlassian MCP server.
# Source this script; do not execute it directly.
#
# Requires: JIRA_URL, JIRA_EMAIL and JIRA_API_TOKEN env vars (set by setup-env.sh)

set -euo pipefail

mkdir -p ~/.claude
cp majordomo/agent-settings.json ~/.claude/settings.json

claude mcp add atlassian \
    --env JIRA_URL="${JIRA_URL}" \
    --env JIRA_EMAIL="${JIRA_EMAIL}" \
    --env JIRA_API_TOKEN="${JIRA_API_TOKEN}" \
    -- uvx mcp-atlassian
claude mcp list
