# syntax=docker/dockerfile:1
# Adapted from PlugFox/docker_flutter (MIT); see LICENSE.
ARG FLUTTER_CHANNEL=""
ARG FLUTTER_VERSION=""
ARG BASE_IMAGE=xanter/flutter:${FLUTTER_VERSION:-${FLUTTER_CHANNEL:-stable}}
ARG UBUNTU_VERSION=24.04
ARG ANDROID_HOME=/opt/android
ARG ANDROID_SDK_TOOLS_VERSION=11076708

FROM ubuntu:${UBUNTU_VERSION} AS sdk
ARG ANDROID_HOME
ARG ANDROID_SDK_TOOLS_VERSION

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl unzip openjdk-21-jdk-headless; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p "${ANDROID_HOME}/cmdline-tools"; \
    curl --fail --location --retry 3 \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_SDK_TOOLS_VERSION}_latest.zip" \
        --output /tmp/android-tools.zip; \
    unzip -q /tmp/android-tools.zip -d /tmp; \
    mv /tmp/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest"; \
    rm /tmp/android-tools.zip

FROM ${BASE_IMAGE} AS production
USER root
ARG ANDROID_HOME
ARG ANDROID_SDK_TOOLS_VERSION
ARG ANDROID_PLATFORM_VERSION=36
ARG ANDROID_BUILD_TOOLS_VERSION=36.0.0

ENV ANDROID_HOME=${ANDROID_HOME} \
    ANDROID_SDK_ROOT=${ANDROID_HOME} \
    ANDROID_TOOLS_ROOT=${ANDROID_HOME} \
    ANDROID_SDK_TOOLS_VERSION=${ANDROID_SDK_TOOLS_VERSION} \
    ANDROID_PLATFORM_VERSION=${ANDROID_PLATFORM_VERSION} \
    ANDROID_BUILD_TOOLS_VERSION=${ANDROID_BUILD_TOOLS_VERSION} \
    JAVA_HOME=/usr/lib/jvm/java-21-openjdk \
    PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools"

COPY --from=sdk --chown=101:101 ${ANDROID_HOME}/ ${ANDROID_HOME}/
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openjdk-21-jdk-headless; \
    rm -rf /var/lib/apt/lists/*; \
    ln -s "$(dirname "$(dirname "$(readlink -f /usr/bin/javac)")")" "${JAVA_HOME}"

USER flutter
WORKDIR /home
RUN set -eux; \
    mkdir -p /home/.android; \
    touch /home/.android/repositories.cfg; \
    printf 'y\n%.0s' {1..100} | sdkmanager --sdk_root="${ANDROID_HOME}" --licenses; \
    sdkmanager --sdk_root="${ANDROID_HOME}" --install \
        'platform-tools' "platforms;android-${ANDROID_PLATFORM_VERSION}" \
        "build-tools;${ANDROID_BUILD_TOOLS_VERSION}"; \
    flutter config --enable-android; \
    flutter precache --android; \
    sdkmanager --list_installed > /home/sdkmanager-list-installed.txt

LABEL org.opencontainers.image.title="Flutter Android" \
    org.opencontainers.image.description="Ubuntu with Flutter, Android SDK and OpenJDK 21" \
    android.home="${ANDROID_HOME}" \
    android.platform="${ANDROID_PLATFORM_VERSION}" \
    android.build-tools="${ANDROID_BUILD_TOOLS_VERSION}"

CMD ["flutter", "doctor"]
