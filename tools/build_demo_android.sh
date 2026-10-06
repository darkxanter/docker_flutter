#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
flutter create --project-name demo --org dev.flutter --pub -a kotlin --platforms android "$work/demo"
cd "$work/demo"
flutter build apk --release --no-pub --shrink --target-platform android-arm,android-arm64,android-x64
