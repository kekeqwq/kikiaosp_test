#include <android/gui/ISurfaceComposerClient.h>
#include <algorithm>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <vector>

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

static uint8_t glyphRow(char c, int row) {
    static const uint8_t glyphs[][7] = {
        {14, 4, 4, 4, 4, 4, 4},       // T
        {31, 16, 16, 30, 16, 16, 31}, // E
        {15, 16, 16, 14, 1, 1, 30},   // S
        {0, 0, 0, 0, 0, 0, 0},        // space
        {14, 17, 17, 17, 17, 17, 14}, // O
        {17, 18, 20, 24, 20, 18, 17}, // K
    };
    int index = c == 'T' ? 0 : c == 'E' ? 1 : c == 'S' ? 2 :
                c == ' ' ? 3 : c == 'O' ? 4 : c == 'K' ? 5 : 3;
    return glyphs[index][row];
}

static sp<SurfaceControl> makeColorRect(const sp<SurfaceComposerClient>& client,
                                        const char* name, int x, int y, int width,
                                        int height, int z, const half3& color) {
    sp<SurfaceControl> layer = client->createSurface(
            String8(name), 0, 0, PIXEL_FORMAT_RGBA_8888,
            ISurfaceComposerClient::eFXSurfaceEffect);
    if (layer == nullptr || !layer->isValid()) return nullptr;
    SurfaceComposerClient::Transaction transaction;
    transaction.setCrop(layer, Rect(0, 0, width, height))
            .setColor(layer, color)
            .setPosition(layer, x, y)
            .setLayer(layer, z)
            .show(layer);
    if (transaction.apply(true) != NO_ERROR) return nullptr;
    return layer;
}

int main() {
    int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) { dprintf(fd, "<6>KIKI-TEST-UI waiting 12s for HWC\n"); close(fd); }
    sleep(12);

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
    const int kWidth = mode.resolution.getWidth();
    const int kHeight = mode.resolution.getHeight();
    const int kScale = std::max(3, std::min(kWidth, kHeight) / 48);
    const int kTextWidth = 7 * 6 * kScale;
    const int originX = (kWidth - kTextWidth) / 2;
    const int originY = kHeight / 3;
    int layoutFd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (layoutFd >= 0) {
        dprintf(layoutFd, "<6>KIKI-TEST-UI display=%dx%d scale=%d\n",
                kWidth, kHeight, kScale);
        close(layoutFd);
    }
    int z = 1000;
    const char text[] = "TEST OK";
    int runCount = 0;
    std::vector<sp<SurfaceControl>> textLayers;
    textLayers.reserve(32);

    // A single SurfaceFlinger transaction creates the white 5x7 TEST OK glyphs.
    SurfaceComposerClient::Transaction textTransaction;
    textTransaction.setDisplayLayerStack(display, ui::DEFAULT_LAYER_STACK);
    for (int row = 0; row < 7; ++row) {
        int x = 0;
        for (int ch = 0; text[ch]; ++ch) {
            uint8_t bits = glyphRow(text[ch], row);
            int col = 0;
            while (col < 5) {
                while (col < 5 && (bits & (1u << (4 - col))) == 0) ++col;
                int start = col;
                while (col < 5 && (bits & (1u << (4 - col))) != 0) ++col;
                if (start < col) {
                    char name[48];
                    snprintf(name, sizeof(name), "KikiTestText%d", runCount++);
                    sp<SurfaceControl> rect = client->createSurface(
                            String8(name), 0, 0, PIXEL_FORMAT_RGBA_8888,
                            ISurfaceComposerClient::eFXSurfaceEffect);
                    if (rect == nullptr || !rect->isValid()) {
                        logStatus("text layer creation failed", 0, -1);
                        return 2;
                    }
                    textLayers.push_back(rect);
                    textTransaction.setCrop(rect, Rect(0, 0, (col - start) * kScale, kScale))
                            .setColor(rect, half3{1.0f, 1.0f, 1.0f})
                            .setPosition(rect, originX + (ch * 6 + start) * kScale,
                                         originY + row * kScale)
                            .setLayer(rect, z++)
                            .show(rect);
                }
            }
        }
    }
    result = textTransaction.apply(true);
    if (result != NO_ERROR) {
        logStatus("text transaction failed", 0, result);
        return 3;
    }

    const int boxSize = std::max(24, kHeight / 8);
    const int boxY = originY + 7 * kScale + kHeight / 30;
    sp<SurfaceControl> box = makeColorRect(client, "KikiTestMovingBox", 0, boxY,
                                           boxSize, boxSize, z + 1,
                                           half3{0.0f, 1.0f, 0.25f});
    if (box == nullptr) {
        logStatus("animation layer creation failed", 0, -1);
        return 4;
    }
    int fd2 = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd2 >= 0) {
        dprintf(fd2, "<6>KIKI-TEST-UI TEST OK layers=%d animation=ready\n", runCount + 1);
        close(fd2);
    }

    // Move and recolor the single square on every frame; two successful commits
    // are the minimum visual-motion proof, then continue for user observation.
    for (unsigned frame = 0;; ++frame) {
        int phase = static_cast<int>(frame % 32);
        int travel = kWidth - boxSize;
        int x = phase < 16 ? phase * travel / 16 : (32 - phase) * travel / 16;
        half3 color = (frame & 1) ? half3{0.0f, 1.0f, 0.25f}
                                  : half3{0.0f, 0.6f, 1.0f};
        result = SurfaceComposerClient::Transaction()
                .setPosition(box, x, boxY)
                .setColor(box, color)
                .apply(true);
        logStatus(result == NO_ERROR ? "frame committed" : "frame failed", frame, result);
        usleep(500000);
    }
}
