# SPDX-License-Identifier: GPL-2.0-or-later
# Separate build target, same device/ABI and accepted runtime composition.
# Only independent, audited release outputs may use this target. The ordinary
# phone target remains the developer baseline and defaults to channel=dev.
$(call inherit-product, device/kiki/kikiaosp_test/kikiaosp_test_arm64_phone.mk)

PRODUCT_NAME := kikiaosp_test_arm64_phone_release
PRODUCT_DEVICE := kikiaosp_test
PRODUCT_MODEL := KikiAOSP 0.3 Alpha
PRODUCT_SYSTEM_NAME := kikiaosp_test

# Android 17 gen_build_prop.py emits display/fingerprint defaults with ?=.
# Explicit product properties are the supported override, not modifications
# to upstream Make/Soong or legacy PRODUCT_BUILD_PROP_OVERRIDES.
PRODUCT_SYSTEM_PROPERTIES += \
    ro.kikiaosp.build_channel=release \
    ro.kikiaosp.system_version=0.3.0-alpha \
    ro.build.display.id=KikiAOSP-0.3-Alpha \
    ro.build.fingerprint=KikiAOSP/kikiaosp_test/kikiaosp_test:17/CP2A.260605.016/KIKI_0.3.0_ALPHA:userdebug/test-keys
