#include <algorithm>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#include <android/gui/ISurfaceComposerClient.h>
#include <gui/SurfaceComposerClient.h>
#include <math/vec3.h>
#include <ui/DisplayMode.h>
#include <ui/LayerStack.h>
#include <ui/PixelFormat.h>
#include <ui/Rect.h>
#include <utils/String8.h>

using namespace android;

static void logStatus(const char* tag, unsigned frame, int status) {
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI %s frame=%u status=%d\n", tag, frame, status);
        close(fd);
    }
}

static void logHandle(const char* name, const sp<SurfaceControl>& layer) {
    const sp<IBinder> handle = layer->getHandle();
    const String8 descriptor(handle->getInterfaceDescriptor());
    const int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI handle=%s binder=%p local=%p alive=%d descriptor='%s'\n",
                name, handle.get(), handle->localBinder(), handle->isBinderAlive(),
                descriptor.c_str());
        close(fd);
    }
}

static sp<SurfaceControl> makeColorLayer(const sp<SurfaceComposerClient>& client,
                                         const char* name) {
    return client->createSurface(String8(name), 0, 0, PIXEL_FORMAT_RGBA_8888,
                                 ISurfaceComposerClient::eFXSurfaceEffect);
}

int main() {
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI waiting 25s for stable SurfaceFlinger/HWC\n");
        close(fd);
    }
    sleep(25);

    auto client = sp<SurfaceComposerClient>::make();
    status_t result = client->initCheck();
    if (result != NO_ERROR) {
        logStatus("initCheck failed", 0, result);
        return 1;
    }
    const auto displayIds = SurfaceComposerClient::getPhysicalDisplayIds();
    if (displayIds.empty()) {
        logStatus("no physical display", 0, -1);
        return 2;
    }
    const sp<IBinder> display = SurfaceComposerClient::getPhysicalDisplayToken(displayIds.front());
    if (display == nullptr) {
        logStatus("physical display token unavailable", 0, -1);
        return 3;
    }
    ui::DisplayMode mode{};
    result = SurfaceComposerClient::getActiveDisplayMode(display, &mode);
    if (result != NO_ERROR) {
        logStatus("display mode query failed", 0, result);
        return 3;
    }
    const int width = mode.resolution.getWidth();
    const int height = mode.resolution.getHeight();
    const int dotSize = std::max(24, std::min(width, height) / 10);
    const int dotY = height / 2 - dotSize / 2;
    auto background = makeColorLayer(client, "KikiTestBackground");
    auto dot = makeColorLayer(client, "KikiTestMovingPixel");
    if (background == nullptr || dot == nullptr || !background->isValid() || !dot->isValid()) {
        logStatus("layer creation failed", 0, -1);
        return 4;
    }
    logHandle("background", background);
    logHandle("dot", dot);

    SurfaceComposerClient::Transaction show;
    show.setDisplayLayerStack(display, ui::DEFAULT_LAYER_STACK);
    show.setCrop(background, Rect(0, 0, width, height))
            .setColor(background, half3{0.015f, 0.02f, 0.03f})
            .setLayer(background, 0)
            .show(background)
            .setCrop(dot, Rect(0, 0, dotSize, dotSize))
            .setPosition(dot, 24, dotY)
            .setColor(dot, half3{0.0f, 1.0f, 0.25f})
            .setLayer(dot, 1)
            .show(dot);
    result = show.apply(true);
    if (result != NO_ERROR) {
        logStatus("show transaction failed", 0, result);
        return 5;
    }
    fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI TEST OK display=%dx%d animated-layers=2\n", width, height);
        close(fd);
    }

    const int travel = std::max(1, width - dotSize - 48);
    for (unsigned frame = 0;; ++frame) {
        const int phase = static_cast<int>(frame % 32);
        const int step = phase < 16 ? phase : 32 - phase;
        const int x = 24 + step * travel / 16;
        const half3 color = (frame & 1) ? half3{0.0f, 1.0f, 0.25f}
                                        : half3{0.0f, 0.55f, 1.0f};
        result = SurfaceComposerClient::Transaction()
                .setPosition(dot, x, dotY)
                .setColor(dot, color)
                .apply(true);
        logStatus(result == NO_ERROR ? "frame committed" : "frame failed", frame, result);
        usleep(500000);
    }
}
