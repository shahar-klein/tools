
FROM rockylinux:8.5
RUN dnf install -y dnf-utils
RUN dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
RUN dnf install -y docker-ce-cli

RUN yum install -y wget

RUN wget https://go.dev/dl/go1.18.1.linux-amd64.tar.gz

RUN rm -rf /usr/local/go && tar -C /usr/local -xzf go1.18.1.linux-amd64.tar.gz

RUN yum install -y git make curl findutils

RUN yum install -y docker-ce

