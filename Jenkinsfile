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
                JIRA_ACCT               = credentials('minordomo_jenkins_token')
            }
            options {
                timeout(time: 60, unit: 'MINUTES')
            }
            steps {
                container('majordomo') {
                    sh '''
                        set -euo pipefail

                        source majordomo/jenkins/shared/setup-env.sh

                        sleep 1800

                        source majordomo/jenkins/shared/setup-claude.sh

                        claude -p "$(cat majordomo/system-prompt.md)"
                    '''
                }
            }
        }
    }
}
