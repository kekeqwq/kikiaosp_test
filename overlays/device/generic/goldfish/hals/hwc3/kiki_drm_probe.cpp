// Minimal independent KikiAOSP DRM scanout probe.
// This process deliberately does not share HWC/DrmClient objects.
#include <errno.h>
#include <fcntl.h>
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <xf86drm.h>
#include <xf86drmMode.h>

static int ioctl_drm(int fd, unsigned long request, void* arg) {
    int rc;
    do {
        rc = ioctl(fd, request, arg);
    } while (rc < 0 && errno == EINTR);
    return rc;
}

int main() {
    setbuf(stdout, nullptr);
    const int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "KIKI-PROBE open failed: %s\n", strerror(errno));
        return 1;
    }
    drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
    if (drmSetMaster(fd) != 0) {
        fprintf(stderr, "KIKI-PROBE drmSetMaster failed: %s\n", strerror(errno));
        return 2;
    }

    drmModeRes* res = drmModeGetResources(fd);
    if (!res) return 3;
    drmModeConnector* connector = nullptr;
    for (int i = 0; i < res->count_connectors; ++i) {
        auto* c = drmModeGetConnector(fd, res->connectors[i]);
        if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes > 0) {
            connector = c;
            break;
        }
        if (c) drmModeFreeConnector(c);
    }
    if (!connector) {
        fprintf(stderr, "KIKI-PROBE no connected connector\n");
        return 4;
    }
    const drmModeModeInfo mode = connector->modes[0];
    uint32_t crtc_id = 0;
    drmModeEncoder* encoder = connector->encoder_id ? drmModeGetEncoder(fd, connector->encoder_id) : nullptr;
    if (encoder) {
        crtc_id = encoder->crtc_id;
        drmModeFreeEncoder(encoder);
    }
    if (!crtc_id && res->count_crtcs > 0) crtc_id = res->crtcs[0];
    if (!crtc_id) return 5;

    drm_mode_create_dumb create{};
    create.width = mode.hdisplay;
    create.height = mode.vdisplay;
    create.bpp = 32;
    if (ioctl_drm(fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) return 6;
    drm_mode_map_dumb map{};
    map.handle = create.handle;
    if (ioctl_drm(fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) return 7;
    void* pixels = mmap(nullptr, create.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, map.offset);
    if (pixels == MAP_FAILED) return 8;
    memset(pixels, 0, create.size);
    auto* p = static_cast<uint32_t*>(pixels);
    p[(mode.vdisplay / 2) * (create.pitch / 4) + mode.hdisplay / 2] = 0xff00ff00u;
    munmap(pixels, create.size);

    uint32_t handles[4] = {create.handle, 0, 0, 0};
    uint32_t pitches[4] = {create.pitch, 0, 0, 0};
    uint32_t offsets[4] = {0, 0, 0, 0};
    uint32_t fb = 0;
    if (drmModeAddFB2(fd, mode.hdisplay, mode.vdisplay, DRM_FORMAT_XRGB8888,
                      handles, pitches, offsets, &fb, 0) != 0) return 9;
    uint32_t connector_id = connector->connector_id;
    if (drmModeSetCrtc(fd, crtc_id, fb, 0, 0, &connector_id, 1,
                       const_cast<drmModeModeInfo*>(&mode)) != 0) {
        fprintf(stderr, "KIKI-PROBE set CRTC failed: %s\n", strerror(errno));
        return 10;
    }
    fprintf(stderr, "KIKI-PROBE scanout %ux%u connector=%u crtc=%u fb=%u\n",
            mode.hdisplay, mode.vdisplay, connector_id, crtc_id, fb);
    drmModeFreeConnector(connector);
    drmModeFreeResources(res);
    // Keep the GEM object and framebuffer alive for the display lifetime.
    for (;;) sleep(3600);
}
