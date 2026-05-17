#!/usr/bin/env bash
# Deploys Claude agent permissions and registers the Atlassian MCP server.
# Source this script; do not execute it directly.
#
# Requires: JIRA_URL, JIRA_EMAIL and JIRA_API_TOKEN env vars (set by setup-env.sh)

set -euo pipefail

mkdir -p ~/.claude/hooks
cp shared/agent-settings.json ~/.claude/settings.json
cp shared/pre-bash-guard.sh ~/.claude/hooks/pre-bash-guard.sh

claude mcp add atlassian \
    --env JIRA_URL="${JIRA_URL}" \
    --env JIRA_EMAIL="${JIRA_EMAIL}" \
    --env JIRA_API_TOKEN="${JIRA_API_TOKEN}" \
    -- uvx mcp-atlassian
claude mcp list

mkdir -p ~/.config/beads
cat > ~/.config/beads/server.json <<'EOF'
{
  "dolt_mode": "server",
  "dolt_server_host": "dolt-server.minordomo.svc.cluster.local",
  "dolt_server_port": 3306
}
EOF
