# SPDX-License-Identifier: Apache-2.0
# Only our publisher key in otacerts.zip; never AOSP's public testkey.
PRODUCT_DEFAULT_DEV_CERTIFICATE := device/kiki/kikiaosp_test/ota/payload
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := boot system vendor
PRODUCT_VIRTUAL_AB_OTA := false
PRODUCT_USE_DYNAMIC_PARTITIONS := false
PRODUCT_PACKAGES += com.android.hardware.boot bootctl update_engine update_engine_client KikiUpdater
PRODUCT_COPY_FILES += \
    device/kiki/kikiaosp_test/ota/update-payload-key.pub.pem:system/etc/update_engine/update-payload-key.pub.pem
PRODUCT_SYSTEM_PROPERTIES += \
    ro.kiki.ota.layout=gpt-ab-v1 \
    ro.kiki.ota.sequence=1
