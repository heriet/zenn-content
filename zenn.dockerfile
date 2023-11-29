FROM node:21.2.0-bookworm-slim

RUN apt update \
 && apt-get install -y --no-install-recommends \
    git \
 && apt-get -y clean \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g zenn-cli
