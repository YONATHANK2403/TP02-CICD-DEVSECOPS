// TP02 - CI/CD + DevSecOps pipeline
// Any failing mandatory stage stops the pipeline: nothing is deployed after a failure.
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
        timeout(time: 40, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    }

    // Poll Git as a fallback; a GitHub webhook (githubPush) gives instant triggering.
    triggers {
        pollSCM('H/5 * * * *')
    }

    parameters {
        booleanParam(name: 'SIMULATE_VULNERABILITY', defaultValue: false,
                     description: 'Build the image with a known vulnerable dependency to prove that Trivy blocks the deployment')
        booleanParam(name: 'REQUIRE_APPROVAL', defaultValue: false,
                     description: 'Ask for a manual approval before the production deployment')
    }

    environment {
        APP_NAME     = 'demo-app'
        IMAGE        = "demo-app:${BUILD_NUMBER}"
        APP_PORT     = '5000'
        REPORT_DIR   = 'reports'
        BLOCK_SEVERITIES = 'CRITICAL'
        WARN_SEVERITIES  = 'HIGH'
    }

    stages {

        stage('1. Checkout Git') {
            steps {
                script {
                    def scmVars = checkout scm
                    env.GIT_BRANCH_NAME = scmVars.GIT_BRANCH ?: 'unknown'
                    env.GIT_SHORT = (scmVars.GIT_COMMIT ?: 'unknown').take(8)
                }
                sh 'mkdir -p reports/lint reports/trivy reports/connectivity'
                echo "Branch: ${env.GIT_BRANCH_NAME} | Commit: ${env.GIT_SHORT}"
            }
        }

        stage('2. Lint') {
            failFast true
            parallel {
                stage('yamllint') {
                    steps { sh 'bash scripts/lint.sh yamllint' }
                }
                stage('ansible-lint') {
                    steps { sh 'bash scripts/lint.sh ansible-lint' }
                }
                stage('pylint') {
                    steps { sh 'bash scripts/lint.sh pylint' }
                }
                stage('vault encrypted?') {
                    steps { sh 'bash scripts/lint.sh vault-check' }
                }
            }
        }

        stage('2b. Unit tests + coverage') {
            steps { sh 'bash scripts/run-tests.sh' }
        }

        stage('3. SonarQube Scan + Quality Gate') {
            steps {
                // 'SonarQube' = server name configured in Manage Jenkins > System
                withSonarQubeEnv('SonarQube') {
                    sh '''
                        set +x
                        export SONAR_TOKEN="${SONAR_TOKEN:-${SONAR_AUTH_TOKEN:-}}"
                        sonar-scanner -Dproject.settings=sonarqube/sonar-project.properties -Dsonar.projectVersion="${BUILD_NUMBER}"
                    '''
                }
            }
        }

        stage('4. Build Docker') {
            steps {
                script {
                    String reqFile = params.SIMULATE_VULNERABILITY ? 'requirements-vulnerable.txt' : 'requirements.txt'
                    if (params.SIMULATE_VULNERABILITY) {
                        echo 'SIMULATE_VULNERABILITY=true -> building with a vulnerable dependency'
                    }
                    sh """
                        docker build --pull -f app/Dockerfile \
                          --build-arg REQUIREMENTS_FILE=${reqFile} \
                          --build-arg APP_VERSION=${env.BUILD_NUMBER}-${env.GIT_SHORT} \
                          --label git.commit=${env.GIT_SHORT} \
                          -t ${env.IMAGE} -t ${env.APP_NAME}:latest app
                    """
                }
            }
        }

        stage('5. Trivy Scan') {
            steps {
                script {
                    int rc = sh(script: 'bash trivy/scan.sh "$IMAGE"', returnStatus: true)
                    if (rc == 1) {
                        error('Trivy: blocking vulnerabilities (or secrets) found -> deployment forbidden')
                    } else if (rc == 2) {
                        unstable('Trivy: HIGH vulnerabilities found (non blocking, to be fixed)')
                    } else if (rc != 0) {
                        error("Trivy: scan error (exit code ${rc}) -> failing closed")
                    }
                }
            }
        }

        stage('6. Deploy to TEST') {
            steps {
                withCredentials([file(credentialsId: 'ansible-vault-password', variable: 'VAULT_PASS_FILE')]) {
                    sh '''
                        ansible-playbook scripts/deploy.yml \
                          --vault-password-file "$VAULT_PASS_FILE" \
                          -e @vault/secrets.yml \
                          -e target_env=test -e app_image="$IMAGE"
                    '''
                }
            }
        }

        stage('7. Connectivity tests (TEST)') {
            steps {
                sh 'bash scripts/connectivity-test.sh demo-app-test "$APP_PORT" test'
            }
        }

        stage('8. Deploy to PRODUCTION') {
            when {
                expression { env.GIT_BRANCH_NAME ==~ /(origin\/)?main/ }
            }
            steps {
                script {
                    if (params.REQUIRE_APPROVAL) {
                        timeout(time: 15, unit: 'MINUTES') {
                            input message: 'All tests passed. Deploy to production?', ok: 'Deploy'
                        }
                    }
                }
                withCredentials([file(credentialsId: 'ansible-vault-password', variable: 'VAULT_PASS_FILE')]) {
                    sh '''
                        ansible-playbook scripts/deploy.yml \
                          --vault-password-file "$VAULT_PASS_FILE" \
                          -e @vault/secrets.yml \
                          -e target_env=prod -e app_image="$IMAGE"
                    '''
                }
                sh 'bash scripts/connectivity-test.sh demo-app-prod "$APP_PORT" prod'
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true, fingerprint: true
            junit allowEmptyResults: true, testResults: 'reports/junit.xml'
            publishHTML(target: [allowMissing: true, alwaysLinkToLastBuild: true, keepAll: true,
                                 reportDir: 'reports/trivy', reportFiles: 'trivy-report.html',
                                 reportName: 'Trivy Report'])
        }
        failure {
            script { notifyBuild('FAILURE') }
        }
        unstable {
            script { notifyBuild('UNSTABLE') }
        }
        success {
            echo 'Pipeline completed successfully.'
        }
    }
}

// Notification helper: webhook (Slack/Discord/Teams-compatible) when the
// 'notify-webhook-url' credential exists, otherwise reports/notifications.log only.
def notifyBuild(String status) {
    String msg = "${env.JOB_NAME} #${env.BUILD_NUMBER} ${status} (last stage: ${env.STAGE_NAME}) - ${env.BUILD_URL}"
    withEnv(["NOTIFY_STATUS=${status}", "NOTIFY_MESSAGE=${msg}"]) {
        try {
            withCredentials([string(credentialsId: 'notify-webhook-url', variable: 'NOTIFY_WEBHOOK_URL')]) {
                sh 'bash scripts/notify.sh "$NOTIFY_STATUS" "$NOTIFY_MESSAGE" || true'
            }
        } catch (err) {
            echo "Webhook credential unavailable (${err.message}) - writing to the log only"
            sh 'bash scripts/notify.sh "$NOTIFY_STATUS" "$NOTIFY_MESSAGE" || true'
        }
    }
}
