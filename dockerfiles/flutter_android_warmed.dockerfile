# syntax=docker/dockerfile:1
ARG FLUTTER_CHANNEL=""
ARG FLUTTER_VERSION=""
ARG BASE_IMAGE=xanter/flutter:${FLUTTER_VERSION:-${FLUTTER_CHANNEL:-stable}}-android
FROM ${BASE_IMAGE} AS production

USER flutter
WORKDIR /home
RUN set -eux; \
    flutter create --pub -a kotlin --project-name warmup --platforms android -t app warmup; \
    cd warmup; \
    flutter build apk --release --no-pub --shrink --target-platform android-arm,android-arm64,android-x64; \
    android/gradlew -p android --stop; \
    cd /home; \
    rm -rf warmup .gradle/daemon; \
    find .gradle -type f -name '*.lock' -delete; \
    sdkmanager --list_installed > /home/sdkmanager-list-installed.txt

LABEL org.opencontainers.image.title="Flutter Android warmed" \
    org.opencontainers.image.description="Flutter Android with SDK platforms and warmed Gradle dependencies"

WORKDIR /
CMD ["flutter", "doctor"]
