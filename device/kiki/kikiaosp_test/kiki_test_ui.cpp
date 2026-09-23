#include <algorithm>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string>
#include <vector>
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

struct Glyph {
    char character;
    const char* rows[7];
};

static const Glyph* findGlyph(char character) {
    static const Glyph glyphs[] = {
            {'T', {"11111", "00100", "00100", "00100", "00100", "00100", "00100"}},
            {'E', {"11111", "10000", "10000", "11110", "10000", "10000", "11111"}},
            {'S', {"01111", "10000", "10000", "01110", "00001", "00001", "11110"}},
            {'O', {"01110", "10001", "10001", "10001", "10001", "10001", "01110"}},
            {'K', {"10001", "10010", "10100", "11000", "10100", "10010", "10001"}},
    };
    for (const Glyph& glyph : glyphs) {
        if (glyph.character == character) return &glyph;
    }
    return nullptr;
}

struct Stroke {
    sp<SurfaceControl> layer;
    int x;
    int y;
    int width;
};

static bool appendTextStrokes(const sp<SurfaceComposerClient>& client,
                              const char* text, int cell, int originX, int originY,
                              std::vector<Stroke>* strokes) {
    int cursorX = originX;
    for (const char* character = text; *character; ++character) {
        if (*character == ' ') {
            cursorX += cell * 3;
            continue;
        }
        const Glyph* glyph = findGlyph(*character);
        if (glyph == nullptr) return false;
        for (int row = 0; row < 7; ++row) {
            int column = 0;
            while (column < 5) {
                while (column < 5 && glyph->rows[row][column] != '1') ++column;
                const int runStart = column;
                while (column < 5 && glyph->rows[row][column] == '1') ++column;
                if (runStart == column) continue;

                char name[48];
                snprintf(name, sizeof(name), "KikiTestText_%zu", strokes->size());
                auto layer = makeColorLayer(client, name);
                if (layer == nullptr || !layer->isValid()) return false;
                strokes->push_back({layer, cursorX + runStart * cell,
                                    originY + row * cell, (column - runStart) * cell});
            }
        }
        cursorX += cell * 6;
    }
    return true;
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
    const int cell = std::max(6, std::min(12, width / 48));
    const char* testText = "TEST OK";
    const int textCells = 39;
    const int textWidth = textCells * cell;
    const int textHeight = 7 * cell;
    const int textX = (width - textWidth) / 2;
    const int textY = std::max(24, height / 2 - textHeight);
    const int dotSize = std::max(24, std::min(width, height) / 12);
    const int dotY = std::min(height - dotSize - 24, textY + textHeight + cell * 2);
    auto background = makeColorLayer(client, "KikiTestBackground");
    auto dot = makeColorLayer(client, "KikiTestMovingPixel");
    if (background == nullptr || dot == nullptr || !background->isValid() || !dot->isValid()) {
        logStatus("layer creation failed", 0, -1);
        return 4;
    }
    std::vector<Stroke> textStrokes;
    if (!appendTextStrokes(client, testText, cell, textX, textY, &textStrokes)) {
        logStatus("text stroke creation failed", 0, -1);
        return 4;
    }
    logHandle("background", background);
    logHandle("dot", dot);

    SurfaceComposerClient::Transaction show;
    show.setDisplayLayerStack(display, ui::DEFAULT_LAYER_STACK);
    show.setCrop(background, Rect(0, 0, width, height))
            .setColor(background, half3{0.015f, 0.02f, 0.03f})
            .setLayer(background, 0)
            .show(background);
    int layerIndex = 1;
    for (const Stroke& stroke : textStrokes) {
        show.setCrop(stroke.layer, Rect(0, 0, stroke.width, cell))
                .setPosition(stroke.layer, stroke.x, stroke.y)
                .setColor(stroke.layer, half3{0.2f, 1.0f, 0.55f})
                .setLayer(stroke.layer, layerIndex++)
                .show(stroke.layer);
    }
    show.setCrop(dot, Rect(0, 0, dotSize, dotSize))
            .setPosition(dot, 24, dotY)
            .setColor(dot, half3{0.0f, 1.0f, 0.25f})
            .setLayer(dot, layerIndex)
            .show(dot);
    result = show.apply(true);
    if (result != NO_ERROR) {
        logStatus("show transaction failed", 0, result);
        return 5;
    }
    fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI TEST OK display=%dx%d text-strokes=%zu animated=1\n",
                width, height, textStrokes.size());
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
