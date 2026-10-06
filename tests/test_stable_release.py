import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
STABLE = "a" * 40
OTHER = "b" * 40


class StableReleaseParserTests(unittest.TestCase):
    def resolve(self, refs):
        return subprocess.run(
            [sys.executable, "tools/resolve_flutter_stable.py"], cwd=ROOT,
            input=refs, text=True, capture_output=True,
        )

    def test_selects_tag_at_stable_not_highest_unrelated_tag(self):
        result = self.resolve(
            f"{OTHER}\trefs/tags/3.50.0\n"
            f"{STABLE}\trefs/tags/3.50.0-0.1.pre\n"
            f"{STABLE}\trefs/tags/3.47.6\n"
            f"{STABLE}\trefs/heads/stable\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"3.47.6 {STABLE}")

    def test_uses_peeled_annotated_tag(self):
        result = self.resolve(
            f"{STABLE}\trefs/heads/stable\n"
            f"{OTHER}\trefs/tags/3.47.6\n"
            f"{STABLE}\trefs/tags/3.47.6^{{}}\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"3.47.6 {STABLE}")

    def test_multiple_release_aliases_use_numeric_version_order(self):
        result = self.resolve(
            f"{STABLE}\trefs/heads/stable\n"
            f"{STABLE}\trefs/tags/3.47.10\n"
            f"{STABLE}\trefs/tags/3.47.9\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), f"3.47.10 {STABLE}")

    def test_untagged_or_prerelease_only_head_fails(self):
        for tag in ("", f"{STABLE}\trefs/tags/3.50.0-0.1.pre\n"):
            with self.subTest(tag=tag):
                result = self.resolve(f"{STABLE}\trefs/heads/stable\n{tag}")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("No release tag", result.stderr)

    def test_missing_or_invalid_stable_head_fails(self):
        for refs in (f"{STABLE}\trefs/tags/3.47.6\n", "bad-hash\trefs/heads/stable\n"):
            with self.subTest(refs=refs):
                result = self.resolve(refs)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")
                self.assertIn("Missing or invalid stable branch", result.stderr)


class StableReleaseIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="flutter-release-")
        self.addCleanup(self.directory.cleanup)
        self.env = os.environ.copy()
        self.env.update(
            GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.test",
            GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.test",
            FLUTTER_URL=self.directory.name,
            FLUTTER_VERSION="3.35.7", FLUTTER_CHANNEL="beta",
            FLUTTER_REVISION=OTHER, IMAGE_REPOSITORY="localhost/flutter-check",
            IMAGE_CHANNEL_TAG="", CI_CACHE="false",
        )
        self.git("init", "--bare")
        tree = self.git("mktree", input="")
        self.revision = self.git("commit-tree", tree, "-m", "fixture release")
        self.git("update-ref", "refs/heads/stable", self.revision)
        self.git("tag", "-a", "3.47.6", "-m", "fixture release", self.revision)

    def git(self, *args, input=None):
        result = subprocess.run(
            ["git", "-C", self.directory.name, *args], env=self.env,
            input=input, text=True, capture_output=True, check=True,
        )
        return result.stdout.strip()

    def resolve(self):
        return subprocess.run(
            ["bash", "tools/image.sh", "resolve-stable"], cwd=ROOT,
            env=self.env, text=True, capture_output=True,
        )

    def test_real_git_resolution_flows_into_bake_tags(self):
        result = self.resolve()
        self.assertEqual(result.returncode, 0, result.stderr)
        values = dict(line.split("=", 1) for line in result.stdout.splitlines())
        self.assertEqual(values["FLUTTER_VERSION"], "3.47.6")
        self.assertEqual(values["FLUTTER_REVISION"], self.revision)
        self.assertEqual(values["FLUTTER_CHANNEL"], "")
        self.assertEqual(values["IMAGE_TAG"], "3.47.6")
        self.assertEqual(values["IMAGE_MINOR_TAG"], "3.47")
        self.assertEqual(values["IMAGE_CHANNEL_TAG"], "stable")

        result = subprocess.run(
            ["bash", "tools/image.sh", "print"], cwd=ROOT,
            env={**self.env, **values}, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        targets = json.loads(result.stdout)["target"]
        self.assertEqual(targets["base"]["args"]["FLUTTER_REVISION"], self.revision)
        self.assertEqual(set(targets["android-warmed"]["tags"]), {
            "localhost/flutter-check:3.47.6-android-warmed",
            "localhost/flutter-check:3.47-android-warmed",
            "localhost/flutter-check:stable-android-warmed",
        })

    def test_head_without_release_tag_stops_resolution(self):
        self.git("update-ref", "-d", "refs/tags/3.47.6")
        result = self.resolve()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("No release tag", result.stderr)


if __name__ == "__main__":
    unittest.main()
