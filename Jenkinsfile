def GAR_HOST = 'us-east4-docker.pkg.dev'
def GAR_REPO = "${GAR_HOST}/${env.GCP_PROJECT}/default-gar"

pipeline {
    agent none
    options {
        timestamps()
        disableConcurrentBuilds()
    }
    stages {
        stage('Majordomo') {
            agent {
                kubernetes {
                    yaml """
                        apiVersion: v1
                        kind: Pod
                        spec:
                          containers:
                          - name: majordomo
                            image: ${GAR_REPO}/majordomo-runner:latest
                            command:
                            - cat
                            tty: true
                            resources:
                              requests:
                                cpu: "500m"
                                memory: "1Gi"
                              limits:
                                cpu: "1000m"
                                memory: "2Gi"
                    """
                }
            }
            environment {
                CLAUDE_CODE_OAUTH_TOKEN = credentials('claude-code-oauth-token')
                GH_TOKEN                = credentials('gh-token')
                JIRA_DOMAIN             = 'flipperkid'
                ATLASSIAN_EMAIL         = credentials('atlassian-email')
                ATLASSIAN_TOKEN         = credentials('atlassian-api-token')
            }
            options {
                timeout(time: 60, unit: 'MINUTES')
            }
            steps {
                container('majordomo') {
                    sh '''
                        set -euo pipefail

                        # Deploy agent permissions into the repo's .claude directory
                        mkdir -p .claude
                        cp majordomo/agent-settings.json .claude/settings.json

                        # Substitute credentials into the MCP config and write to a temp file.
                        # The MCP server inherits the container environment, so env vars in the
                        # config template are resolved by the shell before claude starts.
                        MCP_CONFIG=$(mktemp)
                        envsubst < majordomo/mcp-config.json > "$MCP_CONFIG"

                        claude -p "$(cat majordomo/system-prompt.md)" \
                            --mcp-config "$MCP_CONFIG"

                        rm -f "$MCP_CONFIG"
                    '''
                }
            }
        }
    }
}
