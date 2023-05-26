
FROM rockylinux:8.7
COPY epel.repo /etc/yum.repos.d/

RUN dnf install -y dnf-utils
RUN dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
RUN dnf install -y docker-ce-cli

RUN yum install -y wget
RUN yum install -y jemalloc-devel



#RUN wget https://go.dev/dl/go1.17.8.linux-amd64.tar.gz

#RUN rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.8.linux-amd64.tar.gz

RUN yum group install -y "Development Tools"

RUN yum install -y git make curl pkgconfig rpm-build vim iproute iproute-tc

RUN dnf --enablerepo=powertools install -y python3-sphinx
RUN yum install -y libcap-ng-devel openssl-devel python3-devel
RUN yum install -y selinux-policy-devel
RUN dnf --enablerepo=powertools install -y groff
RUN yum install -y desktop-file-utils
RUN yum install -y unbound unbound-devel libunwind libunwind-devel


RUN yum install -y docker-ce

