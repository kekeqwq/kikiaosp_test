# Fresh GPT storage system verification — 2026-10-01

Status: development-system prototype verified, NOT a clean public release,
finished ZIP contract or user CLI/installer acceptance. Stable main remains
untouched. All code is on `feat/release-0_1-alpha`.

## Tested installation materials

Device recipe commit `e7d98608bc24b9ce90421d53d2844d61e2735b07`;
native installer/core checkpoint in KikiEmu `efde7d0`.

| Material | SHA-256 |
| --- | --- |
| boot.img | `85ab546274f353e0eea87f46a75ecb6424240654d24ce7545d94d64b7da6102a` |
| system.img | `90c4698dd99dd9cdb13f6ee1048d66683436e616b35b0b4c14b4e7b93b917b8c` |
| vendor.img | `d1ded22c632cf2e6a6b01a07f102b36792aed9824a6f482d8aee10dd5ba7ac9c` |
| Linux7.3-rc4-4k kernel | `02c5439434feb3f1b5f5d63f82b2d3fbd6ccb8aa81f93d708f3d0f3bba9a7ce8` |
| Generated gzip ramdisk | `4e4f4a6d2a105dc61726372748a342e7241a47187b30c3a5a426f730de5dc756` |

These materials came from an incremental development output. They MUST NOT
be renamed as the final clean 0.1 release. Boot generation is from tracked
source/init/fstab, not the old frozen ramdisk/support bundle. Kernel, initramfs
and the accepted SDL QEMU EXE are unchanged from the corrected GPT boot.

## Whole-disk and filesystem evidence

Fresh standalone QCOW2 disks contain GPT boot/system/vendor/misc/userdata,
all inside the requested immutable TOTAL. No backing file, preallocation,
old userdata, extra compatibility disk or `-snapshot`. Boot cache is read
back and derived from the installed boot partition; the launch command does
not read the original installation materials.

| Observation | 32 GiB | 200 GiB |
| --- | ---: | ---: |
| GPT/kernel/vold/StorageStats total bytes |34359738368 |214748364800 |
| Fresh F2FS filesystem bytes |33102495744 |213491122176 |
| First observed available data bytes |32577556480 |212104196096 |
| System/partition/reserve difference, bytes |1257242624 |1257242624 |
| Host QCOW2 file length after first boot, bytes |1292173312 |1292763136 |
| Actual Settings total display |34GB |215GB |
| Actual Settings used display |1.8GB |2.6GB |
| Actual Settings Android17 display |1.3GB |1.3GB |
| Actual Settings temporary-files display |518MB |1.4GB |

`g` in the CLI means GiB; Settings formats decimal GB. The apparent 32→34
and 200→215 display differences are unit conversions, not capacity inflation.
The 200-GiB filesystem's metadata/reserve footprint differs from 32 GiB;
do not impose an 8/10-GB system label or promise exact host/guest usage equality.
These byte counts describe this payload set, not fixed future partition sizes.
Host file length excludes boot cache/logs and is not a complete instance
physical-allocation report; the manager must account for those too.

Underlying checks used the live block disk and existing mount/vold/StorageStats
services, not an injected size property. The read-only KikiEmu checker requires
explicit PID/EXE/disk/creation identity and owned loopback ADB listener. Its
native Binder read IDs are pinned to the tested CP2A AIDL; recheck those before
using it against a changed upstream interface. Screenshots are DPI-aware full
Windows 2880x1920 desktop captures after HOME and Settings actually load.
Private screenshots/logs are not included in this public repository.

## Defects fixed rather than hidden

1. Init UUID discovery recognized MMC/NVME/SCSI but omitted virtio-blk.
   The tracked patch recognizes the exact virtio transport; both init stages
   are rebuilt. It does not simply trust disk number vda or every controller.
2. Android's physical-phone marketing-tier rounding turned 32 GiB into 64 GB
   and derived ~31 GB of system usage. `ro.kikiaosp.exact_storage_size` gates
   real whole-parent-block bytes in both StorageManager entry points and
   StorageStatsService. Other products retain their existing behavior.
3. Settings invented a minimum 1 GiB of temporary files even when the true
   unattributed usage was smaller. The same product flag now uses the real
   nonnegative remainder; other products retain the original minimum.
   Three Robolectric test methods/four assertions are tracked; these tests
   were added but NOT run as a separate host robotest suite. Settings compiled
   and actual 32/200-GiB UI behavior was checked instead.

The complete AOSP integration audit passes: 188 tracked patch paths and 5
overlay paths. No untracked upstream code changes outside the allowlist.
Native core tests: 65 checks pass. These are not setup.exe or public create tests.

## Boot and persistence boundaries

Both fresh capacities reach Android 17 / Linux 7.3-rc4-4k HOME on the actual
Windows ARM64 Surface: 8 vCPU/4 GiB, SDL/VirGL GLES3.1, 1003x1556, 288 dpi,
font 1.5, 120-Hz mode, no Grab/extra console. Crash buffer was empty when read.
The camera channel/bridge was enabled and the new system enumerated two
camera devices; front/rear live image/switch/photo/release regression is still
a separate release gate, not proven by device enumeration.

Normal guest shutdown unmounts/syncs data before kernel Power down; tests
do not merely kill QEMU. Both final R5 capacities retained their individual
data markers and exact kernel/vold/StorageStats capacities across normal
shutdown and another full HOME boot. 32 GiB after reboot had 32576106496 available
data bytes and host image length 1301413888; 200 GiB had 212102852608 available
data bytes and host image length 1302134784. Both were shut down again normally
and their QEMU/camera bridge processes exited. No existing user disk was
reformatted. A deliberately mismatched instance directory was rejected by
the read-only checker before ADB access.

Still required before publication: actual versioned ZIP schema/producer/reader,
clean independent release source/output provenance, proper release identities,
private release/dev ADB/control/camera/runtime namespaces and dual-instance
isolation, installer/desktop integration and the user's CLI/setup acceptance.
