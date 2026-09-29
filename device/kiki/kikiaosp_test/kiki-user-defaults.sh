#!/system/bin/sh

# Avoid Android's short desktop-style repeat cadence for an attached physical
# keyboard. Do not overwrite values an Android user has already customized.
set_if_unset() {
    namespace="$1"
    key="$2"
    value="$3"
    current=$(/system/bin/settings get "$namespace" "$key" 2>/dev/null)
    if [ -z "$current" ] || [ "$current" = "null" ]; then
        /system/bin/settings put "$namespace" "$key" "$value"
    fi
}

set_if_unset secure key_repeat_timeout 2000
set_if_unset secure key_repeat_delay 1000
