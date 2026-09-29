include build/make/target/board/generic_arm64/BoardConfig.mk
# Build these packages in their own logical partitions rather than folding
# them back into /system as the generic GSI configuration does.
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := erofs
TARGET_2ND_ARCH :=
TARGET_SUPPORTS_32_BIT_APPS := false
TARGET_SUPPORTS_64_BIT_APPS := true

# KikiAOSP runs on QEMU's Ranchu/Goldfish device model. Keep the upstream
# emulator policy inputs so init can perform normal Android process labeling.
BOARD_VENDOR_SEPOLICY_DIRS += device/generic/goldfish/sepolicy/vendor
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/generic/goldfish/sepolicy/system_ext/private
