FROM rockylinux:8.5
COPY epel.repo /etc/yum.repos.d/

COPY go1.19.13.linux-arm64.tar.gz /

RUN rm -rf /usr/local/go && tar -C /usr/local -xzf go1.19.13.linux-arm64.tar.gz

RUN yum group install -y "Development Tools"

RUN yum install -y git make curl pkgconfig rpm-build vim
