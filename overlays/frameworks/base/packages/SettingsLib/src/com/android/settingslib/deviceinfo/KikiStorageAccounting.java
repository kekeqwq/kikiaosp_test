/* SPDX-License-Identifier: Apache-2.0 */
package com.android.settingslib.deviceinfo;

import android.os.Environment;
import android.os.SystemProperties;

/** Sparse physical A/B image accounting; never changes writable-space APIs. */
public final class KikiStorageAccounting {
    private KikiStorageAccounting() {}

    private static long images(long total) {
        if (!SystemProperties.get("ro.kiki.ota.layout").equals("gpt-ab-v1")
                || !SystemProperties.get("sys.kiki.storage.status").equals("ready")
                || SystemProperties.getLong("sys.kiki.storage.disk", -1) != total) return -1;
        long data = Environment.getDataDirectory().getTotalSpace();
        long image = SystemProperties.getLong("sys.kiki.storage.images", -1);
        if (data <= 0 || SystemProperties.getLong("sys.kiki.storage.data", -1) != data
                || image <= 0 || image > total || data > total - image) return -1;
        // Read readiness again to reject an interrupted native refresh.
        return SystemProperties.get("sys.kiki.storage.status").equals("ready") ? image : -1;
    }

    public static long getUsedBytes(long total, long free) {
        long image = images(total);
        if (image < 0) return Math.max(0, total - free);
        long data = Environment.getDataDirectory().getTotalSpace();
        long unallocated = Environment.getDataDirectory().getFreeSpace();
        if (unallocated < 0 || unallocated > data) return Math.max(0, total - free);
        return image + data - unallocated;
    }

    public static long getSystemBytes(long total, long fallback) {
        long image = images(total);
        return image < 0 ? fallback : image;
    }

    public static long getReservedBytes(long total) {
        long image = images(total);
        if (image < 0) return -1;
        long data = Environment.getDataDirectory().getTotalSpace();
        long free = Environment.getDataDirectory().getFreeSpace();
        long usable = Environment.getDataDirectory().getUsableSpace();
        if (usable < 0 || free < usable || free > data) return -1;
        return total - data - image + free - usable;
    }

    public static long getWritableBytes(long total) {
        return images(total) < 0 ? -1 : Environment.getDataDirectory().getUsableSpace();
    }
}
