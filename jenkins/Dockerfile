FROM jenkins/jenkins:lts-jdk21

ARG TRIVY_VERSION=0.76.2
ARG SONAR_SCANNER_VERSION=6.2.1.4610
ARG DOCKER_CLI_VERSION=27.5.1

USER root

RUN find /etc/apt -type f \( -name '*.sources' -o -name 'sources.list' \) \
        -exec sed -i 's|http://deb.debian.org|https://deb.debian.org|g' {} + \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates jq python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only (the daemon is the host's, reached through /var/run/docker.sock)
RUN curl -fsSL "https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_CLI_VERSION}.tgz" \
    | tar -xz --strip-components=1 -C /usr/local/bin docker/docker

# Trivy + its HTML report template
RUN curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin "v${TRIVY_VERSION}" \
    && mkdir -p /opt/trivy/templates \
    && curl -fsSL -o /opt/trivy/templates/html.tpl \
       "https://raw.githubusercontent.com/aquasecurity/trivy/v${TRIVY_VERSION}/contrib/html.tpl"

# SonarScanner CLI (platform-independent build, uses the JDK of the Jenkins image)
RUN curl -fsSL -o /tmp/scanner.zip \
       "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}.zip" \
    && unzip -q /tmp/scanner.zip -d /opt \
    && mv "/opt/sonar-scanner-${SONAR_SCANNER_VERSION}" /opt/sonar-scanner \
    && rm /tmp/scanner.zip

# Python tooling (ansible, lint, tests) in an isolated virtualenv
COPY requirements-ci.txt /tmp/requirements-ci.txt
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements-ci.txt \
    && mkdir -p /opt/ansible/collections \
    && /opt/venv/bin/ansible-galaxy collection install community.docker -p /opt/ansible/collections \
    && chown -R jenkins:jenkins /opt/ansible

ENV PATH="/opt/venv/bin:/opt/sonar-scanner/bin:${PATH}" \
    ANSIBLE_COLLECTIONS_PATH=/opt/ansible/collections \
    TRIVY_CACHE_DIR=/var/jenkins_home/.cache/trivy

USER jenkins

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
