# syntax=docker/dockerfile:1
# Adapted from PlugFox/docker_flutter (MIT); see LICENSE.
ARG FLUTTER_CHANNEL=""
ARG FLUTTER_VERSION=""
ARG BASE_IMAGE=xanter/flutter:${FLUTTER_VERSION:-${FLUTTER_CHANNEL:-stable}}
FROM ${BASE_IMAGE} AS production

USER root
RUN set -eux; \
    curl --fail --location --retry 3 \
        https://github.com/tdewolff/minify/releases/download/v2.24.19/minify_linux_amd64.tar.gz \
        --output /tmp/minify.tar.gz; \
    printf '%s\n' '4439d43ec2c80142d91db7fd2228afe1e2e272f211d2aeb9cd9187a2e5885b5d  /tmp/minify.tar.gz' \
        | sha256sum --check; \
    tar -xzf /tmp/minify.tar.gz -C /usr/local/bin minify; \
    chmod 0755 /usr/local/bin/minify; \
    rm /tmp/minify.tar.gz

USER flutter
RUN flutter config --enable-web && flutter precache --web

LABEL org.opencontainers.image.title="Flutter Web" \
    org.opencontainers.image.description="Ubuntu with Flutter web artifacts and minify 2.24.19"

WORKDIR /
CMD ["flutter", "doctor"]
