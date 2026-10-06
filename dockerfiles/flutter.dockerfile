# syntax=docker/dockerfile:1
# Adapted from PlugFox/docker_flutter (MIT); see LICENSE.
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS production

ARG FLUTTER_HOME=/opt/flutter
ARG PUB_CACHE=/var/tmp/.pub_cache

ENV FLUTTER_HOME=${FLUTTER_HOME} \
    FLUTTER_ROOT=${FLUTTER_HOME} \
    PUB_CACHE=${PUB_CACHE} \
    HOME=/home \
    PATH="${PATH}:${FLUTTER_HOME}/bin:${PUB_CACHE}/bin"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash ca-certificates curl git unzip xz-utils zip sudo libstdc++6 \
        sqlite3 libsqlite3-dev; \
    rm -rf /var/lib/apt/lists/*; \
    if getent passwd 101 || getent group 101; then \
        echo 'UID/GID 101 is already allocated; cannot create flutter' >&2; exit 1; \
    fi; \
    groupadd --gid 101 flutter; \
    useradd --uid 101 --gid 101 --home-dir /home --no-create-home --shell /bin/bash flutter; \
    mkdir -p "${FLUTTER_HOME}" "${PUB_CACHE}" /home; \
    chown -R 101:101 "${FLUTTER_HOME}" "${PUB_CACHE}" /home; \
    printf '%s\n' 'flutter ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/flutter; \
    chmod 0440 /etc/sudoers.d/flutter

USER flutter
WORKDIR /home

ARG FLUTTER_CHANNEL=""
ARG FLUTTER_VERSION=""
ARG FLUTTER_REVISION=""
ARG FLUTTER_URL=https://github.com/flutter/flutter.git

# The resolved revision invalidates this layer when a channel advances.
RUN set -eux; \
    git clone --branch "${FLUTTER_VERSION:-${FLUTTER_CHANNEL:-stable}}" --depth 1 \
        "${FLUTTER_URL}" "${FLUTTER_HOME}"; \
    if [ -n "${FLUTTER_REVISION}" ]; then \
        test "$(git -C "${FLUTTER_HOME}" rev-parse HEAD)" = "${FLUTTER_REVISION}"; \
    fi; \
    git -C "${FLUTTER_HOME}" gc --prune=all; \
    dart --disable-analytics; \
    flutter config --no-analytics --no-cli-animations; \
    flutter precache --universal

LABEL org.opencontainers.image.title="Flutter" \
    org.opencontainers.image.description="Ubuntu 24.04 with Flutter, Dart and SQLite" \
    org.opencontainers.image.source="https://github.com/darkxanter/docker_flutter" \
    org.opencontainers.image.licenses="MIT" \
    family="xanter/flutter" \
    flutter.channel="${FLUTTER_CHANNEL}" \
    flutter.version="${FLUTTER_VERSION}" \
    flutter.revision="${FLUTTER_REVISION}" \
    flutter.home="${FLUTTER_HOME}" \
    flutter.cache="${PUB_CACHE}"

CMD ["flutter", "doctor"]
