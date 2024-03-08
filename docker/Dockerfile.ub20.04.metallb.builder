FROM ubuntu:20.04

RUN apt-get update
RUN apt-get install -y net-tools bash curl python3 wget bash strace  vim bash nginx

RUN apt-get install -y python3-pip

RUN curl -fsSL https://get.docker.com | sh

RUN pip3 install invoke semver pyyaml

COPY manifest-tool-linux-amd64 /usr/local/bin/manifest-tool

COPY Dockerfile.ub20.04.metallb.builder /Dockerfile
