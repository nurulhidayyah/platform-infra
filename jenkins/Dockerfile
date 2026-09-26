# Jenkins platform: LTS resmi, ditambah Docker CLI dan plugin yang dipin.
FROM jenkins/jenkins:2.568.3-lts-jdk21

# Hanya CLI, tanpa daemon: Jenkins memakai Docker milik host lewat soket yang
# di-mount di compose. Versinya sama dengan daemon host (29.7.1).
COPY --from=docker:29.7.1-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29.7.1-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

# Kunci host GitHub yang sudah diperiksa, untuk push ke platform-gitops lewat SSH.
COPY github_known_hosts /etc/ssh/ssh_known_hosts

COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
