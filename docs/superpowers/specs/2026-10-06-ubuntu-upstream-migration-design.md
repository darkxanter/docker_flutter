# Ubuntu 24.04 image migration design

## Status and scope

This specification records the approved direction for bringing selected changes
from [PlugFox/docker_flutter](https://github.com/PlugFox/docker_flutter) into
this fork. The user approved migrating from Alpine to Ubuntu 24.04. This is a
design approved by the user; the implementation plan and inline execution were
subsequently approved. Remote publication requires a separate user request.

The deliverable is the existing four-image family, rebuilt on native Ubuntu
glibc: `base`, `web`, `android`, and `android-warmed`. Preserve the public image
repository `xanter/flutter`, existing Make targets and Compose service names,
and the `FLUTTER_CHANNEL` / `FLUTTER_VERSION` build interface. A specified
version takes precedence as it does today. Version builds retain full-version
and major.minor tags; channel builds retain their channel tags. Weekly stable
images remain supported. Release architecture remains `linux/amd64`.

Do not alter projects' Gradle wrappers or silently extend compatibility to old
Flutter-generated wrappers. Android use requires Gradle 8.5 or later and a
compatible Android Gradle Plugin (AGP).

## Image contracts

### Shared base and Android build stage

- Use Ubuntu 24.04 and native glibc. Install apt packages with
  `--no-install-recommends`; remove the Alpine/musl and sgerrand glibc overlay.
- Keep the `flutter` account non-root with UID/GID `101:101`, home `/home`, and
  passwordless sudo compatibility. Create the account using Ubuntu's user and
  group mechanisms, make the home and SDK/cache paths writable, and handle any
  UID/GID collision deliberately. Do not replace system `/etc` files.
- Preserve `FLUTTER_HOME` and `FLUTTER_ROOT` as `/opt/flutter`,
  `ANDROID_HOME` as `/opt/android`, and `PUB_CACHE` as
  `/var/tmp/.pub_cache`. Retain the existing working-directory contracts:
  `/home` for base and Android, `/` for web and warmed images.
- Install `openjdk-21-jdk-headless` in both the Android SDK build stage and the
  Android image. Expose `JAVA_HOME=/usr/lib/jvm/java-21-openjdk`; link this
  stable path to Ubuntu's packaged JVM location if necessary. Both `java` and
  `javac` must resolve to JDK 21.
- Provide the SQLite CLI and system library to support Dart FFI loading as
  `libsqlite3.so`. Use Ubuntu packages and ensure the unversioned library name
  is available; the exact package/link technique is an implementation choice.
- Initialize Flutter as `flutter`, disable analytics and CLI animation, and
  precache universal artifacts during image construction. Retain the Flutter
  SDK `.git` directory, templates, and tooling.

### Android variants

Use Android command-line tools version `11076708` by default. Expose build
arguments for Android SDK platform and build-tools versions, defaulting to
platform `36` and build-tools `36.0.0`. The regular Android image installs those
SDK components and performs Flutter's Android precache.

The `android-warmed` image remains a supported variant. It inherits the
platform selected by the shared arguments and performs the release demo build for
`android-arm,android-arm64,android-x64`, and records the installed SDK
inventory. Stop Gradle daemons and remove the temporary demo project and lock
files, but preserve usable Gradle wrapper and dependency caches under
`/home/.gradle`. The current cleanup discards those warmed Gradle caches;
correcting that behavior is in scope.

### Web variant

Include `tdewolff/minify` version `2.24.19`, pinned and checksum-verified (or
built from pinned source). The recorded Linux amd64 release tarball SHA-256 is
`4439d43ec2c80142d91db7fd2228afe1e2e272f211d2aeb9cd9187a2e5885b5d`. Precache
Flutter web artifacts and retain the web build support. The minifier must have
a meaningful output smoke check.

## Build, cache, and publishing interfaces

Add a `.dockerignore` that excludes `.git`, editor state, `.opencode`, the
untracked `dockerfiles/index/` artifacts, and local generated output without
excluding Docker build inputs. Add OCI source and image labels for
`darkxanter/docker_flutter` and `xanter/flutter`; retain the family label used
by Make's prune behavior.

Preserve `make build`, `make push`, `make shell`, and `make demo`, plus current
Compose service names. Dependent Dockerfiles need an explicit base-image
override so a local verification build can use locally built images rather
than requiring public pushes. Modernize the workflow around one dependency
graph (`base` → `web` / `android` → `android-warmed`). Use Buildx caching scoped
per image variant. Bake target contexts should resolve local dependencies
without requiring premature public pushes.

Keep stable and manual version entrypoints and existing DockerHub secrets.
Ensure moving Flutter channels resolve an immutable SDK revision, or otherwise
invalidate the relevant cache selectively, so cache reuse cannot freeze weekly
stable updates. Publish only tags for the intended run and only after checks
pass. This work does not include a remote image publication.

## Documentation and runner compatibility

Update the README for Ubuntu and `apt` rather than `apk`, the preserved paths,
JDK 21 / Gradle 8.5+ requirement, SQLite support, minifier, and local build
usage. Document the GitLab Docker executor variable
`FF_DISABLE_UMASK_FOR_DOCKER_EXECUTOR: 'true'` to preserve non-root behavior
without manual checkout `chown`. Explain that Runner-configured `feature_flags`
can override pipeline variables. The default user remains non-root; a root
default was not approved.

## Verification acceptance criteria

Run the following during implementation; these are acceptance criteria, not
checks performed for this design:

1. Build all four Dockerfiles for Flutter `3.35.7` on `linux/amd64`. Inspect
   Ubuntu release, default user, and SDK/cache ownership.
2. Verify SQLite CLI and run an in-memory query using Dart `sqlite3` `2.9.4`.
3. With an unchanged lockfile, run `pub get --enforce-lockfile`, build_runner,
   and `flutter test` against a fixture. Check `java`, `javac`, and Flutter's
   selected Java runtime.
4. Build the same release APK command used by the warmed image. Verify the
   warmed Gradle cache survives cleanup and remains writable by `flutter`.
5. Build a real Flutter web fixture and check minifier output.
6. Check Make/Compose/Bake dependency graphs and tag generation for both version
   and channel inputs. Validate workflow syntax and run `git diff --check`.
7. A full GitLab Runner execution is not available as an assumed check. A local
   ownership reproduction or documentation of Runner behavior is not equivalent
   to running that pipeline.

Earlier successful Alpine JDK 21 / Gradle 8.12 APK and SQLite tests are baseline
evidence only; they do not verify Ubuntu images.

## Deliberate exclusions

Do not inherit upstream's JDK 17 choice, removal of the warmed variant, or
replacement of this fork's image names and build arguments. The upstream Linux
desktop image, ARM publication, GHCR, root default, and broad copies of `/usr/lib`
or `/etc` are outside scope. Do not make changes to project Gradle wrappers.

## Baseline and references

- Local baseline: `fdc8411` (`jdk 21`), preceded by `56af164`
  (`add sqlite and android-36`). The current Android image uses Alpine 3.19,
  JDK 21, and the warmed variant currently deletes `.gradle` after its build.
- Selected upstream reference: `PlugFox/docker_flutter` branch `master`,
  inspected at `a232440` (December 5, 2025). Its Ubuntu migration and selected
  build/workflow improvements inform this design; fork-specific contracts above
  take precedence.
- Minifier release reference: GitHub latest-release API, version `2.24.19`,
  dated October 3, 2026; checksum recorded above.
