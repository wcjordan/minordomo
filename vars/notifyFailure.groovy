// Jenkins shared library function — call as notifyFailure() in post { failure { } } blocks.
// Reads GAR_HOST, GCP_PROJECT, and NOTIFICATION_EMAIL from the environment.
def call() {
    def garHost = env.GAR_HOST ?: 'us-east4-docker.pkg.dev'
    def garRepoNotify = "${garHost}/${env.GCP_PROJECT}/default-gar"
    def subject = "${env.JOB_NAME} FAILED (Build #${env.BUILD_NUMBER})"
    def body = currentBuild.description ?: "Build failed.\nURL: ${env.BUILD_URL}"
    podTemplate(yaml: """
        apiVersion: v1
        kind: Pod
        spec:
          containers:
          - name: notify
            image: ${garRepoNotify}/minordomo-image:latest
            command: [cat]
            tty: true
            resources:
              requests:
                cpu: "100m"
                memory: "256Mi"
              limits:
                cpu: "200m"
                memory: "512Mi"
    """) {
        node(POD_LABEL) {
            checkout scm
            writeFile file: 'notify-body.txt', text: body
            container('notify') {
                withCredentials([
                    string(credentialsId: 'aws-ses-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-ses-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    usernamePassword(credentialsId: 'github-app', usernameVariable: 'GH_APP_USR', passwordVariable: 'GH_APP_PSW'),
                    usernamePassword(credentialsId: 'jira-api-key', usernameVariable: 'JIRA_ACCT_USR', passwordVariable: 'JIRA_ACCT_PSW')
                ]) {
                    withEnv(["NOTIFY_SUBJECT=${subject}"]) {
                        sh '''
                            source shared/setup-env.sh
                            python3 shared/notify-failure.py \
                                --subject "$NOTIFY_SUBJECT" \
                                --body-file notify-body.txt
                        '''
                    }
                }
            }
        }
    }
}
