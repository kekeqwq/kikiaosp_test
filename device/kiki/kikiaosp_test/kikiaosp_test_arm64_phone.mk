# KikiAOSP Android 17 ARM64 test product.
#
# Compose from AOSP's generic media-capable core, then add only the handheld UI
# entry points needed to observe and control a real Android window. Do not
# inherit aosp_arm64.mk: that is a full GSI product with telephony/GSI/apps.

# core_64_bit.mk must be inherited before the core_minimal chain.
ZYGOTE_FORCE_64 := true
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_minimal.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_default.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/updatable_apex.mk)

# Product identity.
PRODUCT_NAME := kikiaosp_test_arm64_phone
PRODUCT_DEVICE := kikiaosp_test
PRODUCT_BRAND := KikiAOSP
PRODUCT_MANUFACTURER := Kiki
PRODUCT_MODEL := KikiAOSP Test Device
PRODUCT_SYSTEM_NAME := KikiAOSP
PRODUCT_SYSTEM_DEVICE := kikiaosp_test
PRODUCT_SYSTEM_BRAND := KikiAOSP

# This board has no physical orientation sensor; the overlay keeps display
# rotation deterministic while preserving the normal WindowManager path.
DEVICE_PACKAGE_OVERLAYS += device/kiki/kikiaosp_test/overlay

PRODUCT_PRODUCT_PROPERTIES += \
    ro.kikiaosp.device=kikiaosp_test_arm64_phone \
    ro.kikiaosp.graphics=ranchu-native

# Use the normal Android framework/service lifecycle. These are explicit
# device facts or narrowly retained platform workarounds, not a minimal server
# profile. In particular, no init rule below may stop netd, audio, graphics,
# storage, KeyMint, or other Android native services.
PRODUCT_SYSTEM_PROPERTIES += \
    ro.kikiaosp.bootstrap_only=false \
    ro.kikiaosp.minimal_services=false \
    ro.kikiaosp.single_mount_namespace=true \
    ro.kikiaosp.overlay_manager=true \
    ro.kikiaosp.sensorless=true \
    ro.kikiaosp.sensor_privacy=true \
    ro.kikiaosp.role_manager=true \
    ro.kikiaosp.usage_stats=true \
    ro.kikiaosp.compat_receiver=true \
    ro.kikiaosp.watchdog=true \
    ro.kikiaosp.keychain_service=true \
    ro.kikiaosp.rollback_manager=true \
    ro.kikiaosp.webview=true \
    ro.kikiaosp.telephony_registry=false \
    ro.kikiaosp.telecom_loader=false \
    ro.kikiaosp.battery_service=false \
    service.sf.prime_shader_cache=false

# Retain the full standard core/APEX package graph, but keep the user-facing
# system_ext set small and explicit. KikiWindowTest is installed by Soong as a
# normal APK, rather than being an out-of-band image-repack-only payload.
PRODUCT_PACKAGES += \
    Launcher3QuickStep \
    Settings \
    SystemUI \
    LatinIME \
    preinstalled-packages-platform-handheld-product.xml \
    preinstalled-packages-handheld-system-ext.xml \
    KikiWindowTest

# Dynamic image sizing and RRO enforcement are required by the upstream core
# product layers and the fixed-orientation device overlay.
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true
PRODUCT_ENFORCE_RRO_TARGETS := *
PRODUCT_NO_BIONIC_PAGE_SIZE_MACRO := true

# Use Android's generated APEX linker configuration and the current Ranchu
# partition contract. The second-stage fstab is consumed by apexd/vold.
PRODUCT_PACKAGES += linkerconfig plat_sepolicy_vers.txt
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/bin/linkerconfig \
    system/etc/init/kiki-minimal-native.rc \
    system/etc/init/kiki-adb.rc \
    vendor/etc/fstab.ranchu \
    vendor/etc/init/hw/init.ranchu.rc
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/fstab.ranchu:vendor/etc/fstab.ranchu \
    device/kiki/kikiaosp_test/init.ranchu.rc:vendor/etc/init/hw/init.ranchu.rc \
    device/kiki/kikiaosp_test/kiki-adb.rc:system/etc/init/kiki-adb.rc \
    device/kiki/kikiaosp_test/kiki-minimal-native.rc:system/etc/init/kiki-minimal-native.rc \
    device/kiki/kikiaosp_test/kiki-adb-wait.sh:system/bin/kiki-adb-wait.sh

# The userdebug/eng image keeps the already verified TCP ADB path for test
# control. This product exposes no user build lunch target.
PRODUCT_PACKAGES += kiki-adbd kiki-adbd-standard adbd_flags_c_lib
PRODUCT_SYSTEM_PROPERTIES += ro.adb.secure=0

# Runtime data still needed by the currently tracked ART/APEX compatibility
# patch. Do not delete these aliases/assets until the app_process bootclasspath
# change is removed atomically and Android 17's stock APEX classpath is proved.
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/prebuilt/icu/icudt78l.dat:system/framework/etc/icu/icudt78l.dat
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/framework/etc/icu/icudt78l.dat

KIKI_TZ_FILES := \
    tzdata \
    tz_version \
    versioned/8/icu/windowsZones.res \
    versioned/8/icu/timezoneTypes.res \
    versioned/8/icu/metaZones.res \
    versioned/8/icu/zoneinfo64.res \
    versioned/8/telephonylookup.xml \
    versioned/8/tzdata \
    versioned/8/tzlookup.xml \
    versioned/8/tz_version \
    versioned/9/icu/windowsZones.res \
    versioned/9/icu/timezoneTypes.res \
    versioned/9/icu/metaZones.res \
    versioned/9/icu/zoneinfo64.res \
    versioned/9/telephonylookup.xml \
    versioned/9/tzdata \
    versioned/9/tzlookup.xml \
    versioned/9/tz_version \
    versioned/10/icu/windowsZones.res \
    versioned/10/icu/timezoneTypes.res \
    versioned/10/icu/metaZones.res \
    versioned/10/icu/zoneinfo64.res \
    versioned/10/telephonylookup.xml \
    versioned/10/tzdata \
    versioned/10/tzlookup.xml \
    versioned/10/tz_version
PRODUCT_COPY_FILES += $(foreach f,$(KIKI_TZ_FILES),device/kiki/kikiaosp_test/prebuilt/tz/$(f):system/framework/etc/tz/$(f))
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += $(foreach f,$(KIKI_TZ_FILES),system/framework/etc/tz/$(f))

# Temporary no-APEX framework aliases consumed by patches/aosp-working-tree.patch.
# This is intentionally isolated here and remains technical debt, not the
# desired final Android runtime architecture.
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/prebuilt/framework/core-oj.jar:system/framework/kiki-core-oj.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/core-libart.jar:system/framework/kiki-core-libart.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/okhttp.jar:system/framework/kiki-okhttp.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/bouncycastle.jar:system/framework/kiki-bouncycastle.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/apache-xml.jar:system/framework/kiki-apache-xml.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/core-icu4j.jar:system/framework/kiki-core-icu4j.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/conscrypt.jar:system/framework/kiki-conscrypt.jar \
    device/kiki/kikiaosp_test/prebuilt/framework/service-art.jar:system/framework/kiki-service-art.jar
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/framework/apache-xml.jar \
    system/framework/bouncycastle.jar \
    system/framework/conscrypt.jar \
    system/framework/core-icu4j.jar \
    system/framework/core-libart.jar \
    system/framework/core-oj.jar \
    system/framework/okhttp.jar \
    system/framework/service-art.jar \
    system/framework/boot.art \
    system/framework/boot.oat \
    system/framework/boot.vdex \
    system/framework/kiki-apache-xml.jar \
    system/framework/kiki-bouncycastle.jar \
    system/framework/kiki-conscrypt.jar \
    system/framework/kiki-core-icu4j.jar \
    system/framework/kiki-core-libart.jar \
    system/framework/kiki-core-oj.jar \
    system/framework/kiki-okhttp.jar \
    system/framework/kiki-service-art.jar

# KikiAOSP is strictly 64-bit userspace; keep zygote selection consistent with
# the ARM64-only kernel and the empty secondary-architecture BoardConfig.
TARGET_SUPPORTS_32_BIT_APPS := false
TARGET_SUPPORTS_64_BIT_APPS := true

# Ranchu HWC3, minigbm allocator/mapper, and Pastel are the proven native
# display stack. This is the Android-facing display contract for upstream QEMU.
PRODUCT_SOONG_NAMESPACES += device/generic/goldfish/hals/hwc3
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.ranchu \
    android.hardware.graphics.composer@2.1-resources \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm \
    vulkan.pastel
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/lib/android.hardware.graphics.composer@2.1.so
DEVICE_MANIFEST_FILE += device/kiki/kikiaosp_test/kiki_hwc3.xml
