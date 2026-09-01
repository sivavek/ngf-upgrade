ARG REPO
ARG JENKINS_VERSION
FROM $REPO/jenkins-master_hardened:$JENKINS_VERSION

USER root

ARG OSRC_PLUGIN_VERSION
ARG CDAAS_AGENT_SCALER_VERSION
ARG NEXUS_REPO

ENV JENKINS_STAGING=/usr/share/jenkins/ref

# Get cdaas-agent-scaller plugin
RUN mkdir $JENKINS_STAGING/plugins
RUN echo $NEXUS_REPO > /tmp/nexus_repo
RUN curl $NEXUS_REPO/io/jenkins/plugins/cdaas-agent-scaler/$CDAAS_AGENT_SCALER_VERSION/cdaas-agent-scaler-$CDAAS_AGENT_SCALER_VERSION.jpi -o $JENKINS_STAGING/plugins/cdaas-agent-scaler.jpi
RUN curl $NEXUS_REPO/io/jenkins/plugins/cdaas-agent-scaler/$CDAAS_AGENT_SCALER_VERSION/cdaas-agent-scaler-$CDAAS_AGENT_SCALER_VERSION.jpi.md5 -o $JENKINS_STAGING/plugins/cdaas-agent-scaler.jpi.md5 && \
        cd $JENKINS_STAGING/plugins && \
        echo " cdaas-agent-scaler.jpi" >> cdaas-agent-scaler.jpi.md5 && \
        md5sum -c cdaas-agent-scaler.jpi.md5 && \
        rm cdaas-agent-scaler.jpi.md5

# Get the OSRC plugin
RUN curl $NEXUS_REPO/io/jenkins/plugins/tpsd-jenkins-plugin/$OSRC_PLUGIN_VERSION/tpsd-jenkins-plugin-$OSRC_PLUGIN_VERSION.hpi -o $JENKINS_STAGING/plugins/tpsd-jenkins-plugin.jpi
RUN curl $NEXUS_REPO/io/jenkins/plugins/tpsd-jenkins-plugin/$OSRC_PLUGIN_VERSION/tpsd-jenkins-plugin-$OSRC_PLUGIN_VERSION.hpi.md5 -o $JENKINS_STAGING/plugins/tpsd-jenkins-plugin.jpi.md5 && \
        cd $JENKINS_STAGING/plugins && \
        echo " tpsd-jenkins-plugin.jpi" >> tpsd-jenkins-plugin.jpi.md5 && \
        md5sum -c tpsd-jenkins-plugin.jpi.md5 && \
        rm tpsd-jenkins-plugin.jpi.md5

# Install plugins
COPY plugins.txt.resolved $JENKINS_STAGING/plugins.txt
RUN jenkins-plugin-cli --plugin-file $JENKINS_STAGING/plugins.txt

# Groovy init scripts
COPY init.d  $JENKINS_STAGING/init.groovy.d/

# Change permissions
RUN chmod -R ugo+rw "${JENKINS_HOME}" \
    && chmod -R ugo+r "${JENKINS_STAGING}"

# Install additional tools
RUN apt-get update -y && \
    apt-get install jq -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER jenkins

# Need to override ENTRYPOINT / COMMAND as docker hardening added /bin/bash to args and just stops instantly
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/jenkins.sh"]
