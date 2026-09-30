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

# KikiAOSP runs on QEMU's Ranchu/Goldfish device model. Keep the upstream
# emulator policy inputs so init can perform normal Android process labeling.
BOARD_VENDOR_SEPOLICY_DIRS += \
    device/generic/goldfish/sepolicy/vendor \
    device/kiki/kikiaosp_test/sepolicy/vendor
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/generic/goldfish/sepolicy/system_ext/private
