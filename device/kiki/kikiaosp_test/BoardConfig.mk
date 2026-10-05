include build/make/target/board/generic_arm64/BoardConfig.mk
# Match AOSP's system-image layout for this non-dynamic QEMU target. The
# system image is the root filesystem, so separate product/system_ext images
# would collide with /system/product and /system/system_ext compatibility
# symlinks after first-stage init switches root to /system.
TARGET_COPY_OUT_PRODUCT := system/product
TARGET_COPY_OUT_SYSTEM_EXT := system/system_ext
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE :=
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE :=
TARGET_2ND_ARCH :=
TARGET_SUPPORTS_32_BIT_APPS := false
TARGET_SUPPORTS_64_BIT_APPS := true

# Physical A/B: generous independent system slots, shared persistent F2FS.
# The Windows supervisor implements the virtual bootloader using AOSP BCB.
BOARD_AVB_ENABLE := false
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE :=
BOARD_CACHEIMAGE_PARTITION_SIZE :=
BOARD_USES_METADATA_PARTITION := false
BOARD_USES_SYSTEM_DLKMIMAGE := false
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE :=
TARGET_NO_KERNEL := false
TARGET_PREBUILT_KERNEL := device/kiki/kikiaosp_test/prebuilt/ota-kernel
BOARD_BOOT_HEADER_VERSION := 4
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_VENDORIMAGE_PARTITION_RESERVED_SIZE := 16777216

# KikiAOSP runs on QEMU's Ranchu/Goldfish device model. Keep the upstream
# emulator policy inputs so init can perform normal Android process labeling.
BOARD_VENDOR_SEPOLICY_DIRS += \
    device/generic/goldfish/sepolicy/vendor \
    device/kiki/kikiaosp_test/sepolicy/vendor
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/generic/goldfish/sepolicy/system_ext/private
