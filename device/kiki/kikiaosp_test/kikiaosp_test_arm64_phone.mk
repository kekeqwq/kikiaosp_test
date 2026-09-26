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

# Android's text stack requires the generated fallback map together with the
# actual font files. Inherit only the stock font fragments from the handheld
# product, not the phone/tablet service and app package set.
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, external/google-fonts/dancing-script/fonts.mk)
$(call inherit-product-if-exists, external/google-fonts/carrois-gothic-sc/fonts.mk)
$(call inherit-product-if-exists, external/google-fonts/coming-soon/fonts.mk)
$(call inherit-product-if-exists, external/google-fonts/cutive-mono/fonts.mk)
$(call inherit-product-if-exists, external/google-fonts/source-sans-pro/fonts.mk)
$(call inherit-product-if-exists, external/noto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-flex-fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-mono/fonts.mk)

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

# Keep the current trunk_staging flags, but disable its phone taskbar for this
# handheld test device so SystemUI creates the standard three-button nav bar.
PRODUCT_RELEASE_CONFIG_MAPS += \
    device/kiki/kikiaosp_test/release_config/release_config_map.textproto

PRODUCT_PRODUCT_PROPERTIES += \
    ro.kikiaosp.device=kikiaosp_test_arm64_phone \
    ro.kikiaosp.graphics=ranchu-native \
    ro.kikiaosp.drm_legacy_present=true

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
    ro.kikiaosp.telephony_registry=true \
    ro.kikiaosp.telecom_loader=false \
    ro.kikiaosp.battery_service=true \
    debug.hwui.use_buffer_age=false \
    debug.hwui.use_partial_updates=false \
    service.sf.prime_shader_cache=false \
    debug.sf.nobootanimation=1

# Retain the full standard core/APEX package graph, with Launcher3QuickStep
# and Settings as the user-facing apps. KikiWindowTest remains a source-level
# regression fixture and is not installed in the product image.
PRODUCT_PACKAGES += \
    Launcher3QuickStep \
    Settings \
    SystemUI \
    LatinIME \
    FusedLocation \
    SoundPicker \
    preinstalled-packages-platform-handheld-product.xml \
    preinstalled-packages-platform-handheld-system.xml \
    preinstalled-packages-handheld-system-ext.xml

# LocationManagerService requires a direct-boot-aware fused provider before
# phase 600 completes. Use AOSP's stock privileged provider rather than a
# Kiki-specific bypass or an unrelated full handheld product inheritance.
PRODUCT_SYSTEM_SERVER_APPS += FusedLocation

# Zygote preloads RenderScript framework classes even without app usage.
# Match the native runtime library included by AOSP handheld_system.mk.
PRODUCT_PACKAGES += \
    librs_jni

# Android 17's HintManagerService requires IPower/default during construction.
# Goldfish uses this upstream no-op virtual Power HAL for the same purpose.
PRODUCT_PACKAGES += \
    com.android.hardware.power

# JobScheduler requires BatteryManagerInternal during construction. Keep the
# platform BatteryService and pair it with AOSP's generic virtual Health HAL;
# this provides the required service contract without inventing a Kiki HAL.
PRODUCT_PACKAGES += \
    android.hardware.health-service.example

# LockSettingsService needs a live Keystore2 backed by KeyMint and Gatekeeper
# when it creates user-0 synthetic-password keys. These are AOSP's software
# emulator implementations; no secure hardware or physical peripheral is used.
PRODUCT_PACKAGES += \
    android.hardware.security.keymint-service \
    com.android.hardware.gatekeeper.nonsecure

# SystemServer's SoundTrigger capture-state listener requires a live
# AudioFlinger. Keep Android audio enabled and provide AOSP's default AIDL
# core/effect HAL services through their vendor APEX.
PRODUCT_PACKAGES += \
    com.android.hardware.audio \
    android.hardware.audio.output.prebuilt.xml
# The Android media stream starts at its maximum index. Host-side speaker
# volume remains under Windows control during emulator sessions.
PRODUCT_SYSTEM_PROPERTIES += \
    ro.config.media_vol_steps=15 \
    ro.config.media_vol_default=15
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    vendor/etc/permissions/android.hardware.audio.output.prebuilt.xml

# Register QEMU's virtio NIC as Android's unrestricted Ethernet default
# network. The static address matches QEMU user-mode NAT and the early ADB
# bootstrap; ConnectivityService owns the app-visible route and DNS.
PRODUCT_PACKAGES += \
    KikiConnectivityOverlay \
    android.hardware.ethernet.prebuilt.xml
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    vendor/etc/permissions/android.hardware.ethernet.prebuilt.xml \
    vendor/overlay/KikiConnectivityOverlay.apk

# The AOSP AIDL primary HAL sends the Speaker PCM stream to ALSA card 0,
# device 0. The host runner provides that card with virtio-sound.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    vendor/etc/audio_policy_configuration.xml \
    vendor/etc/audio_policy_volumes.xml \
    vendor/etc/default_volume_tables.xml \
    vendor/etc/r_submix_audio_policy_configuration.xml \
    vendor/etc/bluetooth_with_le_audio_policy_configuration_7_0.xml \
    vendor/etc/audio_effects_config.xml
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/audio/audio_policy_configuration.xml:vendor/etc/audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/audio_policy_volumes.xml:vendor/etc/audio_policy_volumes.xml \
    frameworks/av/services/audiopolicy/config/default_volume_tables.xml:vendor/etc/default_volume_tables.xml \
    frameworks/av/services/audiopolicy/config/r_submix_audio_policy_configuration.xml:vendor/etc/r_submix_audio_policy_configuration.xml \
    frameworks/av/services/audiopolicy/config/bluetooth_with_le_audio_policy_configuration_7_0.xml:vendor/etc/bluetooth_with_le_audio_policy_configuration_7_0.xml \
    hardware/interfaces/audio/aidl/default/audio_effects_config.xml:vendor/etc/audio_effects_config.xml

# Dynamic image sizing and RRO enforcement are required by the upstream core
# product layers and the fixed-orientation device overlay.
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true
# Keep this device overlay static: the navigation-bar and AppWidgetService
# config booleans are not overlayable resources, so enforced RRO silently
# drops them from the generated framework-res overlay.
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += \
    device/kiki/kikiaosp_test/overlay
PRODUCT_ENFORCE_RRO_TARGETS := *
PRODUCT_NO_BIONIC_PAGE_SIZE_MACRO := true

# Ranchu's first-stage boot must mount core APEXes before zygote starts.
# Compressed CAPEX files cannot be directly mounted by this bootstrap path.
PRODUCT_COMPRESSED_APEX := false

# Use Android's generated APEX linker configuration and the current Ranchu
# partition contract. The second-stage fstab is consumed by apexd/vold.
PRODUCT_PACKAGES += linkerconfig plat_sepolicy_vers.txt
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/bin/linkerconfig \
    system/etc/init/kiki-minimal-native.rc \
    system/etc/init/kiki-adb.rc \
    vendor/etc/fstab.ranchu \
    vendor/etc/ueventd.rc \
    vendor/etc/init/hw/init.ranchu.rc
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/fstab.ranchu:vendor/etc/fstab.ranchu \
    device/kiki/kikiaosp_test/ueventd.kikiaosp.rc:vendor/etc/ueventd.rc \
    device/kiki/kikiaosp_test/init.ranchu.rc:vendor/etc/init/hw/init.ranchu.rc \
    device/kiki/kikiaosp_test/kiki-adb.rc:system/etc/init/kiki-adb.rc \
    device/kiki/kikiaosp_test/kiki-minimal-native.rc:system/etc/init/kiki-minimal-native.rc \
    device/kiki/kikiaosp_test/kiki-adb-wait.sh:system/bin/kiki-adb-wait.sh

# The userdebug/eng image keeps the already verified TCP ADB path for test
# control. This product exposes no user build lunch target.
PRODUCT_PACKAGES += kiki-adbd kiki-adbd-standard adbd_flags_c_lib
PRODUCT_SYSTEM_PROPERTIES += ro.adb.secure=0
PRODUCT_SYSTEM_PROPERTIES += ro.adb.has_usb=false

# The host keyboard is a connected Android peripheral. Keep its device
# identity separate from the built-in virtio multitouch screen.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/usr/idc/Vendor_0627_Product_0001.idc \
    system/usr/keylayout/Generic.kl \
    system/usr/keychars/Generic.kcm
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/input/Vendor_0627_Product_0001.idc:system/usr/idc/Vendor_0627_Product_0001.idc
PRODUCT_PACKAGES += keylayout_data keychars_data

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

# Upstream QEMU exposes virtio-gpu/DRM, not the Goldfish pipe used by the
# emulator's default display finder. Select Ranchu HWC3's native DRM finder.
PRODUCT_VENDOR_PROPERTIES += ro.vendor.hwcomposer.display_finder_mode=drm

# Export the actual Goldfish namespace root so Make installs the Ranchu
# HWC3 vendor APEX into vendor.img (the hwc3 directory is not a namespace).
PRODUCT_SOONG_NAMESPACES += device/generic/goldfish
PRODUCT_PACKAGES += \
    com.android.hardware.graphics.composer.ranchu \
    android.hardware.graphics.composer@2.1-resources \
    android.hardware.graphics.allocator-service.minigbm \
    mapper.minigbm \
    vulkan.pastel
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/lib/android.hardware.graphics.composer@2.1.so
DEVICE_MANIFEST_FILE += device/kiki/kikiaosp_test/kiki_hwc3.xml

# Settings ringtone/notification/alarm rows launch SoundPicker. Package 14 is
# the current AOSP material set and is much smaller than AllAudio.mk.
$(call inherit-product-if-exists, frameworks/base/data/sounds/AudioPackage14.mk)
