"""Select the release tag at stable HEAD from a git ls-remote snapshot."""

import re
import sys


def resolve_stable_release(text):
    refs = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        fields = line.split()
        if len(fields) != 2:
            raise ValueError("Malformed Git reference")
        revision, name = fields
        refs[name] = revision

    revision = refs.get("refs/heads/stable", "")
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Missing or invalid stable branch")

    versions = []
    for name, target in refs.items():
        match = re.fullmatch(r"refs/tags/([0-9]+\.[0-9]+\.[0-9]+)", name)
        if match and refs.get(f"{name}^{{}}", target) == revision:
            versions.append(match[1])
    if not versions:
        raise ValueError(f"No release tag matches stable HEAD {revision}; retry after the release is tagged")

    version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
    return version, revision


def main():
    try:
        version, revision = resolve_stable_release(sys.stdin.read())
    except ValueError as error:
        print(f"Cannot resolve Flutter stable release: {error}", file=sys.stderr)
        return 1
    print(version, revision)
    return 0


if __name__ == "__main__":
    sys.exit(main())
