#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
command=${1:-}
case "$command" in
    resolve|print|build|push) ;;
    *) printf 'Usage: bash tools/image.sh {resolve|print|build|push}\n' >&2; exit 2 ;;
esac

invalid() {
    printf 'Invalid %s\n' "$1" >&2
    exit 2
}

export FLUTTER_VERSION=${FLUTTER_VERSION:-}
export FLUTTER_CHANNEL=${FLUTTER_CHANNEL:-}
export FLUTTER_URL=${FLUTTER_URL:-https://github.com/flutter/flutter.git}
export FLUTTER_REVISION=${FLUTTER_REVISION:-}
export IMAGE_REPOSITORY=${IMAGE_REPOSITORY:-xanter/flutter}
export CI_CACHE=${CI_CACHE:-false}

if [[ -n "$FLUTTER_VERSION" ]]; then
    [[ "$FLUTTER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || invalid FLUTTER_VERSION
    FLUTTER_CHANNEL=""
else
    FLUTTER_CHANNEL=${FLUTTER_CHANNEL:-stable}
    case "$FLUTTER_CHANNEL" in stable|beta|master|main|dev) ;; *) invalid FLUTTER_CHANNEL ;; esac
fi
[[ "$IMAGE_REPOSITORY" =~ ^[a-z0-9]+([._-][a-z0-9]+)*(:[0-9]+)?(/[a-z0-9]+([._-][a-z0-9]+)*)+$ ]] || invalid IMAGE_REPOSITORY
[[ -z "$FLUTTER_REVISION" || "$FLUTTER_REVISION" =~ ^[0-9a-f]{40}$ ]] || invalid FLUTTER_REVISION
[[ "$CI_CACHE" == true || "$CI_CACHE" == false ]] || invalid CI_CACHE

export IMAGE_TAG=${FLUTTER_VERSION:-$FLUTTER_CHANNEL}
export IMAGE_MINOR_TAG=""
if [[ "$FLUTTER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IMAGE_MINOR_TAG=${FLUTTER_VERSION%.*}
fi

if [[ "$command" != push && -z "$FLUTTER_REVISION" ]]; then
    if [[ -n "$FLUTTER_VERSION" ]]; then
        ref="refs/tags/$FLUTTER_VERSION"
        refs=$(git ls-remote --exit-code -- "$FLUTTER_URL" "$ref" "$ref^{}")
    else
        ref="refs/heads/$FLUTTER_CHANNEL"
        refs=$(git ls-remote --exit-code -- "$FLUTTER_URL" "$ref")
    fi
    peeled=""
    while read -r revision name; do
        [[ "$name" != "$ref" ]] || FLUTTER_REVISION=$revision
        [[ "$name" != "$ref^{}" ]] || peeled=$revision
    done <<< "$refs"
    FLUTTER_REVISION=${peeled:-$FLUTTER_REVISION}
    [[ "$FLUTTER_REVISION" =~ ^[0-9a-f]{40}$ ]] || invalid 'resolved Flutter revision'
fi

case "$command" in
    resolve)
        printf '%s\n' "FLUTTER_VERSION=$FLUTTER_VERSION" "FLUTTER_CHANNEL=$FLUTTER_CHANNEL" \
            "FLUTTER_REVISION=$FLUTTER_REVISION" "IMAGE_REPOSITORY=$IMAGE_REPOSITORY" \
            "IMAGE_TAG=$IMAGE_TAG" "IMAGE_MINOR_TAG=$IMAGE_MINOR_TAG"
        ;;
    print) docker buildx bake --file docker-bake.hcl --print ;;
    build) docker buildx bake --file docker-bake.hcl --load ;;
    push)
        images=()
        for suffix in '' -web -android -android-warmed; do
            images+=("$IMAGE_REPOSITORY:$IMAGE_TAG$suffix")
            if [[ -n "$IMAGE_MINOR_TAG" ]]; then
                images+=("$IMAGE_REPOSITORY:$IMAGE_MINOR_TAG$suffix")
            fi
        done
        # Check the complete set before publishing its first image.
        docker image inspect "${images[@]}" > /dev/null
        for image in "${images[@]}"; do docker push "$image"; done
        ;;
esac
