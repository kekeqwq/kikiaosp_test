PRODUCT_MAKEFILES := \
    kikiaosp_test_arm64_phone:$(LOCAL_DIR)/kikiaosp_test_arm64_phone.mk \
    kikiaosp_test_arm64_phone_release:$(LOCAL_DIR)/kikiaosp_test_arm64_phone_release.mk

COMMON_LUNCH_CHOICES := \
    kikiaosp_test_arm64_phone-cp2a-eng \
    kikiaosp_test_arm64_phone-cp2a-userdebug \
    kikiaosp_test_arm64_phone_release-cp2a-userdebug
