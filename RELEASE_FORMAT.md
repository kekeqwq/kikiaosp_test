# KikiAOSP system package contract — version 1 proposal

Status: implementation draft, 2026-09-30. No version-1 package has been built or accepted yet. Freeze this contract only after the first producer/consumer installation prototype passes. The existing development bundle is NOT this format.

This document belongs to `kikiaosp_test`, the producer of system installation materials. `KikiEmu` implements the reader/installer against the same versioned contract. Do not independently redefine it in the launcher repository.

## 1. Scope and immutable identities

- Product: `kikiaosp_test`; system brand: `KikiAOSP`; launcher/window/CLI: `KikiEmu`.
- First public system version: `0.1.0-alpha`. Release version and package-format version are different identifiers.
- Target: AArch64, 4-KiB guest pages, the validated Windows ARM64/Surface QEMU/WHPX/SDL/VirGL route.
- Proposed container: a single ZIP, filename `KikiAOSP-<version>-arm64.zip`, ZIP64 supported when necessary.
- Proposed package kind: `org.kiki.kikiaosp.system`; `formatVersion: 1`; disk layout `gpt-v1`; runtime ABI `kiki-arm64-whpx-virgl-gpt-v1`.
- ZIP is a distribution container, NOT a bootable whole disk or an initialized user instance.

## 2. Exact package allowlist

```text
manifest.json
payload/boot.img
payload/system.img
payload/vendor.img
provenance/source-lock.json
licenses/<component>.txt
```

`boot.img` is proposed as an Android boot-header-v4 partition payload containing the freshly built mainline kernel and complete, freshly generated KikiAOSP initramfs. It does not imply an Android phone bootloader, GKI certification or verified-boot signing. KikiEmu must explicitly parse this supported format and supply the extracted matching kernel/ramdisk to QEMU's direct boot route.

`system.img` and `vendor.img` are raw EROFS partition payloads, not Android sparse images, QCOW2 images, or whole-disk images. Their `.img` suffix does not mean a pre-created user disk is being distributed. CP2A product/system_ext contents remain inside system; do NOT include the old development compatibility disks just because they existed in a launch script.

No new required partition payload may be added silently. If the implementation proves that the proposed three payloads are insufficient, revise this DRAFT jointly before freezing version 1. Afterwards a required new payload/layout/boot format is a compatibility change.

Forbidden: GPT/MBR whole-disk images, `.qcow2`, `userdata.img`, initialized misc/metadata/empty placeholder disks, the old runtime-support tarball, accounts, Android IDs from a used instance, ADB authorized keys, app data, test APKs, photos, private logs, QEMU/Windows executables, or a nested archive of development files. Only original required system assets are published.

## 3. Required manifest semantics

The implementation must introduce a machine-readable schema and semantic validator before releasing any assets. Required records:

| Record | Meaning |
| --- | --- |
| `kind`, `formatVersion` | Exact package family and supported structural version |
| `systemVersion`, `product`, `channel` | Version, device product and `release`; not inferred from filenames |
| `architecture`, `pageSizeBytes` | AArch64 and 4096; reject incompatible targets |
| `runtimeAbi`, `minimumLauncherVersion` | Supported boot/disk/device ABI plus compatible reader version |
| `layoutVersion`, `sectorSizeBytes`, `alignmentBytes` | GPT-v1 rules, proposed 512-byte sectors and 1-MiB alignment |
| `minimumDataBytes`, partition requirements | Minimum supported capacity, established by tests, not a hardcoded 128/200-GiB choice |
| `payloads` | Required role, canonical path, image format, exact byte length, SHA-256, installed partition size constraints |
| `sourceLock` | Exact AOSP manifest and device/kernel source identities; no floating main branch as provenance |
| `buildIdentity` | KikiAOSP display version/fingerprint and release channel |
| `requiredFeatures` | Reader/runtime capabilities whose absence causes explicit rejection |

Partition names and roles, payload encodings, integer units, required keys and runtime ABI are normative after freezing. Use integer bytes internally, never localized display strings or host absolute paths. A schema alone is insufficient: check cross-field consistency, headers, checksums, installed partition bounds, total capacity and runtime ABI too.

The manifest must NOT supply arbitrary executable commands, QEMU arguments, filesystem destinations, URLs to executable dependencies, or host-specific `C:\...`/`/home/...` paths. The installed launcher translates supported ABI fields into its own protected launch configuration.

## 4. User-created disk contract

`kikiemu create --system <zip> --storage <directory> --size <capacity> --qemu <bin-directory>` creates a NEW standalone QCOW2 disk with no backing dependency on the ZIP, a developer directory, or the program installation directory. QEMU is explicitly user-provided; its validated directory binding is launcher configuration, not an executable path supplied by this manifest. Preallocation is off. The capacity is the TOTAL virtual phone storage, not just `/data`, and becomes immutable when creation succeeds.

Proposed partition labels: `boot`, `system`, `vendor`, `misc`, `userdata`. GPT headers, alignment, reserved ranges and every partition are inside the declared total. Partition sizes derive from the manifest and installation algorithm; remaining usable aligned space goes to a fresh F2FS userdata partition. If proven required, another runtime-created service partition must be declared in the jointly approved layout BEFORE version 1 freezes. Do not distribute preformatted service/user disks.

Boot/system/vendor payloads are installed into their own partitions. The launcher may derive a small, verified local direct-boot cache from the installed boot partition; this is runtime output, never a reliance on the deleted download ZIP. Cache and logs must be reported in host actual-usage accounting and cannot be presented as additional Android capacity.

Filesystem formatting must use the actual new userdata partition. Choosing 200 GiB must create a 200-GiB total disk, not an 8-GiB filesystem behind a 200-GiB image. Minimum-capacity checks occur before writes. The first-boot format/init path and recovery from an interrupted first boot need explicit verification.

CLI suffix `g` means GiB (2^30 bytes); publish this in English help. 128 and 200 are examples, not fixed presets or defaults. Guest available capacity excludes system/service partitions and filesystem overhead. Host physical use includes allocated QCOW2 clusters, metadata, cache and logs; neither exact equality with guest used bytes nor immediate space reclamation after deletion is guaranteed.

Android must report the exact TOTAL backing block-device capacity through its
storage APIs, not round it up to a physical phone's marketing tier. Settings
system/reserve usage must follow the actual installed layout/filesystems;
never fake a fixed 8/10-GB system number. This product enables
`ro.kikiaosp.exact_storage_size`; the tracked framework patch obtains the
whole parent disk size through the existing mount/vold interface. The
installer record, kernel block size, vold, StorageStats and Settings must
agree in bytes, allowing only the documented GB/GiB display-unit conversion.

Changing virtual disk size, partition layout, system payloads or product identity through `set` is prohibited. A validated `set --qemu` may change the launcher runtime binding for the NEXT start, but may not change this installed disk ABI or invoke a silent migration. Detect external size/layout modification at startup and refuse to boot rather than silently repairing, resizing or formatting an established instance.

## 5. Reader and compatibility rules

- Only this exact package type is accepted; never guess a development bundle from filenames.
- Before installation, verify supported format/layout/runtime ABI, release channel, architecture, declared lengths, file hashes and capacity requirements.
- Reject missing/extra executable or disk payloads, duplicate ZIP names, absolute paths, `..`, Windows drive/UNC paths, symlinks, ambiguous case-folded names and dangerous decompression sizes. Manifest paths are canonical and archive extraction cannot escape its staging directory.
- Use a new staging location, validate first, then install transactionally. Never overwrite an existing user's storage directory or register `Created id NN` on failure.
- Persist immutable source/version/hash/layout/capacity/instance UUID separately from mutable resource settings. The installed instance does not reference Downloads.
- Verify created GPT/partition contents and virtual capacity. Actual Android `/data` size and persistence are end-to-end acceptance checks, not inferred from QCOW2 metadata.
- Publish an external ZIP SHA-256 and provenance. SHA checks detect mismatch/corruption, not a promise of publisher authentication without a signing mechanism.

## 6. Version evolution

After freeze, format 1 is immutable for breaking semantics. A system patch release retaining this ABI must still be readable by the existing compatible launcher. Never silently switch ZIP to another format, change payload paths/encodings, change roles or require new boot flags within the same contract.

A breaking change requires a new format/layout/runtime ABI as appropriate, reader support first, clear minimum-version validation and backward-compatibility fixtures. Installed users' disks are never rewritten merely because the launcher or a Release asset was updated. Keep old accepted fixtures and immutable assets available; corrections are new versions, not replacement files under an old tag.

## 7. Contract test suite to implement

Producer and consumer use the SAME schema plus golden fixtures pinned to an exact contract revision. Before each release test valid package reading, multiple supported capacities, corrupted payload, missing role, wrong boot header, unknown format/ABI, duplicate/path-traversal ZIP entries, too-small capacity, interrupted create, interrupted first boot and an externally resized disk. Both repositories' gates must reject forbidden development/user artifacts.

References: [AOSP boot image header](https://source.android.com/docs/core/architecture/bootloader/boot-image-header), [QEMU disk formats](https://www.qemu.org/docs/master/system/images.html). The GPT install/direct-boot combination is our design; its32/200-GiB development system prototypes now pass actual boot and capacity checks, documented in [GPT_STORAGE_PROTOTYPE](docs/GPT_STORAGE_PROTOTYPE.md). The public ZIP producer/consumer, clean release provenance and release/dev isolation are still pending; this format is not frozen or released yet.
