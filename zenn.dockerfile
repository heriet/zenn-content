FROM node:14.11.0-stretch-slim

WORKDIR /workspace

RUN apt update \
 && apt-get install -y --no-install-recommends \
    git \
 && apt-get -y clean \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g zenn-cli
