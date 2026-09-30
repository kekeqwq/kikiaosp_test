# KikiAOSP 0.1 Alpha release policy

Status: implementation draft, 2026-09-30. This records agreed release constraints and implementation gates; it is not a claim that packaging, installation or release isolation has already passed acceptance.

The user-agreed constraints (clean installation materials only, user-created immutable total capacity, English product text and safe development while releases run) are mandatory. The proposed boot/GPT encoding remains a technical draft pending prototype validation; that does not permit relaxing these constraints to ship a developer disk or postpone isolation.

## Ownership and deliverables

- `kikiaosp_test`: canonical system-package contract, device release configuration, complete initramfs/boot payload recipe, exact source lock, system-package producer/validator, and the system ZIP published to this repository's Releases.
- `kikiaosp_kernel`: reproducible mainline kernel configuration, source fetching and patches. Provide an exact source identity and kernel artifact for the system producer; users do not separately assemble kernels.
- `KikiEmu`: package consumer/installer, native ARM64 CLI and desktop entry, QEMU patches/runtime, camera bridge, Windows installer/uninstaller, runtime isolation and acceptance tests. Publish setup.exe to its Releases.
- End users download TWO project release assets: the system ZIP and setup.exe. QEMU is user-provided through required `create --qemu <bin-directory>`; the KikiEmu README documents a matching patched native ARM64 build and self-contained runtime directory. Checksums and corresponding source/provenance are additional release materials. Users do not manually assemble Android disks.
- Brand: `KikiAOSP` system and `KikiEmu` launcher/window/CLI. Self-authored new code defaults to GPL-2.0-or-later. Keep each third-party component's original licenses, notices and applicable corresponding source; GPL does not remove third-party ownership obligations. Original mascot artwork must not copy Google's Android robot/logo.

## Clean release construction

1. Freeze exact device/kernel/launcher commits and the complete pinned AOSP manifest. Do not update upstream while preparing the same candidate.
2. Use clean source checkouts or validated worktrees and independent release output directories. Apply only reviewed, tracked integration inputs and run the full audits. Existing development outputs, runtime bundles and userdata are not release inputs.
3. Freshly build the selected AOSP release product, required filesystem payloads, kernel, complete initramfs, boot payload and Windows runtime. Do not rename yesterday's binaries as clean release products. Dependency/tool caches may remain, but build inputs/output provenance must identify the actual release recipe and outputs.
4. Replace the old frozen-ramdisk/runtime-support dependency with a complete tracked generation recipe. A recipe gap is a blocker, not permission to include the old IMG/tarball.
5. Build only installation materials listed in RELEASE_FORMAT.md. Do not ship a whole disk, user filesystem, previously initialized misc/metadata disk or legacy compatibility placeholders.
6. Run package/schema/semantic allowlist validators, payload hash checks, source-lock checks and a privacy audit. Record the exact tools and final artifact hashes.

The old README's frozen bundles remain development rollback references only. No public release may be made through the old support-tarball collector path.

## Identity and release/dev isolation: REQUIRED BEFORE 0.1

| Boundary | Installed release | Development |
| --- | --- | --- |
| SDL title | `KikiEmu` with optional instance ID | `QEMU` / explicitly marked Dev |
| Guest brand/version/model | `KikiAOSP 0.1 Alpha`, release build identity | `KikiAOSP Dev`, development build identity |
| Guest serial identity | Unique `kiki-release-<instance UUID>` boot identity | Unique `kiki-dev-<instance UUID>` identity |
| Manager records | User-scoped release registry | Separate dev registry; never change release default |
| Process/runtime identity | Recorded exact EXE path, start identity, UUID and release runtime | Explicit development runtime/identity |
| ADB | Private release server/endpoint and exact instance transport | Separate server/endpoints and Dev alias |
| QEMU control | Per-instance release control endpoint | Separate development control endpoint |
| Camera/other IPC | Per-instance release namespace/endpoint | Separate development namespace/endpoint |
| Storage/logs/mutexes | Per-instance user release locations | Development-only locations and locks |

Brand fields that may safely change must change BEFORE the public build: product model/manufacturer/display version, build ID/fingerprint/channel and application/installer/window branding. Android version remains 17. Do not rename upstream Android package IDs, the `ranchu` hardware/init protocol or required HAL/service identifiers just to add branding. Device product `kikiaosp_test` remains the established build target.

A guest serial/model is NOT transport isolation. TCP `adb devices` usually shows its address/port; `adb devices -l` can expose model/product metadata. KikiEmu must use its own server and exact transport, expose an unambiguous `kikiemu adb --id NN` route, and label its own instance records/commands. A Dev guest-name suffix alone is insufficient.

Allocate collision-safe per-instance loopback endpoints or namespaced pipes; do not hardcode the developer's 5555/4447/4455 for installed users. Register endpoint ownership and bound startup retries. No global `adb kill-server`, process-name kills, unscoped `adb shell`, title-only process selection, or changing host IME/keyboard/display settings as runtime setup. Stop/control operations verify the stored process instance and control endpoint, accounting for PID reuse.

### Development while an installed release is in use

This is a permanent release invariant, not a task deferred until the first repair. An installed release is pinned to immutable OS/boot identity and the validated user-configured QEMU bin/runtime identity. Development does not read or write that release runtime, release installation directories, user disks, default-instance selection, authorized keys, mutexes or endpoint registrations. No development tool may select release targets merely because they are the only connected ADB transport or the only QEMU process.

Ship launcher-owned libraries privately. User-provided QEMU must have its required dependencies in its own validated bin/runtime directory; do not add a developer's MSYS2 DLL directory or search PATH as a fallback. Save normalized paths and pinned byte identities at create/set and revalidate before start. Building/installing a Dev QEMU uses a separate output directory, never updates a running installed release or its configured runtime. Installing a future launcher release must not replace it; existing instances retain their compatible binding until explicit `set --qemu` passes validation for the next start.

Keep release/dev package channels, launch modes and registry namespaces distinct. A developer command against a release UUID/endpoint must fail closed; a debug package must not be installed by the public release path. Operations use exact UUID, executable path, process creation identity and owned control/ADB endpoints. ADB branding improves observability but is not the authority check.

Host hardware is shared: do not steal a camera, reconfigure the host audio/display/keyboard/GL driver, restart Windows or exhaust host resources as an automatic development step while a release is in use. If a test needs a shared-device or global-driver change, stop and arrange a separate test environment or explicit user coordination. Resource contention can still affect timing; isolated namespaces alone do not promise performance isolation or immunity from host-driver failures.

Mandatory acceptance: keep release instance A running with a persistent marker/app state, then build Dev, start Dev B, change B's resource configuration, run scoped ADB and camera tests, stop/restart B and close Dev tools. Verify A's process/control identity, registry/default, disk/boot hashes where immutable, data marker, input and operation remain intact. Detect deliberate targeting mistakes and endpoint collisions and require explicit rejection. Test these boundaries whenever launcher/IPC/device-identity code changes, not only at release tagging.

Release and development channels are frozen into package/build metadata; a configuration edit cannot turn a user release into a development target. Development diagnostics must refuse release-owned instances. Test installing/running a release while launching, stopping and rebuilding Dev WITHOUT closing, changing or writing the release instance. A failure here blocks 0.1 publication; do not defer to a corrective re-release.

## Mutable vs immutable configuration

### Clean release build target and pipeline

The ordinary `kikiaosp_test_arm64_phone-cp2a-userdebug` target remains Dev.
Its optional channel property defaults to `dev`; a release target inherits
the same minimal composition, device name and boot ABI, without replacing the
ordinary target. Select `kikiaosp_test_arm64_phone_release-cp2a-userdebug` ONLY
in a prepared independent source/output tree. Its model is KikiAOSP 0.1 Alpha,
channel `release`, system version `0.1.0-alpha` and explicit Android 17
fingerprint. Product properties override Android's optional defaults using
the upstream property mechanism, not edits to upstream build scripts.

After `prepare-clean-release.py` reports `CLEAN_PINNED_SOURCE_READY`, run:

```sh
python scripts/build-clean-release.py \
  --preparation /path/to/source-preparation-record \
  --kernel-repo /path/to/kikiaosp_kernel \
  --output /new/independent-aosp-output \
  --record /new/release-build-record --jobs 8
```

The pipeline rechecks the exact full-commit upstream manifest and pristine
checkout, freezes clean device/kernel commits into detached worktrees,
requires space for independent output, applies only tracked integration and
runs both integration/profile audits. It forces the pure pinned kernel
derivation to rebuild, builds system/vendor/ramdisk and host tools into the
new output, then derives boot-v4 from that output's static init and GPT fstab.
It checks the ACTUAL generated release properties and records hashes/phases.
`--resume` requires the same paths and commits and reuses only this release
output, never a development output. Interrupted integration is not blindly
reapplied. These are candidate INPUTS: packaging, source/licenses and real
system acceptance remain separate mandatory gates.

`create` requires system package, storage destination, TOTAL capacity and QEMU bin directory (`--qemu`). Performance preset is optional. After creation the capacity/layout/source identity are immutable. `set --size`, reformat, replacing the OS payload or changing partition layout is forbidden in 0.1. KikiEmu accepts `--create`/`--set` command aliases as well.

`set --default NN` changes manager selection. Resource settings such as `--mem`, `--cpus` and a validated `--performance` preset are configurable and translate to supported QEMU launch parameters. `set --id NN --qemu <bin-directory>` validates and atomically replaces the saved QEMU binding. All changes apply on the NEXT start; a running process keeps its original executable/dependencies/configuration. Reject arbitrary raw QEMU arguments and dangerous/backend/ABI overrides.

Explicit destructive lifecycle operation: `kikiemu --delete --force --id NN` (alias `delete --force --id NN`) terminates only that instance's owned QEMU/runtime, waits for exit and permanently removes its registered storage directory. It requires an explicit ID and valueless `--force` flag, with no confirmation/default-target fallback or arbitrary `--storage` override. Preflight registered UUID/channel, directory creation identity and owner marker, reject protected roots, overlaps and reparse redirects, pin paths, validate all process/endpoint ownership before terminating any, and journal outside storage. Unregister/clear the default only after deletion succeeds; preserve failed-delete recovery records. The original package, configured BYO QEMU, other instances and app installation are not deletion targets. This differs from uninstall, which keeps user disks/records. Immutable total capacity still forbids resizing/reformatting an existing instance; explicit deletion is not a size mutation or silent OS migration.

Presets preserve the same validated SDL/VirGL/120-Hz/native-resolution behavior. Proposed budgets: default 8vCPU/4GiB, medium 8vCPU/6GiB, high 10vCPU/8GiB, with host-aware validation. Do not invent additional GPUs or lower resolution to manufacture a higher FPS claim. All product-owned CLI/installer/dialog/startup messages are English.

## Publication gates

- Schema/semantic and negative package tests pass in BOTH repositories; exact contract/source revisions are recorded.
- The user owns setup.exe installation/uninstallation, PATH/shortcut and CLI create/set acceptance. The agent supplies the built candidate and documentation, runs build checks and system verification, but does not execute setup.exe or change the user's PATH. Record user acceptance separately; do not claim it as agent-tested.
- User acceptance: in a clean Windows ARM64 environment, install setup.exe, create instances at several capacities with an explicit QEMU bin path, delete the original ZIP and successfully boot via the desktop shortcut directly into the native boot console and desktop. Test valid/invalid `set --qemu`, missing/changed dependencies and next-start-only rebinding.
- Confirm actual total virtual capacity, real F2FS data capacity, sparse host usage and successful fresh initialization. Install an APK/save a photo, shut down normally, reopen, and verify persistence.
- Changing memory/CPU affects the next boot. Unsupported capacity changes and concurrent access to the same disk are refused. Double-clicking an already-running instance activates its window rather than opening a second writer.
- Native GUI/input/keyboard/Ethernet/audio/front-rear camera/Settings/files/ThemePicker/120-Hz mode regressions pass on the tested Surface. No extra console/Grab window and no silent software fallback. Keep known latency/security limits in release notes.
- Release/dev parallel-isolation tests pass, including ADB, camera conflicts, process selection and restarting Dev. If both request a physical camera, report ownership/busy instead of stealing it.
- Uninstall removes application binaries, owned PATH entry and shortcuts only; keep user disks and data by default. Reinstall can recover retained instance records.
- Explicit delete acceptance: a live target is force-stopped and only its registered storage removed; another live instance remains intact, deleting the default clears selection, and malformed paths/foreign owner markers/PID reuse/reparse redirection reject before effects. Test interrupted/partial removal retaining a recoverable record. The agent's isolated library fixtures do not replace user-owned public CLI acceptance.
- Launcher dependencies and corresponding source/license materials are complete. QEMU build/deployment and host GL prerequisites are documented and checked; do not assume the recipient has the developer's MSYS2 PATH or custom host GL installation. Uninstall does not delete user-provided QEMU.

## Version/tag/asset discipline

### Independent pinned-source preparation

`scripts/prepare-clean-release.py` prepares a NEW checkout from the baseline's
exact `repo manifest -r` project commits. It does not copy a patched source
worktree, `out/`, development images, initialized disks or the offline backup
volume. It shares Git object caches through standard `repo --reference` only.
When the frozen manifest is stored locally, relative fetch prefixes are resolved
against the ORIGINAL HTTPS manifest origin; copying `fetch=".."` unchanged to a
`file://` manifest would mistakenly fetch local filesystem repositories.

The preparation record includes original/exported manifest hashes, project
count, pinned repo-tool commit and paths. Reference shallow cutoffs may be
copied only as Git-cache metadata into NEW initialized project gitdirs borrowing
that recorded baseline; no project refs or source files are copied. Missing
objects are fetched through the explicit proxy with bounded jobs, current refs
and no tags. Final project commits and a clean upstream working tree must pass
before `clean-pinned-upstream-ready-not-built` is recorded. That status proves
source preparation only, NOT a clean built/published system package.

Example on the build machine (choose NEW paths, run inside the active build
tmux session; do not start a duplicate task):

```sh
python scripts/test-prepare-clean-release.py
python -u scripts/prepare-clean-release.py \
  --baseline /home/keke/aosp-master --checkout /home/keke/aosp-release-0.1 \
  --record /home/keke/projects/kikiaosp_test/output/release-preparation \
  --proxy http://192.168.2.2:6152 --jobs 4
```

An interrupted preparation uses the same recorded paths and `--resume`, never
a new upstream HEAD. `--repair-relative-remotes` is an explicit migration of an
unfinished older preparation only; it does not change any pinned project
commit. Build the release identity in independent output only after preparation
and integration audits pass. Do not package the preparation log or private host
addresses into a consumer system ZIP.

First version/tag: `0.1.0-alpha` / `v0.1.0-alpha`, GitHub prerelease, with system ZIP and setup.exe in the appropriate two repositories. Freeze candidate source before building; create immutable release tags only for the accepted candidate.

Draft BOTH releases first. Verify the actual uploaded downloads' hashes and perform acceptance against those exact bytes; only then publish. Never replace a published artifact's contents under the same version. Use a new version for a correction, retaining the preceding compatible release for users.

Package-format version is independent of system version; see RELEASE_FORMAT.md for ABI/backward-compatibility requirements. No automatic OS rewrite, disk resize, or runtime change to a running installed instance during development/installer update. Future upgrades require an explicit supported migration, backup and compatibility decision.
