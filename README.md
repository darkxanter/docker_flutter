# Flutter Docker images

[![Build stable](https://github.com/darkxanter/docker_flutter/actions/workflows/build_and_publish_branches.yml/badge.svg)](https://github.com/darkxanter/docker_flutter/actions/workflows/build_and_publish_branches.yml)
[![Docker Hub](https://img.shields.io/badge/Docker-Hub-2496ed.svg)](https://hub.docker.com/r/xanter/flutter/tags)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)

Ubuntu 24.04 images for Flutter and Dart, adapted from [PlugFox/docker_flutter](https://github.com/PlugFox/docker_flutter). Published images target **linux/amd64**. The stable channel is rebuilt every Monday; version builds are triggered manually.

## Image variants

| Tag | Contents |
| --- | --- |
| `<version>` or `stable` | Flutter, Dart, universal Flutter artifacts, SQLite CLI and FFI library |
| `<version>-web` | Base image, Flutter web artifacts, minify 2.24.19 |
| `<version>-android` | Base image, OpenJDK 21, Android command-line tools, platform 36 and build-tools 36.0.0 |
| `<version>-android-warmed` | Android image, SDK components and Gradle dependencies downloaded by a release demo build |

For example: `xanter/flutter:3.35.7-android-warmed`. Stable version builds also produce major.minor aliases such as `3.35-android-warmed`. Prerelease versions receive only their full version tags.

### Migration from Alpine

These images use native Ubuntu glibc. Use `apt-get` instead of `apk` when extending an image. For example:

```dockerfile
FROM xanter/flutter:stable-android
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*
USER flutter
```

## Runtime environment

The default user is `flutter` (UID/GID `101:101`), with home `/home` and passwordless `sudo`. SDK and cache directories are writable by this user.

| Variable | Value |
| --- | --- |
| `HOME` | `/home` |
| `FLUTTER_HOME`, `FLUTTER_ROOT` | `/opt/flutter` |
| `PUB_CACHE` | `/var/tmp/.pub_cache` |
| `ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_TOOLS_ROOT` | `/opt/android` (Android variants) |
| `JAVA_HOME` | `/usr/lib/jvm/java-21-openjdk` (Android variants) |

Base and Android images start in `/home`; web and warmed images start in `/`. The default command is `flutter doctor`. Its checks for desktop tools, Chrome or Android Studio can report missing components that are not included in these CI images.

### Java and Gradle

Android images use **JDK 21**. Your project's `android/gradlew` selects the Gradle version; it must be **8.5 or newer** and meet your Android Gradle Plugin's requirements. Flutter versions used to build warmed images must generate a compatible wrapper. The image does not rewrite project wrappers.

The warmed image retains its Gradle wrapper distributions and dependency cache in `/home/.gradle`. It preloads the dependencies of the generated demo, not every dependency of an arbitrary application.

### SQLite and web utilities

SQLite is available both as a CLI and as `libsqlite3.so` for Dart FFI consumers such as `sqlite3` 2.x, Drift and `sqflite_common_ffi`:

```sh
sqlite3 :memory: 'SELECT sqlite_version();'
```

Web images include a pinned, checksum-verified `minify` executable:

```sh
minify --output build/web/index.min.html build/web/index.html
```

## GitLab CI

For the Docker executor, enable Runner's ownership handling for the non-root image:

```yaml
.build:
  image: ${CI_DEPENDENCY_PROXY_GROUP_IMAGE_PREFIX}/xanter/flutter:${FLUTTER_VERSION}-android-warmed
  variables:
    FF_DISABLE_UMASK_FOR_DOCKER_EXECUTOR: "true"
```

This can also be set in top-level `variables` for all jobs. A supporting Runner uses the image user's UID/GID to adjust checkout, restored cache and artifact ownership. Values explicitly set in the Runner's `[runners.feature_flags]` configuration take precedence over pipeline variables.

This addresses pub's `Failed to set file modification time, path = 'pubspec.lock'` error when a helper-created checkout belongs to root. Write permission (`666`) alone does not let a non-owner set an explicit modification time. Set the flag as a CI/CD variable, before job preparation; an `export` in `before_script` is too late.

## Build and verify locally

Requires Docker with Buildx/Bake, Bash and Git. Build the full dependency graph and load the images into the local engine:

```sh
make build FLUTTER_VERSION=3.35.7
make check FLUTTER_VERSION=3.35.7

# Or build a moving channel, resolving its current SDK revision first:
make build FLUTTER_CHANNEL=stable
```

`FLUTTER_VERSION` takes precedence if both selectors are set; the default is `stable`. Build layers are cached. Resolving and checking the Flutter revision keeps a cached build from silently using an older channel checkout. If the channel moves between resolution and checkout, the build fails; retry to resolve its new revision.

Use `IMAGE_REPOSITORY=localhost/flutter-check` on both commands to keep verification tags separate. Dependent Dockerfiles also accept `BASE_IMAGE` for direct local builds. Configurable Android build arguments are `ANDROID_SDK_TOOLS_VERSION` (default `11076708`), `ANDROID_PLATFORM_VERSION` (`36`) and `ANDROID_BUILD_TOOLS_VERSION` (`36.0.0`). Export them in the environment before `make build` to override them.

`make check` runs SQLite/code-generation tests, verifies Java and warmed caches, and builds a web fixture. The warmed image's Docker build itself compiles a release APK for all three Android architectures. These checks require network access for fixture dependencies.

```sh
make shell FLUTTER_VERSION=3.35.7   # Mount this directory at /workspace
make demo FLUTTER_VERSION=3.35.7    # Build a disposable Android demo
make push FLUTTER_VERSION=3.35.7   # Publish only this version and its minor aliases
```

Compose 2.17+ is also supported for the stable services through `docker compose build`. For a cached Compose build of a moving channel, first resolve `FLUTTER_REVISION` using `bash tools/image.sh resolve` and export the reported revision. `make build` performs this resolution automatically.

GitHub Actions uses the same Bake graph with per-variant GHA caches. All four images are loaded and checked before Docker Hub login and publication. Existing `DOCKER_LOGIN_USERNAME` and `DOCKER_LOGIN_PASSWORD` secrets are used. Local builds do not require registry credentials or GitHub cache credentials.
