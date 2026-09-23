// Static ARM64 DRM/KMS black scanout for the minimal KikiAOSP product.
// No libc or Android framework dependencies: only Linux syscalls and DRM UAPI.
#include <asm/unistd.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <fcntl.h>
#include <stdint.h>

static long syscall6(long nr, long a, long b, long c, long d, long e, long f) {
    register long x0 asm("x0") = a;
    register long x1 asm("x1") = b;
    register long x2 asm("x2") = c;
    register long x3 asm("x3") = d;
    register long x4 asm("x4") = e;
    register long x5 asm("x5") = f;
    register long x8 asm("x8") = nr;
    asm volatile("svc #0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x3),
                 "r"(x4), "r"(x5), "r"(x8) : "memory");
    return x0;
}

static long drm_ioctl(int fd, unsigned long request, void *value) {
    return syscall6(__NR_ioctl, fd, request, (long)value, 0, 0, 0);
}

static void sleep_seconds(long seconds) {
    struct { long tv_sec, tv_nsec; } duration = {seconds, 0};
    syscall6(__NR_nanosleep, (long)&duration, 0, 0, 0, 0, 0);
}

static void log_message(const char *message) {
    const char *p = message;
    while (*p) ++p;
    int fd = (int)syscall6(__NR_openat, -100, (long)"/dev/kmsg",
                           O_WRONLY | O_CLOEXEC, 0, 0, 0);
    if (fd >= 0) {
        syscall6(__NR_write, fd, (long)message, p - message, 0, 0, 0);
        syscall6(__NR_close, fd, 0, 0, 0, 0, 0);
    }
}

static uint32_t crtc_ids[16];
static uint32_t connector_ids[16];
static uint32_t framebuffer_ids[16];
static uint32_t encoder_ids[16];
static uint32_t prop_ids[128];
static uint64_t prop_values[128];
static struct drm_mode_modeinfo modes[64];

static int run(void) {
    int fd = -1;
    for (int retry = 0; retry < 30 && fd < 0; ++retry) {
        fd = (int)syscall6(__NR_openat, -100, (long)"/dev/dri/card0",
                           O_RDWR | O_CLOEXEC, 0, 0, 0);
        if (fd < 0) sleep_seconds(1);
    }
    if (fd < 0) { log_message("KIKI-BLACK open failed\n"); return 2; }

    struct drm_mode_card_res resources = {0};
    if (drm_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &resources) < 0 ||
        resources.count_crtcs == 0 || resources.count_crtcs > 16 ||
        resources.count_connectors == 0 || resources.count_connectors > 16 ||
        resources.count_fbs > 16 || resources.count_encoders > 16) {
        log_message("KIKI-BLACK resources failed\n"); return 3;
    }
    resources.crtc_id_ptr = (uintptr_t)crtc_ids;
    resources.connector_id_ptr = (uintptr_t)connector_ids;
    resources.fb_id_ptr = (uintptr_t)framebuffer_ids;
    resources.encoder_id_ptr = (uintptr_t)encoder_ids;
    if (drm_ioctl(fd, DRM_IOCTL_MODE_GETRESOURCES, &resources) < 0) {
        log_message("KIKI-BLACK resource IDs failed\n"); return 4;
    }

    uint32_t connector_id = 0;
    struct drm_mode_modeinfo mode = {0};
    for (uint32_t i = 0; i < resources.count_connectors; ++i) {
        struct drm_mode_get_connector connector = {.connector_id = connector_ids[i]};
        if (drm_ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &connector) < 0 ||
            connector.connection != 1 || connector.count_modes == 0 ||
            connector.count_modes > 64 || connector.count_props > 128 ||
            connector.count_encoders > 16) continue;
        connector.modes_ptr = (uintptr_t)modes;
        connector.props_ptr = (uintptr_t)prop_ids;
        connector.prop_values_ptr = (uintptr_t)prop_values;
        connector.encoders_ptr = (uintptr_t)encoder_ids;
        if (drm_ioctl(fd, DRM_IOCTL_MODE_GETCONNECTOR, &connector) < 0 ||
            connector.count_modes == 0) continue;
        mode = modes[0];
        for (uint32_t j = 0; j < connector.count_modes; ++j) {
            if (modes[j].hdisplay == 1080 && modes[j].vdisplay == 2400) {
                mode = modes[j]; break;
            }
        }
        connector_id = connector.connector_id;
        break;
    }
    if (!connector_id) { log_message("KIKI-BLACK no connected mode\n"); return 5; }

    struct drm_mode_create_dumb create = {
        .width = mode.hdisplay, .height = mode.vdisplay, .bpp = 32
    };
    if (drm_ioctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) {
        log_message("KIKI-BLACK create failed\n"); return 6;
    }
    struct drm_mode_map_dumb map = {.handle = create.handle};
    if (drm_ioctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
        log_message("KIKI-BLACK map failed\n"); return 7;
    }
    long pixels = syscall6(__NR_mmap, 0, create.size, 3, 1, fd, map.offset);
    if (pixels < 0 && pixels > -4096) {
        log_message("KIKI-BLACK mmap failed\n"); return 8;
    }
    volatile uint8_t *bytes = (volatile uint8_t *)pixels;
    for (uint64_t i = 0; i < create.size; ++i) bytes[i] = 0;
    syscall6(__NR_munmap, pixels, create.size, 0, 0, 0, 0);

    struct drm_mode_fb_cmd framebuffer = {
        .width = mode.hdisplay, .height = mode.vdisplay,
        .pitch = create.pitch, .bpp = 32, .depth = 24,
        .handle = create.handle
    };
    if (drm_ioctl(fd, DRM_IOCTL_MODE_ADDFB, &framebuffer) < 0) {
        log_message("KIKI-BLACK addfb failed\n"); return 9;
    }
    drm_ioctl(fd, DRM_IOCTL_SET_MASTER, 0);
    struct drm_mode_crtc crtc = {
        .set_connectors_ptr = (uintptr_t)&connector_id,
        .count_connectors = 1,
        .crtc_id = crtc_ids[0], .fb_id = framebuffer.fb_id,
        .mode_valid = 1, .mode = mode
    };
    if (drm_ioctl(fd, DRM_IOCTL_MODE_SETCRTC, &crtc) < 0) {
        log_message("KIKI-BLACK setcrtc failed\n"); return 10;
    }
    log_message("KIKI-BLACK scanout active\n");
    drm_ioctl(fd, DRM_IOCTL_DROP_MASTER, 0);
    for (;;) sleep_seconds(3600);
}

void _start(void) {
    int result = run();
    syscall6(__NR_exit, result, 0, 0, 0, 0, 0);
    for (;;) {}
}
