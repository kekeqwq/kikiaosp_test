# KikiAOSP test device

This repository contains the standalone KikiAOSP device tree for the ARM64 native graphics test target.

- Device identity: `kikiaosp_test`
- Product: `kikiaosp_test_arm64_phone`
- System identity: `KikiAOSP`
- Expected AOSP checkout: Android 17 `master`/matching manifest revision

The device tree is copied into an AOSP checkout at `device/kiki/kikiaosp_test`. The `patches/` directory records the source-level integration changes needed by the currently verified native ranchu HWC path; `overlays/` contains files that were untracked in the working AOSP tree. Applying these patches keeps the upstream checkout itself clean and makes the Kiki changes reviewable.

Use `scripts/apply-aosp-integration.sh /path/to/aosp` after syncing AOSP, then select `kikiaosp_test_arm64_phone-trunk_staging-eng`.