// Shared agent pipeline. AGENT_MODE must be set by the caller ('planning' or 'worker').
def GAR_HOST = 'us-east4-docker.pkg.dev'
def GAR_REPO = "${GAR_HOST}/${env.GCP_PROJECT}/default-gar"

def agentStageName  = (AGENT_MODE == 'planning') ? 'Planning Agent' : 'Worker'
def agentPromptPath = (AGENT_MODE == 'planning') ? '../minordomo-plan/system-prompt.md'
                                                  : '../minordomo-step/system-prompt.md'

properties([parameters([
    string(name: 'BEADS_TASK_ID', description: 'Beads task ID for this pipeline run', trim: true)
])])

def workerPodYaml = """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: worker
    image: ${GAR_REPO}/minordomo-image:latest
    command: [cat]
    tty: true
    resources:
      requests:
        cpu: "500m"
        memory: "1Gi"
      limits:
        cpu: "1000m"
        memory: "2Gi"
"""

def majordomoPodYaml = """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: majordomo
    image: ${GAR_REPO}/minordomo-image:latest
    command: [cat]
    tty: true
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
"""

timestamps {
    try {
        podTemplate(yaml: workerPodYaml) {
            node(POD_LABEL) {
                stage(agentStageName) {
                    timeout(time: 120, unit: 'MINUTES') {
                        withCredentials([
                            string(credentialsId: 'claude-code-oauth-token', variable: 'CLAUDE_CODE_OAUTH_TOKEN'),
                            usernamePassword(credentialsId: 'github-app',   usernameVariable: 'GH_APP_USR',    passwordVariable: 'GH_APP_PSW'),
                        ]) {
                            checkout scm
                            container('worker') {
                                sh """
                                    set -euo pipefail

                                    source shared/bootstrap.sh ${AGENT_MODE}

                                    { bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
                                    CLAUDE_EXIT=0
                                    claude -p "\$(cat ${agentPromptPath})" --output-format json \\
                                      > /tmp/claude-output.json || CLAUDE_EXIT=\$?

                                    bd dolt pull && bd dolt push
                                    python3 ../shared/report-token-usage.py /tmp/claude-output.json 2>&1 | tee /tmp/prompt-output.txt || true
                                    exit \$CLAUDE_EXIT
                                """
                                def output = sh(
                                    script: 'cat /tmp/beads-output.txt /tmp/prompt-output.txt 2>/dev/null || true',
                                    returnStdout: true
                                ).trim()
                                if (output) currentBuild.description = output
                                def hasErrors = sh(
                                    script: 'python3 shared/check-run-errors.py /tmp/prompt-output.txt',
                                    returnStatus: true
                                ) == 1
                                if (hasErrors) currentBuild.result = 'FAILURE'
                            }
                        }
                    }
                }
            }
        }

        podTemplate(yaml: majordomoPodYaml) {
            node(POD_LABEL) {
                stage('Beads Status') {
                    timeout(time: 5, unit: 'MINUTES') {
                        withCredentials([
                            usernamePassword(credentialsId: 'github-app',   usernameVariable: 'GH_APP_USR',    passwordVariable: 'GH_APP_PSW'),
                        ]) {
                            checkout scm
                            container('majordomo') {
                                sh '''
                                    set -euo pipefail
                                    source shared/setup-env.sh

                                    gh auth setup-git
                                    [ -d .beads ] && chmod 700 .beads
                                    bd bootstrap
                                    bd dolt show
                                    bd dolt pull
                                    { bd stats && echo "---" && bd list; } | tee /tmp/beads-output.txt
                                '''
                                def beadsOutput = sh(
                                    script: 'cat /tmp/beads-output.txt 2>/dev/null || true',
                                    returnStdout: true
                                ).trim()
                                if (beadsOutput) {
                                    def existing = currentBuild.description ?: ''
                                    currentBuild.description = existing + (existing ? '\n\n---\n\n' : '') + beadsOutput
                                }
                            }
                        }
                    }
                }
            }
        }

    } catch (err) {
        currentBuild.result = 'FAILURE'
        throw err
    } finally {
        if (currentBuild.result == 'FAILURE') {
            notifyFailure()
        }
    }
}
