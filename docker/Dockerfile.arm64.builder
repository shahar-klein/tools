FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive
#RUN apt-get update && apt-get install -y build-essential && apt-get install -y debhelper docker-ce docker-ce-cli
RUN apt-get update && apt-get install -y build-essential && apt-get install -y debhelper
RUN curl -fsSL https://get.docker.com | sh
