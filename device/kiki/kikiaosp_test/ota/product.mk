# SPDX-License-Identifier: Apache-2.0
# The native OTA trust store contains ONLY our publisher certificate.
# Keep the existing unrelated APK/platform signing identity unchanged.
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := boot system vendor
PRODUCT_VIRTUAL_AB_OTA := false
PRODUCT_USE_DYNAMIC_PARTITIONS := false
PRODUCT_PACKAGES += com.android.hardware.boot bootctl update_engine update_engine_client KikiUpdater KikiOtaCerts
PRODUCT_COPY_FILES += \
    .kiki-native-inputs/kernel:kernel \
    device/kiki/kikiaosp_test/ota/update-payload-key.pub.pem:system/etc/update_engine/update-payload-key.pub.pem
PRODUCT_SYSTEM_PROPERTIES += \
    ro.kiki.ota.layout=gpt-ab-v1 \
    ro.kiki.ota.sequence=1
