ZYGOTE_FORCE_64 := true
$(call inherit-product, $(SRC_TARGET_DIR)/product/aosp_arm64.mk)

# KikiAOSP product identity. Keep the inherited Cuttlefish hardware contract
# unchanged; all Kiki-specific behavior belongs in this product/device tree.
PRODUCT_NAME := kikiaosp_test_arm64_phone
PRODUCT_DEVICE := kikiaosp_test
PRODUCT_BRAND := KikiAOSP
PRODUCT_MANUFACTURER := Kiki
PRODUCT_MODEL := KikiAOSP ARM64 Phone

PRODUCT_SYSTEM_NAME := KikiAOSP
PRODUCT_SYSTEM_DEVICE := kikiaosp_test
PRODUCT_SYSTEM_BRAND := KikiAOSP

PRODUCT_PRODUCT_PROPERTIES += \
    ro.kikiaosp.device=kikiaosp_test_arm64_phone \
    ro.kikiaosp.graphics=ranchu-native

# Build-only system-linked allocator variant for unified Binder validation.
PRODUCT_PACKAGES += kiki-allocator-system kiki-libnativeloader-bootstrap kiki-libsigchain-bootstrap kiki-libicu-bootstrap kiki-libnativebridge-bootstrap kiki-libicuuc-bootstrap kiki-libicui18n-bootstrap kiki-libandroidicu-bootstrap kiki-libnativehelper-bootstrap kiki-libart kiki-libartbase kiki-libartpalette kiki-libdexfile kiki-libprofile kiki-libstatspull kiki-libstatssocket kiki-libconnectivity-native kiki-libicu_jni kiki-libjavacore kiki-libopenjdk kiki-libopenjdkjvm kiki-libandroidio

# Early boot linkerconfig must use bootstrap linker before runtime APEX activation.
PRODUCT_PACKAGES += linkerconfig
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/bin/linkerconfig system/etc/fstab.ranchu system/lib64/libnativeloader.so system/lib64/libsigchain.so system/lib64/libicu.so system/lib64/libicui18n.so system/lib64/libnativebridge.so system/lib64/libicuuc.so system/lib64/bootstrap/libicui18n.so system/lib64/bootstrap/libandroidicu.so system/lib64/bootstrap/libnativehelper.so system/lib64/libart.so system/lib64/libartbase.so system/lib64/libartpalette.so system/lib64/libdexfile.so system/lib64/libprofile.so system/lib64/libstatspull.so system/lib64/libstatssocket.so system/etc/ld.config.kiki.txt


# Runtime apexd/vold need a second-stage default fstab.
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/selinux/plat_sepolicy_vers.txt:vendor/etc/selinux/plat_sepolicy_vers.txt
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/fstab.ranchu:system/etc/fstab.ranchu \
    device/kiki/kikiaosp_test/ld.config.kiki.txt:system/etc/ld.config.kiki.txt

# Temporary ART crash diagnostics for Zygote bring-up.
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/kiki-art-logcat.rc:system/etc/init/kiki-art-logcat.rc
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/kiki-minimal-native.rc:system/etc/init/kiki-minimal-native.rc
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/kiki-adb.rc:system/etc/init/kiki-adb.rc
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/etc/init/kiki-art-logcat.rc system/etc/init/kiki-minimal-native.rc system/etc/init/kiki-adb.rc

# KikiAOSP no-APEX runtime data. Keep these files version-matched to this build.
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/icu/icudt78l.dat:system/framework/etc/icu/icudt78l.dat
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/framework/etc/icu/icudt78l.dat
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

# KikiAOSP is an arm64-only target; do not start the failing 32-bit zygote.
PRODUCT_VENDOR_PROPERTIES := $(filter-out ro.zygote=zygote64_32,$(PRODUCT_VENDOR_PROPERTIES))
PRODUCT_VENDOR_PROPERTIES += ro.zygote=zygote64
TARGET_SUPPORTS_32_BIT_APPS := false
TARGET_SUPPORTS_64_BIT_APPS := true
ZYGOTE_FORCE_64 := true
PRODUCT_VENDOR_PROPERTIES := $(subst ro.zygote=zygote64_32,ro.zygote=zygote64,$(PRODUCT_VENDOR_PROPERTIES))

# KikiAOSP explicit ART boot assets
# KIKIAOSP_OLD_BOOT_DISABLED -apache-xml.oat:system/framework/boot-apache-xml.oat
# KIKIAOSP_OLD_BOOT_DISABLED -bouncycastle.oat:system/framework/boot-bouncycastle.oat
# KIKIAOSP_OLD_BOOT_DISABLED -core-icu4j.oat:system/framework/boot-core-icu4j.oat
# KIKIAOSP_OLD_BOOT_DISABLED -core-libart.oat:system/framework/boot-core-libart.oat
# KIKIAOSP_OLD_BOOT_DISABLED -ext.oat:system/framework/boot-ext.oat
# KIKIAOSP_OLD_BOOT_DISABLED -framework-graphics.oat:system/framework/boot-framework-graphics.oat
# KIKIAOSP_OLD_BOOT_DISABLED -framework-location.oat:system/framework/boot-framework-location.oat
# KIKIAOSP_OLD_BOOT_DISABLED -framework-ondeviceintelligence-platform.oat:system/framework/boot-framework-ondeviceintelligence-platform.oat
# KIKIAOSP_OLD_BOOT_DISABLED -framework.oat:system/framework/boot-framework.oat
# KIKIAOSP_OLD_BOOT_DISABLED -ims-common.oat:system/framework/boot-ims-common.oat
# KIKIAOSP_OLD_BOOT_DISABLED -okhttp.oat:system/framework/boot-okhttp.oat
# KIKIAOSP_OLD_BOOT_DISABLED -telephony-common.oat:system/framework/boot-telephony-common.oat
# KIKIAOSP_OLD_BOOT_DISABLED -voip-common.oat:system/framework/boot-voip-common.oat
# KIKIAOSP_OLD_BOOT_DISABLED -apache-xml.vdex:system/framework/boot-apache-xml.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -bouncycastle.vdex:system/framework/boot-bouncycastle.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -core-icu4j.vdex:system/framework/boot-core-icu4j.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -core-libart.vdex:system/framework/boot-core-libart.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -ext.vdex:system/framework/boot-ext.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -framework-graphics.vdex:system/framework/boot-framework-graphics.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -framework-location.vdex:system/framework/boot-framework-location.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -framework-ondeviceintelligence-platform.vdex:system/framework/boot-framework-ondeviceintelligence-platform.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -framework.vdex:system/framework/boot-framework.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -ims-common.vdex:system/framework/boot-ims-common.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -okhttp.vdex:system/framework/boot-okhttp.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -telephony-common.vdex:system/framework/boot-telephony-common.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -voip-common.vdex:system/framework/boot-voip-common.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -apache-xml.art:system/framework/boot-apache-xml.art
# KIKIAOSP_OLD_BOOT_DISABLED -bouncycastle.art:system/framework/boot-bouncycastle.art
# KIKIAOSP_OLD_BOOT_DISABLED -conscrypt.art:system/framework/boot-conscrypt.art
# KIKIAOSP_OLD_BOOT_DISABLED -conscrypt.oat:system/framework/boot-conscrypt.oat
# KIKIAOSP_OLD_BOOT_DISABLED -conscrypt.vdex:system/framework/boot-conscrypt.vdex
# KIKIAOSP_OLD_BOOT_DISABLED -core-icu4j.art:system/framework/boot-core-icu4j.art
# KIKIAOSP_OLD_BOOT_DISABLED -core-libart.art:system/framework/boot-core-libart.art
# KIKIAOSP_OLD_BOOT_DISABLED -okhttp.art:system/framework/boot-okhttp.art
# KIKIAOSP_OLD_BOOT_DISABLED -ext.art:system/framework/boot-ext.art
# KIKIAOSP_OLD_BOOT_DISABLED -framework-graphics.art:system/framework/boot-framework-graphics.art
# KIKIAOSP_OLD_BOOT_DISABLED -framework-location.art:system/framework/boot-framework-location.art
# KIKIAOSP_OLD_BOOT_DISABLED -framework-ondeviceintelligence-platform.art:system/framework/boot-framework-ondeviceintelligence-platform.art
# KIKIAOSP_OLD_BOOT_DISABLED -framework.art:system/framework/boot-framework.art
# KIKIAOSP_OLD_BOOT_DISABLED -ims-common.art:system/framework/boot-ims-common.art
# KIKIAOSP_OLD_BOOT_DISABLED -telephony-common.art:system/framework/boot-telephony-common.art
# KIKIAOSP_OLD_BOOT_DISABLED -voip-common.art:system/framework/boot-voip-common.art

# Allow explicit ART boot assets required by the no-APEX runtime path
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/framework/apache-xml.jar system/framework/boot-apache-xml.art system/framework/boot-apache-xml.oat system/framework/boot-apache-xml.vdex system/framework/boot-bouncycastle.art system/framework/boot-bouncycastle.oat system/framework/boot-bouncycastle.vdex system/framework/boot-conscrypt.art system/framework/boot-conscrypt.oat system/framework/boot-conscrypt.vdex system/framework/boot-core-icu4j.art system/framework/boot-core-icu4j.oat system/framework/boot-core-icu4j.vdex system/framework/boot-core-libart.art system/framework/boot-core-libart.oat system/framework/boot-core-libart.vdex system/framework/boot-ext.art system/framework/boot-ext.oat system/framework/boot-ext.vdex system/framework/boot-framework-graphics.art system/framework/boot-framework-graphics.oat system/framework/boot-framework-graphics.vdex system/framework/boot-framework-location.art system/framework/boot-framework-location.oat system/framework/boot-framework-location.vdex system/framework/boot-framework-ondeviceintelligence-platform.art system/framework/boot-framework-ondeviceintelligence-platform.oat system/framework/boot-framework-ondeviceintelligence-platform.vdex system/framework/boot-framework.art system/framework/boot-framework.oat system/framework/boot-framework.vdex system/framework/boot-ims-common.art system/framework/boot-ims-common.oat system/framework/boot-ims-common.vdex system/framework/boot-okhttp.art system/framework/boot-okhttp.oat system/framework/boot-okhttp.vdex system/framework/boot-telephony-common.art system/framework/boot-telephony-common.oat system/framework/boot-telephony-common.vdex system/framework/boot-voip-common.art system/framework/boot-voip-common.oat system/framework/boot-voip-common.vdex system/framework/bouncycastle.jar system/framework/conscrypt.jar system/framework/core-icu4j.jar system/framework/core-libart.jar system/framework/core-oj.jar system/framework/okhttp.jar system/framework/service-art.jar

# KikiAOSP no-APEX framework aliases
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/core-oj.jar:system/framework/kiki-core-oj.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/core-libart.jar:system/framework/kiki-core-libart.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/okhttp.jar:system/framework/kiki-okhttp.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/bouncycastle.jar:system/framework/kiki-bouncycastle.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/apache-xml.jar:system/framework/kiki-apache-xml.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/core-icu4j.jar:system/framework/kiki-core-icu4j.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/conscrypt.jar:system/framework/kiki-conscrypt.jar
PRODUCT_COPY_FILES += device/kiki/kikiaosp_test/prebuilt/framework/service-art.jar:system/framework/kiki-service-art.jar
# KIKIAOSP_OLD_BOOT_DISABLED .art:system/framework/boot.art
# KIKIAOSP_OLD_BOOT_DISABLED .oat:system/framework/boot.oat
# KIKIAOSP_OLD_BOOT_DISABLED .vdex:system/framework/boot.vdex

# Allow no-APEX framework aliases
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/framework/boot.art system/framework/boot.oat system/framework/boot.vdex system/framework/kiki-apache-xml.jar system/framework/kiki-bouncycastle.jar system/framework/kiki-conscrypt.jar system/framework/kiki-core-icu4j.jar system/framework/kiki-core-libart.jar system/framework/kiki-core-oj.jar system/framework/kiki-okhttp.jar system/framework/kiki-service-art.jar

# Bootstrap copy for libandroid dependency in the no-APEX namespace
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libcom.android.tethering.connectivity_native.so


PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libicu_jni.so
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libjavacore.so
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libopenjdk.so
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libandroidio.so
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib64/libopenjdkjvm.so

# KikiAOSP minimal profile: remove cross-device/account synchronization APK.
PRODUCT_PACKAGES -= CrossDeviceSync

# Stable bootstrap-only black-screen baseline. Non-core packages stay out of the runtime graph.
PRODUCT_PACKAGES -= \
    CrossDeviceSync AccountAndSyncSettings Contacts ContactsProvider Calendar CalendarProvider \
    Dialer TeleService TelecomShim TelephonyProvider MmsService CellBroadcastLegacyApp \
    CarrierConfig CFSatelliteService ONS QualifiedNetworksService ImsServiceEntitlement \
    GbaService SimAppDialog Stk CallLogBackup BlockedNumberProvider EmergencyInfo \
    BackupRestoreConfirmation SharedStorageBackup LocalTransport ManagedProvisioning \
    PrivateSpace DynamicSystemInstallationService DeviceAsWebcam Camera2 Gallery2 Music DeskClock \
    Browser2 messaging CompanionDeviceManager SecureElement CaptivePortalLogin \
    BasicDreams PhotoTable EasterEgg LiveWallpapersPicker WallpaperCropper WallpaperBackup \
    BuiltInPrintService PrintSpooler PrintRecommendationService MusicFX SoundPicker \
    BluetoothMidiService ThreadNetworkDemoApp VirtualDeviceManager WebViewUpdateService

# Final KikiAOSP package policy: apply after all inherited product additions.
KIKI_NONCORE_PACKAGES := \
    CrossDeviceSync AccountAndSyncSettings Contacts ContactsProvider Calendar CalendarProvider \
    Dialer TeleService TelecomShim TelephonyProvider MmsService CellBroadcastLegacyApp \
    CarrierConfig CFSatelliteService ONS QualifiedNetworksService ImsServiceEntitlement \
    GbaService SimAppDialog Stk CallLogBackup BlockedNumberProvider EmergencyInfo \
    BackupRestoreConfirmation SharedStorageBackup LocalTransport ManagedProvisioning \
    PrivateSpace DynamicSystemInstallationService DeviceAsWebcam Camera2 Gallery2 Music DeskClock \
    Browser2 messaging CompanionDeviceManager SecureElement CaptivePortalLogin \
    BasicDreams PhotoTable EasterEgg LiveWallpapersPicker WallpaperCropper WallpaperBackup \
    BuiltInPrintService PrintSpooler PrintRecommendationService MusicFX SoundPicker \
    BluetoothMidiService ThreadNetworkDemoApp VirtualDeviceManager WebViewUpdateService
PRODUCT_PACKAGES := $(filter-out $(KIKI_NONCORE_PACKAGES),$(PRODUCT_PACKAGES))

# Native HWC2 resource required by the ranchu HWC3 bridge.
PRODUCT_SOONG_NAMESPACES += device/generic/goldfish/hals/hwc3
PRODUCT_PACKAGES += android.hardware.graphics.composer3-service.ranchu
PRODUCT_PACKAGES += android.hardware.graphics.composer@2.1-resources kiki-mapper-minigbm
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/lib/android.hardware.graphics.composer@2.1.so

# Expose the ranchu HWC3 AIDL instance to servicemanager in the no-APEX path.
DEVICE_MANIFEST_FILE += device/kiki/kikiaosp_test/kiki_hwc3.xml
