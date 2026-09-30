# Source-built direct-boot prototype

Status: development prototype, tested on Windows ARM64 on 2026-09-30. This is
not the public format-1 package or a clean release build certification.

The old frozen ramdisk contains a Cuttlefish recovery userspace and historical
fstab/linker/policy files. The new [recipe](../scripts/build-boot-payload.py)
does **not** extract or use that ramdisk/support archive. It stages the current
product's statically linked AArch64 first-stage init, empty mount points and
the tracked hardware fstab, then runs AOSP mkbootfs, deterministic gzip and
mkbootimg (header version 4).

```bash
cd ~/projects/kikiaosp_test
python3 scripts/build-boot-payload.py \
  --aosp ~/aosp-master \
  --kernel ~/projects/kikiaosp_kernel/result/boot/kernel \
  --output "$PWD/output/boot-prototype-new"
```

Build the corresponding product ramdisk/static init and host mkbootfs/mkbootimg
first. OUT_DIR is honored; a relative OUT_DIR is relative to the AOSP root.
The output must be a new directory. An optional `--fstab` must point to a
tracked recipe in this repository, not an arbitrary recovered file.

The direct-boot command must include `androidboot.hardware=ranchu` and
`androidboot.force_normal_boot=1`. Static init switches into
`/first_stage_ramdisk`, reads `/system/etc/fstab.ranchu`, mounts the real system
partition and switches into its system-as-root filesystem. Second-stage init,
bootstrap linker, SELinux policy, APEX and Android userspace come from that
matching system image, not a fabricated linker configuration in the ramdisk.

## Observed results

- Static init input SHA-256:
  `39883702949b4fd72cd1c2b1cc4c67f91797ba2ae2a50408f42ef12b5430444a`.
- Generated initramfs: 1,508,859 bytes,
  SHA-256 `a1d53d582ef27ea112721c389470c0827d0ffef708e3d0bf5299b12de4641089`.
- Boot-header-v4 image: 37,130,240 bytes,
  SHA-256 `19b4ec76f8fb2723c1339394d0acfe37cd600c95edd0a48f3ec373b4b871be13`.
- Same recipe/input files repeated into another new directory produced both
  byte-identical outputs. This establishes repeatability for these inputs,
  not reproducibility of the whole AOSP build across machines.
- Windows full-system boot: Android 17, Linux 7.3.0-rc4-4k,
  `sys.boot_completed=1`, 1003x1556, VirGL GLES3.1 and 120-Hz active mode;
  native boot console verified HOME and handed control to the real Android UI.
- QEMU EXE hash stayed the accepted
  `3004741332643cfd775f83ad990714716ca9975ae341f0355fda7fded4c4a651`.
  Its EXEs/DLLs were copied into a private development export. Explicit ROM
  lookup was required after relocation; no old EXE or software fallback.
- The test used the accepted development system/vendor and snapshot-only
  compatibility/data disks. It did NOT format a new user filesystem, validate
  the single GPT layout, or build a clean final system ZIP.

The first prototype deliberately omitted the host camera bridge. Opening
Camera2 therefore reported "Can't connect to the camera." This is not a
camera-accepted release configuration and must not become a public default.
The release retains the previously accepted real front/rear bridge, switching
and close-time release behavior. No camera HAL/device configuration was changed
by this prototype, and no camera regression result is claimed.

## Remaining release work

The current default fstab uses whole vda/vdb/vde devices. Implement and verify
the tracked release GPT fstab/partition discovery and truly fresh userdata
formatting before freezing format1. Generate the boot payload from the clean,
source-locked release OUT_DIR, record boot/system/vendor matching identities,
and run the public package producer/consumer checks. The prototype script alone
does not prove privacy, license completeness or clean-output provenance.

## GPT prototype checkpoint — 2026-09-30

The release implementation branch copies tracked `fstab.gpt.ranchu` into
vendor and the newly generated first-stage ramdisk. The proposed installer
creates a standalone GPT disk locally, with boot/system/vendor/misc/userdata
labels and an instance-specific boot partition UUID. No userdata/service disk
is a package payload. The old `fstab.ranchu` remains the multi-disk rollback
reference; mainline is not changed by these prototype commits.

The first native Windows installation prototype had a 32-GiB virtual capacity,
about 1.16-GiB host image length before data formatting, and successful
GPT/payload readback/QCOW2 checks. Kernel GPT parsing found vda1-vda5, but the
first Android boot failed: UUID boot detection produced an empty device name
and consequently no `/dev/block/by-name/system`. Source inspection identified
`GetBlockDeviceInfo`'s UUID branch as supporting MMC/NVME/SCSI only.

`patches/aosp-kikiaosp-init-virtio-boot-uuid.patch` adds exact virtio transport
classification to that UUID branch. It does not fall back to disk number or
classify every disk on a shared PCI/platform controller as the same device.
Both static first-stage init and second-stage init/ueventd need the patch.
The application script and integration audit include it, and
`scripts/build-gpt-prototype.sh` explicitly builds both stages plus
system/vendor/host boot tools before producing new boot materials.

This checkpoint is not proof of corrected boot, data capacity/persistence,
clean release output or source-lock/license compliance. Those gates remain
mandatory. The public package contract is still a draft. The prototype
launcher uses development endpoints; release/dev manager isolation is not
implemented merely by adding GPT or a boot UUID.
