# KikiAOSP 0.1 Alpha

Version `0.1.0-alpha`, immutable tag `v0.1.0-alpha`, GitHub prerelease.

Download the [system ZIP here](https://github.com/kekeqwq/kikiaosp_test/releases/tag/v0.1.0-alpha)
and [setup.exe from KikiEmu](https://github.com/kekeqwq/KikiEmu/releases/tag/v0.1.0-alpha).
Use [the consumer guide](https://github.com/kekeqwq/KikiEmu/blob/main/QUICK_START.md).
QEMU is independently built/provided by the user. Only system installation
materials, NOT an initialized whole disk/userdata/QEMU, enter the format-1 ZIP.

## Actual shipped source identities

- ZIP: `KikiAOSP-0.1.0-alpha-arm64.zip`,834421223 bytes.
- SHA-256: `73a184068b2c1b5576add96bcbadf4621bf3c3998c7f01fffeb624ee44aad42a`.
- AOSP: `android17-release`,1084 pinned projects, manifest SHA-256
  `388a6995d81aabeda16d60b39d31cc05154b2f5389d1598fee04e4577279b598`.
- **Actual built device**: `5693f5550c09fad1581158f2ed29d91d40f02a14`.
- Pipeline tool: `d459b7f3e0106974135fc6e87c05f3d9a557e916`.
- Packaging tool: `500c49cc5cc52edf2c9fa13829574d2fb99b3545`.
- Contract: `5cfd0a94c1b267661d2ae96bdc3875365ad686cf`.
- Kernel recipe: `8984112088b8fa067fdd913950bfd76166102620`;
  Linux7.3-rc4,4KiB, image SHA-256
  `02c5439434feb3f1b5f5d63f82b2d3fbd6ccb8aa81f93d708f3d0f3bba9a7ce8`.

The release tag includes later packaging/documentation improvements and is
NOT the device commit from which the earlier system image was built. The
embedded source-lock and these actual identities are authoritative.

## Source kit and repeatable packaging

The additional source kit is not an end-user installation dependency.
`scripts/collect-release-sources.py` uses the actual ZIP/audit records, exports
manifest-pinned AOSP source archives for all17 notice-identified copyleft
component labels plus platform build/interface dependencies, includes the
actual Nix-consumed Linux source/config and exact kernel/device recipes,
and records SHA-256/commit identities. Unknown notice labels or source/audit
mismatches fail. It does not copy worktree changes, outputs, disks, logs or keys.

Follow README/RELEASE_POLICY for full pinned upstream sync, tracked integration,
`kikiaosp_test_arm64_phone_release-cp2a-userdebug`, pure kernel `nix build`, new
independent output and canonical package validation. Preserve upstream notices;
GPL on our code does not relicense all of Android. Launcher dependency/relinking
materials are separately supplied by KikiEmu.

## Evidence and known limits

Actual Windows ARM64 SDL/VirGL/120-Hz fresh32/200-GiB systems booted with
correct capacity reporting and retained data across graceful restart;200GiB
also booted after its original download path became unavailable. The final
manager update repeated a fresh32-GiB Android17/Linux7.3.0-rc4-4k HOME boot.
Its final managed-close regression passed three boots and two real SDL
close-button/reboot cycles: three camera JPEGs remained byte-identical and
decodeable without manual sync, and HOME appeared without guest input on
the second and third boots. This fix requires BOTH the final launcher and
the five-patch QEMU recipe; it does not change the clean system ZIP.
Launcher3/Settings/SystemUI, external input, Ethernet, speaker, real Surface
front/rear cameras, Gallery/DocumentsUI and ThemePicker are the accepted
baseline. Camera shared-hardware availability can change; closing the camera
releases its device. Actual runtime and user-test boundaries are recorded in
[KikiEmu's release record](https://github.com/kekeqwq/KikiEmu/blob/main/RELEASE_0_1_ALPHA.md).

The user reported successful initialization and explicitly authorized Alpha
publication on 2026-10-01 after the managed-close system regression.
The final setup/public CLI were not executed by the agent; installer/user
acceptance is not falsely claimed as developer automation. The old independent
Dev/concurrency gate was withdrawn, not passed.

GPU acceleration is implemented; prior animation tests exceeded60FPS, but
daily interaction retains noticeable latency.120Hz is a rendering mode, not
guaranteed120FPS. Other GPUs, heavy games, video recording/protected content
are not certified. Userdebug/test keys and experimental permissive policies
make this a test system, not a hardened phone. No Google services, disk resizing
or in-place OS updates. Future fixes retain format1, use a new version/new test
storage and never replace these published bytes.
