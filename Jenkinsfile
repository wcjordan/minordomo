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
                GH_APP                  = credentials('github-app')
                JENKINS_API_KEY         = credentials('jenkins-api-key')
                JIRA_TOKEN              = credentials('jira_api_key')
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
                        export GH_TOKEN=${GH_APP_PSW}

                        export JIRA_DOMAIN="${ROOT_DOMAIN%%.*}"
                        export JENKINS_USERNAME="$JIRA_DOMAIN@gmail.com"
                        export JIRA_USERNAME="$JIRA_DOMAIN@gmail.com"

                        echo "JIRA_DOMAIN: $JIRA_DOMAIN"
                        echo "JENKINS_USERNAME: $JENKINS_USERNAME"
                        echo "JIRA_USERNAME: $JIRA_USERNAME"

                        claude mcp add atlassian \
                            --env JIRA_URL=https://${JIRA_DOMAIN}.atlassian.net \
                            -- uvx mcp-atlassian
                        claude mcp list

                        claude -p "$(cat majordomo/system-prompt.md)"
                    '''
                }
            }
        }
    }
}
