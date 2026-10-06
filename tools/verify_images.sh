#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

repository=${1:?Usage: verify_images.sh IMAGE_REPOSITORY IMAGE_TAG}
tag=${2:?Usage: verify_images.sh IMAGE_REPOSITORY IMAGE_TAG}

docker run --rm -i --volume "$PWD/tests/fixtures/smoke:/fixture:ro" "$repository:$tag" bash -euo pipefail -s <<'BASE'
source /etc/os-release
test "$ID:$VERSION_ID" = ubuntu:24.04
test "$(id -u):$(id -g)" = 101:101
test "$HOME" = /home
test "$FLUTTER_HOME:$PUB_CACHE" = /opt/flutter:/var/tmp/.pub_cache
test -w "$FLUTTER_HOME/bin/cache"
test -w "$PUB_CACHE"
test "$(sqlite3 :memory: 'SELECT 42;')" = 42
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R /fixture/. "$work"
cd "$work"
flutter pub get
sha256sum pubspec.lock > lock.sha256

# Exercise the GitLab helper/job ownership boundary on a disposable checkout.
sudo chown root:root pubspec.lock
sudo chmod 666 pubspec.lock
sudo touch -t 200001010000 pubspec.lock
if flutter pub run build_runner build --delete-conflicting-outputs > ownership.log 2>&1; then
    printf 'Expected root-owned lockfile mtime update to fail\n' >&2
    exit 1
fi
grep -F 'Failed to set file modification time' ownership.log
sudo chown "$(id -u):$(id -g)" pubspec.lock

flutter pub get --enforce-lockfile
flutter pub run build_runner build --delete-conflicting-outputs
flutter test --no-pub --test-randomize-ordering-seed random
sha256sum --check lock.sha256
BASE

docker run --rm -i "$repository:$tag-android" bash -euo pipefail -s <<'ANDROID'
test "$(id -u):$(id -g)" = 101:101
test "$(readlink -f "$(command -v java)")" = "$(readlink -f "$JAVA_HOME/bin/java")"
java -version 2>&1 | grep -E 'version "21\.'
javac -version | grep -E '^javac 21\.'
test -d "$ANDROID_HOME/platforms/android-$ANDROID_PLATFORM_VERSION"
test -d "$ANDROID_HOME/build-tools/$ANDROID_BUILD_TOOLS_VERSION"
doctor=$(flutter doctor -v)
printf '%s\n' "$doctor"
grep -F '[✓] Android toolchain' <<< "$doctor"
grep -F "Java binary at: $JAVA_HOME/bin/java" <<< "$doctor"
ANDROID

docker run --rm -i "$repository:$tag-android-warmed" bash -euo pipefail -s <<'WARMED'
test "$(id -u):$(id -g)" = 101:101
test ! -d /home/warmup
test -d /home/.gradle/caches/modules-2/files-2.1
test -w /home/.gradle/caches/modules-2/files-2.1
test -z "$(find /home/.gradle ! -user flutter -print -quit)"
test -z "$(find /home/.gradle -type f -name '*.lock' -print -quit)"
gradle=$(find /home/.gradle/wrapper/dists -type f -path '*/bin/gradle' -print -quit)
test -n "$gradle"
"$gradle" --version
test -d "$ANDROID_HOME/platforms/android-$ANDROID_PLATFORM_VERSION"
test -s /home/sdkmanager-list-installed.txt
WARMED

docker run --rm -i "$repository:$tag-web" bash -euo pipefail -s <<'WEB'
test "$(id -u):$(id -g)" = 101:101
minify --version
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
flutter create --project-name web_smoke --platforms web "$work/app"
cd "$work/app"
flutter build web --release
test -s build/web/main.dart.js
minify --output "$work/index.html" build/web/index.html
test -s "$work/index.html"
printf '<!doctype html>\n<!-- removable comment -->\n<html><body><p>Smoke</p></body></html>\n' > "$work/sample.html"
minify --output "$work/minified.html" "$work/sample.html"
grep -F Smoke "$work/minified.html"
if grep -F 'removable comment' "$work/minified.html"; then exit 1; fi
test "$(wc -c < "$work/minified.html")" -lt "$(wc -c < "$work/sample.html")"
WEB

printf 'Verified %s:%s: SQLite, code generation, JDK, warmed caches and web build\n' "$repository" "$tag"
