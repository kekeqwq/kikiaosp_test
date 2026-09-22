#include <android/gui/ISurfaceComposerClient.h>
#include <gui/Surface.h>
#include <gui/SurfaceComposerClient.h>
#include <ui/PixelFormat.h>
#include <utils/String8.h>

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include <cstdarg>

using namespace android;

static void klog(const char* fmt, ...) {
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) { dprintf(fd, "<6>KIKI-CPU %s", buf); close(fd); }
}

int main() {
    // Let HWC claim and release DRM master before the first gralloc request.
    // Starting this probe at boot races the compositor on the minimal image.
    klog("delaying buffer probe 12s\n");
    sleep(12);
    auto client = sp<SurfaceComposerClient>::make();
    status_t err = client->initCheck();
    if (err != NO_ERROR) {
        klog("initCheck failed %d\n", err);
        fprintf(stderr, "KIKI-CPU initCheck failed: %d\n", err);
        return 1;
    }

    constexpr uint32_t kWidth = 1080, kHeight = 2400;
    sp<SurfaceControl> layer = client->createSurface(
            String8("KikiCPUProbe"), kWidth, kHeight, PIXEL_FORMAT_RGBA_8888, 0);
    if (layer == nullptr || !layer->isValid()) {
        klog("createSurface failed\n");
        fprintf(stderr, "KIKI-CPU createSurface failed\n");
        return 2;
    }
    SurfaceComposerClient::Transaction()
            .setLayer(layer, 0x7fffffff)
            .setPosition(layer, 0, 0)
            .show(layer)
            .apply(true);
    sp<Surface> surface = layer->getSurface();
    if (surface == nullptr) { klog("getSurface failed\n"); return 3; }
    klog("buffer layer shown\n");
    for (;;) {
        ANativeWindow_Buffer buffer{};
        err = surface->lock(&buffer, nullptr);
        if (err != NO_ERROR) {
            klog("lock failed %d\n", err);
            usleep(250000);
            continue;
        }
        auto* pixels = static_cast<uint8_t*>(buffer.bits);
        for (int y = 0; y < buffer.height; ++y) {
            for (int x = 0; x < buffer.width; ++x) {
                uint8_t* p = pixels + 4 * (y * buffer.stride + x);
                p[0] = (x < 32 && y < 32) ? 255 : 0;
                p[1] = 255; p[2] = 0; p[3] = 255;
            }
        }
        err = surface->unlockAndPost();
        klog("post %d %dx%d stride=%d\n", err, buffer.width, buffer.height, buffer.stride);
        usleep(1000000);
    }
}
