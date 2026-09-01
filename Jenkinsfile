@Library(['jenkins-shared-library', 'thor-shared-pipelines']) _

properties([
    parameters([
        string(
            defaultValue: '2.X.Y.Z',
            description: 'Jenkins master version',
            name: 'JENKINS_VERSION',
            trim: true
        ),
        [$class: 'ChoiceParameter',
        choiceType: 'PT_SINGLE_SELECT',
        description: 'CDaaS-Agent-Scaler version (fetched from Nexus, latest first)',
        name: 'CDAAS_AGENT_SCALER_VERSION',
        script: [$class: 'GroovyScript',
        fallbackScript: [classpath: [], sandbox: true, script: 'return ["Unavailable:selected"]'],
        script: [classpath: [], sandbox: true,
        script: """
def nexusUrl = "https://nexus.cdaas.umbrella.com/repository/maven-releases/io/jenkins/plugins/cdaas-agent-scaler/maven-metadata.xml"
try {
    def metadata = nexusUrl.toURL().text
    def versions = []
    metadata.eachMatch(/<version>([^<]+)<\\/version>/) { match ->
        versions.add(match[1])
    }
    versions = versions.unique().reverse()
    if (versions) {
        versions[0] = "\${versions[0]}:selected"
    }
    return versions
} catch (Exception e) {
    return ["Unavailable:selected"]
}
"""
]]],
        [$class: 'ChoiceParameter',
        choiceType: 'PT_SINGLE_SELECT',
        description: 'OpenSource Scanner Plugin version (fetched from Nexus, latest first)',
        name: 'OSRC_PLUGIN_VERSION',
        script: [$class: 'GroovyScript',
        fallbackScript: [classpath: [], sandbox: true, script: 'return ["Unavailable:selected"]'],
        script: [classpath: [], sandbox: true,
        script: """
def nexusUrl = "https://nexus.cdaas.umbrella.com/repository/maven-releases/io/jenkins/plugins/tpsd-jenkins-plugin/maven-metadata.xml"
try {
    def metadata = nexusUrl.toURL().text
    def versions = []
    metadata.eachMatch(/<version>([^<]+)<\\/version>/) { match ->
        versions.add(match[1])
    }
    versions = versions.unique().reverse()
    if (versions) {
        versions[0] = "\${versions[0]}:selected"
    }
    return versions
} catch (Exception e) {
    return ["Unavailable:selected"]
}
"""
]]],
        string(
            defaultValue: 'https://nexus.cdaas.umbrella.com/repository/maven-releases/',
            description: 'Nexus repository',
            name: 'NEXUS_REPO',
            trim: false
        ),
        string(
            defaultValue: 'https://wwwin-github.cisco.com/sto-ccc/packer-examples.git',
            name: 'PACKER_EXAMPLES_URL',
            description: 'packer-examples repo URL',
        )
    ])
])

pipeline {
    agent {
        label 'ops'
    }

    options {
        buildDiscarder(
            logRotator(
                numToKeepStr: '30',
                artifactNumToKeepStr: '0'
            )
        )
        timestamps()
        timeout(time: 90, unit: 'MINUTES')
        instanceType('t3.2xlarge')
	    instanceExecutors('1')
	    instanceCustomLabel('jenkins-image-build')
    }

    environment {
        // Settings for Corona
        CORONA_CREDENTIALS_ID = "corona-client-bot-credentials"
        ENGINEERING_CONTACT = "umbrella-thor@cisco.com"
        CORONA_PRODUCT_ID = 4822
        CSDL_ID = 56240
    }

    stages {

        stage('Checkout Repositories') {
            steps {
                checkout scm

                dir('packer-examples') {
                    git(
                        branch: 'master',
                        url: params.PACKER_EXAMPLES_URL,
                    )
                }
            }
        }

        stage('Initialize environment variables') {
            steps {
                script {
                    // Set build description
                    currentBuild.description = "Jenkins ${params.JENKINS_VERSION}"
                    
                    // Debug: Print global environment variables
                    echo "DEBUG: Global environment variables:"
                    echo "  SL_AWS_ACCOUNT: ${env.SL_AWS_ACCOUNT}"
                    echo "  ECR_NAMESPACE: ${env.ECR_NAMESPACE}"
                    echo "  SL_AWS_REGION: ${env.SL_AWS_REGION}"
                    echo "  CDAAS_ENV: ${env.CDAAS_ENV}"
                    
                    // Validate required global environment variables
                    if (!env.SL_AWS_ACCOUNT || env.SL_AWS_ACCOUNT == 'null') {
                        error("ERROR: SL_AWS_ACCOUNT is not set. Configure it in Jenkins global environment variables.")
                    }
                    if (!env.ECR_NAMESPACE || env.ECR_NAMESPACE == 'null') {
                        error("ERROR: ECR_NAMESPACE is not set. Configure it in Jenkins global environment variables.")
                    }
                    if (!env.SL_AWS_REGION || env.SL_AWS_REGION == 'null') {
                        error("ERROR: SL_AWS_REGION is not set. Configure it in Jenkins global environment variables.")
                    }
                    if (!env.CDAAS_ENV || env.CDAAS_ENV == 'null') {
                        error("ERROR: CDAAS_ENV is not set. Configure it in Jenkins global environment variables.")
                    }
                    
                    // Use plugin versions selected from ChoiceParameter
                    env.CDAAS_AGENT_SCALER_VERSION = params.CDAAS_AGENT_SCALER_VERSION
                    env.OSRC_PLUGIN_VERSION = params.OSRC_PLUGIN_VERSION

                    if (env.CDAAS_AGENT_SCALER_VERSION == 'Unavailable') {
                        error("CDAAS_AGENT_SCALER_VERSION is unavailable. Verify Nexus connectivity and retry.")
                    }
                    if (env.OSRC_PLUGIN_VERSION == 'Unavailable') {
                        error("OSRC_PLUGIN_VERSION is unavailable. Verify Nexus connectivity and retry.")
                    }
                    
                    echo "Selected plugin versions:"
                    echo "  CDAAS_AGENT_SCALER_VERSION: ${env.CDAAS_AGENT_SCALER_VERSION}"
                    echo "  OSRC_PLUGIN_VERSION: ${env.OSRC_PLUGIN_VERSION}"
                    
                    // Streamline credentials commonly used in this Jenkinsfile
                    env.STRL_CREDENTIALS_ID = "power-user-bot"
                    env.STRL_IAM_ROLE = "thor-${env.CDAAS_ENV}-ecr-power-user"

                    // ECR namespace and tags for docker images
                    env.ECR_FULL_NAMESPACE = "${env.SL_AWS_ACCOUNT}.dkr.ecr.${env.SL_AWS_REGION}.amazonaws.com/${env.ECR_NAMESPACE}"
                    env.BASE_JENKINS_IMAGE_TAG = "${env.ECR_FULL_NAMESPACE}/jenkins-master_hardened:${params.JENKINS_VERSION}"
                    env.DERIVED_JENKINS_IMAGE_TAG = "${env.ECR_FULL_NAMESPACE}/jenkins-master:${params.JENKINS_VERSION}"

                    // Split the version number into the respective components.
                    def version = (
                        params.JENKINS_VERSION =~ /^(\d+\.\d+\.\d+)\.(\d+)$/
                    )
                    if(version.hasGroup()) {
                        env.UPSTREAM_JENKINS_VERSION = version[0][1]
                    } else {
                        error(
                            "Invalid JENKINS_VERSION provided, expected format of 2.X.Y.Z"
                        )
                    }
                }
            }
        }

        stage('Validate and Resolve Plugin Versions') {
            steps {
                ansiColor('xterm') {
                    script {
                        echo "Running plugin compatibility tests (quick mode)..."
                        try {
                            sh 'QUICK_TEST=1 ./scripts/test-check-plugin-compatibility.sh'
                        } catch (Exception e) {
                            echo "test-check-plugin-compatibility.sh had issues: ${e.message}"
                            unstable("Plugin compatibility tests failed: ${e.message}")
                        }
                        
                        echo "==============================================="
                        echo "Plugin versions selected from ChoiceParameter"
                        echo "  CDAAS_AGENT_SCALER_VERSION: ${params.CDAAS_AGENT_SCALER_VERSION}"
                        echo "  OSRC_PLUGIN_VERSION: ${params.OSRC_PLUGIN_VERSION}"
                        echo "==============================================="
                        
                        echo "Resolving plugin versions for Jenkins ${env.UPSTREAM_JENKINS_VERSION}..."
                        sh """
                            ./scripts/check-plugin-compatibility.sh "${env.UPSTREAM_JENKINS_VERSION}" "plugins.txt"
                        """
                        
                        echo "Plugin version resolution completed"
                        if (fileExists('plugins.txt.resolved')) {
                            echo "Plugin versions resolved. Generated plugins.txt.resolved:"
                            sh 'cat plugins.txt.resolved'
                        } else {
                            echo "Note: plugins.txt.resolved not generated"
                        }
                    }
                }
            }
        }

        stage('Build hardened Base Jenkins') {
            steps {
                // This will create a new hardened docker image named as follows:
                // sto-ccc:ciscohardened-jenkins_<Jenkins-version>
                dir('packer-examples') {
                    sh 'ansible-galaxy install --force -r requirements.yml'
                    
                    sh """
                    packer build -color=false \
                    -var-file distros/debian13.pkrvars.hcl \
                    -var "os_family=jenkins" \
                    -var "os_distro=jenkins" \
                    -var "os_majversion=${params.JENKINS_VERSION}" \
                    -var "docker_name=jenkins-hardening-${env.BUILD_NUMBER}" \
                    -var "container_starting_image=jenkins/jenkins:${env.UPSTREAM_JENKINS_VERSION}" \
                    -var 'ansible_extra_vars_user={"ansible_remove_python": "apt-get autoremove --purge python3 -y"}' \
                    -var 'run_entrypoint=--entrypoint=/bin/sh' \
                    builders/docker-ansible.pkr.hcl
                    """
                }
            }
        }

        stage('Tag and push base image to ECR') {
            steps {
                withStreamlineAWS(accountId: env.SL_AWS_ACCOUNT,
                    credentialsId: env.STRL_CREDENTIALS_ID,
                    role: env.STRL_IAM_ROLE)
                {
                    // Tag the image
                    sh "docker tag sto-ccc:ciscohardened-jenkins_${params.JENKINS_VERSION}-x86_64 " +
                        "${env.BASE_JENKINS_IMAGE_TAG}"

                    // Get ECR login and push image
                    script {
                        login = sh(returnStdout: true, script: "aws ecr --no-include-email get-login")
                        sh "set +x; ${login}"
                        sh "docker push ${env.BASE_JENKINS_IMAGE_TAG}"
                    }
                }
            }
        }

        stage('Build derived Jenkins image') {
            steps {
                withStreamlineAWS(accountId: env.SL_AWS_ACCOUNT,
                    credentialsId: env.STRL_CREDENTIALS_ID,
                    role: env.STRL_IAM_ROLE)
                {
                    // Note, the hardened base image from the previous step is referenced in the
                    // Dockerfile being built.
                    sh """
                    docker build -t ${env.DERIVED_JENKINS_IMAGE_TAG} \
                    --build-arg JENKINS_VERSION=${params.JENKINS_VERSION} \
                    --build-arg REPO=${env.ECR_FULL_NAMESPACE} \
                    --build-arg OSRC_PLUGIN_VERSION=${env.OSRC_PLUGIN_VERSION} \
                    --build-arg CDAAS_AGENT_SCALER_VERSION=${env.CDAAS_AGENT_SCALER_VERSION} \
                    --build-arg NEXUS_REPO=${params.NEXUS_REPO} .
                    """
                }
            }
        }

        stage('Run CSE') {
            steps {
                script {
                    String image = env.DERIVED_JENKINS_IMAGE_TAG
                    ThorCredentialScanner {
                        imageName = image
                    }
                }
            }
        }

        stage("Scan with Trivy"){
            steps {
                TrivyScanner(
                    image: env.DERIVED_JENKINS_IMAGE_TAG,
                    ignoreAll: 'true'
                )
            }
        }

        stage('Run ClamAV scan') {
            steps {
                script {
                    String image = env.DERIVED_JENKINS_IMAGE_TAG

                    ThorVirusScan {
                        imageName = image
                    }
                }
            }
        }

        stage('Submit to Corona') {
            steps {

                withCredentials([[
                    $class: 'UsernamePasswordMultiBinding',
                    credentialsId: env.CORONA_CREDENTIALS_ID,
                    usernameVariable: 'CORONA_USERNAME',
                    passwordVariable: 'CORONA_PASSWORD'
                ]])
                {
                    SendToCorona(
                        username: env.CORONA_USERNAME,
                        password: env.CORONA_PASSWORD,
                        productId: env.CORONA_PRODUCT_ID,
                        csdlIdentifier: env.CSDL_ID,
                        engineeringContact: env.ENGINEERING_CONTACT,
                        image: env.DERIVED_JENKINS_IMAGE_TAG,
                        imageType: "docker"
                    )
                }
            }
        }

        stage('Audit image') {
            steps {
                script {
                    // Spin up a container that we can scan
                    String running_container_id = sh(
                        returnStdout: true,
                        script: "docker run --entrypoint /bin/bash -itd ${env.BASE_JENKINS_IMAGE_TAG}"
                    ).trim()

                    // Get a list of installed system packages
                    String docker_exec_command = 'docker exec ' + running_container_id + ' /bin/bash -c "apt list --installed"'
                    String packages = sh returnStdout: true, script: docker_exec_command

                    // Save installed system packages to a file
                    sh 'echo $(date) > CDaaS_Jenkins_docker_image_system_packages.txt'
                    sh "echo '${packages}' >> CDaaS_Jenkins_docker_image_system_packages.txt"

                    // Scan the image with docker-bench
                    CisDockerImageCheck {
                        image = running_container_id
                    }

                    // Re-name the log files and push them to Nexus
                    dir('cis-docker') {
                        sh "mv cis_docker_image_checks.sh.log CDaaS_Jenkins_docker_image.log"
                        sh "mv cis_docker_image_checks.sh.log.json CDaaS_Jenkins_docker_image.json"

                        // Upload the docker-bench reports to nexus
                         SendToNexus(
                             repositoryName: "jenkins-artifacts",
                             artifactName: "dockerbench-reports",
                             artifact: "CDaaS_Jenkins_docker_image.log",
                             artifactVersion: "${env.BUILD_ENVIRONMENT}"
                         )
                         SendToNexus(
                             repositoryName: "jenkins-artifacts",
                             artifactName: "dockerbench-reports",
                             artifact: "CDaaS_Jenkins_docker_image.json",
                             artifactVersion: "${env.BUILD_ENVIRONMENT}"
                         )
                    }
                    // Upload installed system packages to nexus
                    SendToNexus(
                        repositoryName: "jenkins-artifacts",
                        artifactName: "installed-packages",
                        artifact: "CDaaS_Jenkins_docker_image_system_packages.txt",
                        artifactVersion: "${env.BUILD_ENVIRONMENT}"
                    )
                }
            }
        }

        stage("Push derived Jenkins image to ECR") {
            steps {
                withStreamlineAWS(accountId: env.SL_AWS_ACCOUNT,
                    credentialsId: env.STRL_CREDENTIALS_ID,
                    role: env.STRL_IAM_ROLE)
                {
                    // Get ECR login and push image
                    script {
                        login = sh(returnStdout: true, script: "aws ecr --no-include-email get-login")
                        sh "set +x; ${login}"
                        sh "docker push  ${env.DERIVED_JENKINS_IMAGE_TAG}"
                    }
                }
            }
        }
    }
    post {
        failure {
            sendToWebexTeams(
                spaceId: env.WEBEX_TEAMS_SPACE_ID,
                credentialsId: 'webex-teams-bot',
                template: 'buildFailed'
            )
        }
        always {
            echo 'Terminating this Node'
            markNodeOffline()
        }
    }
}
