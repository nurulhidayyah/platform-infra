# Jenkins platform: LTS resmi, ditambah Docker CLI dan plugin yang dipin.
FROM jenkins/jenkins:2.568.3-lts-jdk21

# Hanya CLI, tanpa daemon: Jenkins memakai Docker milik host lewat soket yang
# di-mount di compose. Versinya sama dengan daemon host (29.7.1).
COPY --from=docker:29.7.1-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29.7.1-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
