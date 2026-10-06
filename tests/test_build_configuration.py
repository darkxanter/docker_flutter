import json
import os
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "localhost/flutter-ubuntu-check"
REVISION = "a" * 40


class BuildConfigurationTests(unittest.TestCase):
    def invoke(self, command="print", **overrides):
        env = os.environ.copy()
        env.update(
            FLUTTER_VERSION="3.35.7",
            FLUTTER_CHANNEL="",
            FLUTTER_REVISION=REVISION,
            IMAGE_REPOSITORY=REPOSITORY,
            CI_CACHE="false",
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", "tools/image.sh", command], cwd=ROOT, env=env,
            text=True, capture_output=True,
        )

    def config(self, **overrides):
        result = self.invoke(**overrides)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)["target"]

    def test_local_parent_contexts(self):
        targets = self.config()
        self.assertEqual(set(targets), {"base", "web", "android", "android-warmed"})
        for variant in ("web", "android"):
            self.assertEqual(targets[variant]["contexts"]["flutter-base"], "target:base")
            self.assertEqual(targets[variant]["args"]["BASE_IMAGE"], "flutter-base")
        self.assertEqual(targets["android-warmed"]["contexts"]["flutter-android"], "target:android")
        for target in targets.values():
            self.assertEqual(target["platforms"], ["linux/amd64"])

    def test_version_precedence(self):
        targets = self.config(FLUTTER_CHANNEL="beta")
        for variant, target in targets.items():
            suffix = "" if variant == "base" else f"-{variant}"
            self.assertEqual(set(target["tags"]), {
                f"{REPOSITORY}:3.35.7{suffix}", f"{REPOSITORY}:3.35{suffix}",
            })
        self.assertEqual(targets["base"]["args"]["FLUTTER_VERSION"], "3.35.7")
        self.assertEqual(targets["base"]["args"]["FLUTTER_CHANNEL"], "")

    def test_prerelease_has_no_release_alias(self):
        targets = self.config(FLUTTER_VERSION="3.36.0-0.1.pre")
        self.assertEqual(targets["base"]["tags"], [f"{REPOSITORY}:3.36.0-0.1.pre"])

    def test_channel_revision_reaches_base(self):
        for revision in ("a" * 40, "b" * 40):
            with self.subTest(revision=revision):
                targets = self.config(FLUTTER_VERSION="", FLUTTER_CHANNEL="stable", FLUTTER_REVISION=revision)
                self.assertEqual(targets["base"]["tags"], [f"{REPOSITORY}:stable"])
                self.assertEqual(targets["base"]["args"]["FLUTTER_REVISION"], revision)

    def test_default_channel_is_stable(self):
        self.assertEqual(self.config(FLUTTER_VERSION="")["base"]["tags"], [f"{REPOSITORY}:stable"])

    def test_cache_scopes_are_distinct(self):
        targets = self.config(CI_CACHE="true")
        scopes = set()
        for name, target in targets.items():
            cache = target["cache-to"][0]
            self.assertEqual(cache["type"], "gha")
            self.assertEqual(cache["version"], "2")
            self.assertEqual(cache["scope"], f"flutter-{name}")
            scopes.add(cache["scope"])
        self.assertEqual(len(scopes), 4)
        for target in self.config().values():
            self.assertFalse(target.get("cache-to"))

    def test_android_version_overrides(self):
        targets = self.config(ANDROID_PLATFORM_VERSION="35", ANDROID_BUILD_TOOLS_VERSION="35.0.0")
        self.assertEqual(targets["android"]["args"]["ANDROID_PLATFORM_VERSION"], "35")
        self.assertEqual(targets["android"]["args"]["ANDROID_BUILD_TOOLS_VERSION"], "35.0.0")

    def test_invalid_inputs_fail_before_build(self):
        invalid = [
            {"FLUTTER_VERSION": "$(touch /tmp/not-allowed)"},
            {"FLUTTER_VERSION": "--help"},
            {"FLUTTER_VERSION": "", "FLUTTER_CHANNEL": "stable;true"},
            {"IMAGE_REPOSITORY": "bad repo"},
            {"IMAGE_REPOSITORY": "registry/name:tag"},
            {"FLUTTER_REVISION": "not-a-revision"},
            {"CI_CACHE": "sometimes"},
        ]
        for overrides in invalid:
            with self.subTest(overrides=overrides):
                result = self.invoke(command="resolve", **overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Invalid", result.stderr)

    def test_resolve_output_is_literal(self):
        result = self.invoke(command="resolve", FLUTTER_CHANNEL="beta")
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(values["FLUTTER_VERSION"], "3.35.7")
        self.assertEqual(values["FLUTTER_CHANNEL"], "")
        self.assertEqual(values["IMAGE_TAG"], "3.35.7")
        self.assertEqual(values["FLUTTER_REVISION"], REVISION)

    def test_make_commands_use_shared_tool(self):
        for target in ("build", "push"):
            result = subprocess.run(
                ["make", "-n", target, "FLUTTER_VERSION=3.35.7"],
                cwd=ROOT, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(f"bash tools/image.sh {target}", result.stdout)
            self.assertNotIn("--all-tags", result.stdout)


if __name__ == "__main__":
    unittest.main()
