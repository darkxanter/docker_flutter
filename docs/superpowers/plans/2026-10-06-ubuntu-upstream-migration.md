# Ubuntu upstream migration implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver Ubuntu 24.04 Flutter images with working SQLite, JDK 21 Android builds, useful warmed caches, a web minifier, and cached, verified CI builds.

**Architecture:** Retain four Dockerfiles and their public image interfaces. Share the build dependency graph through Buildx Bake target contexts, load images locally for verification, and publish those checked images afterward. Separate runtime migration, build orchestration, and end-to-end verification into three coherent tasks.

**Tech Stack:** Ubuntu 24.04, Dockerfiles, Docker Buildx/Bake, Compose, Bash, Python 3 standard-library configuration tests, Flutter/Dart, OpenJDK 21, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-06-ubuntu-upstream-migration-design.md`

## Global constraints

- Ubuntu `24.04`; release platform `linux/amd64`.
- Image repository `xanter/flutter`; variants base, web, android, android-warmed.
- Preserve `FLUTTER_CHANNEL` and `FLUTTER_VERSION`; a supplied version takes precedence.
- Preserve full-version and major.minor release tags and the weekly stable workflow.
- Runtime account `flutter`, UID/GID `101:101`, home `/home`, with passwordless sudo.
- `FLUTTER_HOME` / `FLUTTER_ROOT=/opt/flutter`, `PUB_CACHE=/var/tmp/.pub_cache`, `ANDROID_HOME=/opt/android`.
- Working directories: base/android `/home`; web/warmed `/`.
- `openjdk-21-jdk-headless`; `JAVA_HOME=/usr/lib/jvm/java-21-openjdk`; Gradle `8.5+` and compatible AGP.
- Android command-line tools `11076708`; default platform `36`, build-tools `36.0.0`; warmed inherits the selected platform.
- SQLite CLI and a system library loadable as `libsqlite3.so`.
- Minify `2.24.19`, Linux amd64 archive SHA-256 `4439d43ec2c80142d91db7fd2228afe1e2e272f211d2aeb9cd9187a2e5885b5d`.
- Keep existing Make target and Compose service names; preserve usable warmed Gradle caches.
- Do not modify project Gradle wrappers, user-owned `dockerfiles/index/`, or other unrelated local files.
- The user requested a Git commit after implementation. Remote publication requires a separate request.

## Review focus

1. A channel advances while cached layers exist: source revision must invalidate the SDK layer and be checked against the actual checkout.
2. Version and channel are both supplied, or a prerelease is supplied: select one SDK/tag consistently and do not create a misleading major.minor release alias.
3. Local builds use a different repository/tag: dependent images must consume this run's parent targets rather than old public images.
4. A root-owned, writable checkout enters a non-root build: reproduce the mtime constraint and document Runner-side ownership handling accurately.
5. Warmup completes but cleanup removes dependencies or leaves locked/root-owned caches: retain usable caches and prove access under UID 101 after cleanup.

The checks for these conditions belong to the tasks below. A full GitLab Runner execution is not available locally.

## File responsibilities

| Files | Responsibility |
| --- | --- |
| `dockerfiles/flutter.dockerfile` | Ubuntu runtime, user, SQLite, Flutter SDK initialization and universal cache |
| `dockerfiles/flutter_android.dockerfile` | Native JDK 21 and parameterized Android SDK |
| `dockerfiles/flutter_android_warmed.dockerfile` | Additional platforms, release build, retained Gradle caches |
| `dockerfiles/flutter_web.dockerfile` | Flutter web artifacts and pinned minify CLI |
| `.dockerignore`, `.gitignore` | Minimal build context and allow-list for new tracked shell tools |
| `docker-bake.hcl`, `docker-compose.yml`, `Makefile` | Shared image graph, arguments, tags, and existing local entrypoints |
| `tools/image.sh` | Resolve validated SDK inputs/revision and orchestrate build, push, and printed build configuration |
| `.github/workflows/build_and_publish_branches.yml`, `.github/workflows/build_and_publish_tag.yml` | Cached build, verification, then publication |
| `tests/test_build_configuration.py` | Black-box resolution, Bake graph/tag, and Make command checks |
| `tests/fixtures/smoke/{pubspec.yaml,lib/model.dart,test/smoke_test.dart}` | Real SQLite and generated-code integration fixture |
| `tools/verify_images.sh` | Runtime checks against built images and web build verification |
| `README.md`, `tools/build_demo_android.sh` | Supported usage, runner integration, and existing demo helper alignment |

## Task 1: Migrate the four runtime images together

**Consumes:** Existing Dockerfiles, approved spec, Flutter selection arguments.

**Produces:** Four buildable Dockerfiles, with dependent images accepting `BASE_IMAGE`; base additionally accepts optional `FLUTTER_REVISION` and `UBUNTU_VERSION=24.04`.

- [ ] Rewrite the base around Ubuntu packages and a real `flutter` account. Check UID/GID availability explicitly and fail descriptively on collision. Install runtime tools, sudo, SQLite CLI and its unversioned FFI library; keep SDK/cache ownership at 101:101. Remove the Alpine glibc overlay and dependency-tree copies.
- [ ] Initialize Flutter under UID 101, retain SDK Git metadata/templates, disable analytics/animations, and precache universal artifacts. Select version before channel, default to stable when both are empty, and validate an optional resolved revision against the checkout. Add OCI labels pointing to `darkxanter/docker_flutter`, preserving `family=xanter/flutter`.
- [ ] Move the Android SDK preparation stage to Ubuntu, install JDK 21 headless in both Android stages, and create the stable `JAVA_HOME` link to the packaged JDK. Use command-line tools `11076708`; install the selected platform/build-tools and Android Flutter artifacts in the regular image. Retain Android SDK aliases used by existing consumers.
- [ ] Adapt warmed to inherit the new Android image and run its release build for `android-arm,android-arm64,android-x64`. Stop daemons, remove only the demo and disposable lock/daemon files, retain Gradle wrapper/dependency caches, and record SDK inventory.
- [ ] Add checksum-verified minify `2.24.19` to web and precache its Flutter artifacts. Retain each variant's runtime user and working directory. Add `.dockerignore` covering repository/editor/index/generated state while keeping required build inputs.

**Verification:** Use the single complete build in Task 3 after the build graph is ready. Do not perform a knowingly incomplete transition build or rebuild all images once per Dockerfile. Existing Alpine APK/SQLite results are characterization evidence only.

## Task 2: Wire cached local and CI builds to one graph

**Consumes:** Task 1's Dockerfiles and `BASE_IMAGE`/`FLUTTER_REVISION` interfaces.

**Produces:** `tools/image.sh {resolve|print|build|push}`, invoked through existing Make targets; Bake targets `base`, `web`, `android`, `android-warmed`, default group containing all four.

- [ ] Add `tests/test_build_configuration.py` using Python unittest and actual `make -n` / `docker buildx bake --print` output. Use `test_local_parent_contexts`, `test_version_precedence`, `test_prerelease_has_no_release_alias`, `test_channel_revision_reaches_base`, and `test_invalid_inputs_fail_before_build`. Supply explicit revisions to keep configuration tests independent of the network. Assert per-variant cache scopes and linux/amd64 in addition to the following contracts:

  ```python
  # config is parsed from real tools/image.sh print output for version 3.35.7.
  assert config['target']['android']['contexts']['flutter-base'] == 'target:base'
  assert config['target']['web']['contexts']['flutter-base'] == 'target:base'
  assert config['target']['android-warmed']['contexts']['flutter-android'] == 'target:android'
  assert set(config['target']['base']['tags']) == {
      'localhost/flutter-ubuntu-check:3.35.7', 'localhost/flutter-ubuntu-check:3.35'
  }
  # Repeat with both version/channel supplied: version still selects these tags.
  # With 3.36.0-0.1.pre: exactly its full tag, with no 3.36 alias.
  # With stable and two distinct supplied revisions: base args match each revision.
  ```

  Run these new behavior checks before implementing orchestration and record the unsupported graph/input behavior, then complete production and test consumers together.
- [ ] Implement `tools/image.sh` input validation and reference resolution. Inputs are `FLUTTER_VERSION`, `FLUTTER_CHANNEL`, optional `IMAGE_REPOSITORY` (default `xanter/flutter`), and optional `FLUTTER_REVISION`. Resolve missing revision with Git against the selected Flutter ref; handle annotated tags correctly. `resolve` emits shell-safe `KEY=value` records for CI without executing user-provided text. `print` emits Bake JSON; `build` loads the full graph; `push` pushes only the selected graph's checked local tags, never `--all-tags`.
- [ ] Implement `docker-bake.hcl`: web/android use context `flutter-base=target:base`, warmed uses `flutter-android=target:android`; set their `BASE_IMAGE` arguments to those context names. Expose SDK and repository arguments. Enable separate GHA v2 cache scopes `flutter-base`, `flutter-web`, `flutter-android`, `flutter-android-warmed` only when `CI_CACHE=true`; local builds need no GitHub credentials. Use exact source revision for SDK cache freshness.
- [ ] Adapt Make and Compose to those contracts, retaining current target/service names. Keep the Make default as help. Align demo/shell execution with the non-root runtime and existing cache paths. Add narrow `.gitignore` exceptions for tracked scripts rather than removing the repository's blanket script-ignore rules.
- [ ] Update both workflows with `actions/checkout@v4`, `docker/setup-buildx-action@v3` and `docker/bake-action@v6` to load images with authenticated GHA caching, then call `tools/verify_images.sh`, then log in with `docker/login-action@v3` using existing DockerHub secrets and publish through `make push`. Keep weekly stable and manual version entrypoints. Pass event input via environment variables, not interpolated shell code. Add workflow concurrency to prevent overlapping jobs overwriting the same release aliases.
- [ ] Run `python3 -m unittest discover -s tests -p 'test_*.py'`; expect all graph/tag/input tests to pass. Run `docker compose config` and workflow validation with `actionlint`; address errors in changed configuration.

**Environment note:** The current `docker buildx version` command reports Buildah, because local Docker is a Podman shim. Actual Bake validation requires a real Docker CLI/Buildx and a compatible builder. Prepare an isolated verification toolchain; do not treat Podman build success as evidence that Bake works, or weaken the graph checks to accommodate the shim.

## Task 3: Verify production composition and document the result

**Consumes:** The image graph, resolved inputs/tags, and locally loaded images from Tasks 1–2.

**Produces:** `tools/verify_images.sh IMAGE_REPOSITORY IMAGE_TAG`, checked Ubuntu images, updated README and compact final checkpoint.

- [ ] Add the Flutter smoke fixture: Dart SDK constraint `>=3.7.0 <4.0.0`, Flutter SDK, sqlite3 `2.9.4`, json_annotation `4.9.0`, build_runner `2.4.15`, json_serializable `6.9.5`, and flutter_test. Its two tests assert an actual in-memory SQLite insert/select and the generated JSON codec round trip; no package-list snapshots.
- [ ] Implement the image verification script. Run fixtures in disposable writable directories as image-default user; assert Ubuntu 24.04, UID/GID 101, expected HOME/cache paths, SQLite CLI and FFI. Generate the fixture lockfile once, then run `flutter pub get --enforce-lockfile`, `flutter pub run build_runner build --delete-conflicting-outputs`, and `flutter test --no-pub --test-randomize-ordering-seed random`; compare lockfile bytes afterward.
- [ ] In the ownership regression, make only the disposable fixture checkout root-owned and writable, force an old lockfile mtime, and assert the reported failure; restore ownership and assert the command succeeds. This diagnoses the Runner boundary and does not add a checkout-chown requirement to production jobs.
- [ ] Assert Android `java`/`javac` are 21 and Flutter selects `JAVA_HOME`. In warmed, assert the dependency and wrapper caches survived cleanup, are readable/writable by UID 101, and cached Gradle runs `--version`. Treat the actual release APK build during image creation as the APK verification; do not repeat it solely for a checkpoint.
- [ ] Create and release-build a real web fixture. Verify `minify --version`, reduce an HTML sample while preserving its text content, and run minify on the generated entry page without changing unrelated assets.
- [ ] Run the canonical image verification once on the coherent worktree:

  ```sh
  make build FLUTTER_VERSION=3.35.7 IMAGE_REPOSITORY=localhost/flutter-ubuntu-check
  bash tools/verify_images.sh localhost/flutter-ubuntu-check 3.35.7
  ```

  Expected: all four images load, the warmed release build completes, both Flutter smoke tests pass, web build/minification pass, runtime and cache assertions pass. Re-run only invalidated checks after fixes.

- [ ] Update README with Ubuntu/apt migration, non-root identity and paths, image variants, JDK21/Gradle8.5+, SQLite/minify, local build/push/demo commands, and `FF_DISABLE_UMASK_FOR_DOCKER_EXECUTOR: "true"` under GitLab `variables`. Explain Runner configuration precedence and the Docker executor requirement.
- [ ] Review the final diff and run `git diff --check`. Request one final read-only review of the coherent changes, resolve evidenced findings, and update the checkpoint with exact commands, checked image IDs/worktree state, remaining limitations, and review outcome. Do not publish or commit without a user request.

## Current checkpoint

- Approved: spec, plan, and inline execution; baseline `fdc8411`, upstream `a232440`.
- Workspace ruling: work in the existing checkout on branch `ubuntu-upstream-migration`, retaining the approved untracked documents and user index; this avoids moving user work or adding another approval round. Commit now requested; no publication.
- Pre-flight: Task 1 BASE_IMAGE interfaces match Task 2 named contexts; Task 2 repository/tag outputs match Task 3 verification inputs.
- Completed: four Ubuntu Dockerfiles, Bake graph, shared image tool, Make/Compose wiring and runtime acceptance.
- New orchestration tests: observed RED on the absent image tool/old Make wiring; GREEN 10/10 with real Docker Buildx; Compose config passed.
- Toolchain: isolated `flutter-migration-tools` container supplies Docker CLI 28.5.2 and real Buildx against rootless Podman's API; builder `flutter-migration-check` bootstrapped successfully. This resolves the local Buildah alias limitation without changing host configuration.
- Completed edits: CI now resolves source, loads Bake targets, verifies images, then publishes explicit tags. Real SQLite/codegen fixtures and image verification script added; README documents Ubuntu, cache behavior, and GitLab's non-root ownership flag.
- Static evidence: shell syntax checks and 10/10 configuration tests passed; Compose validation and actionlint 1.7.7 passed; tracked diff whitespace check passed.
- Full Bake build: `make build FLUTTER_VERSION=3.35.7 IMAGE_REPOSITORY=localhost/flutter-ubuntu-check` exited 0. IDs: base `893b1b1e5798`, web `a262cb44d45e`, Android `93e107abaa12`, warmed `cbaefa2aee6c`. `.superpowers/ubuntu-migration/build.log` and `build.exit` contain evidence; warmed release APK succeeded (41.3 MB, Gradle 8.12).
- Runtime checks: `bash tools/verify_images.sh localhost/flutter-ubuntu-check 3.35.7` exited 0; `.superpowers/ubuntu-migration/verify.log` and `verify.exit`. Both Flutter tests passed, ownership failure reproduced then resolved in the disposable fixture, lockfile unchanged, Android toolchain recognized JDK 21.0.12.1, Gradle caches survived cleanup, web/minify passed.
- Observed diagnostics: the Kotlin daemon retried startup before the successful APK build. The specified upstream command-line tools version warns about SDK XML v4 when listing newer AGP-installed components; installation, inventory generation, and runtime checks still succeeded. Doctor reports the intentionally absent Chrome/Linux desktop/Android Studio and detached Flutter version checkout.
- Task 1: complete; Task 2: complete (local graph/static workflow verification); Task 3: complete. Live GitHub/GitLab execution and remote publication were not performed.
- Final independent review: Ready, no Critical/Important/Minor findings. Baseline diff supplied at `.superpowers/ubuntu-migration/review.diff`; the initial missing-diff evidence gap was closed in the same reviewer session. The subsequent user edit is covered by the scoped verification below.
- Cleanup: temporary Buildx builder and CLI container removed; checked local images and evidence logs retained.
- Commit preparation: preserved the user's removal of explicit platforms 28–35 from warmed after review and aligned documentation/runtime assertion to the inherited platform. Original base/web/Android evidence remains applicable.
- Final warmed state: rebuilt `dockerfiles/flutter_android_warmed.dockerfile` with Podman against checked parent `localhost/flutter-ubuntu-check:3.35.7-android`; image `fcf746859c61`, release APK 41.3 MB. `warmed-final-build.log/.exit` under the same evidence directory record exit 0. The warmed runtime assertions (UID, retained/writable/owned caches, cached Gradle, inherited platform, SDK inventory) and absence of Android 28 passed; `warmed-final-check.log/.exit` record exit 0. Shell syntax and diff whitespace checks passed.
