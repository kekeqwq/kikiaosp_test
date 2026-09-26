#include <algorithm>
#include <errno.h>
#include <fcntl.h>
#include <linux/dma-buf.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <android/gui/ISurfaceComposerClient.h>
#include <gui/Surface.h>
#include <gui/SurfaceComposerClient.h>
#include <system/window.h>
#include <ui/DisplayMode.h>
#include <ui/Fence.h>
#include <ui/GraphicBuffer.h>
#include <ui/LayerStack.h>
#include <ui/PixelFormat.h>
#include <ui/Rect.h>
#include <utils/String8.h>

using namespace android;

struct Color {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
};

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

static void logStatus(const char* tag, unsigned frame, int status) {
    const int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
    if (fd >= 0) {
        dprintf(fd, "<6>KIKI-TEST-UI %s frame=%u status=%d\n", tag, frame, status);
        close(fd);
    }
}

static void setPixel(uint8_t* pixels, size_t rowBytes, int x, int y, const Color& color) {
    uint8_t* pixel = pixels + static_cast<size_t>(y) * rowBytes + static_cast<size_t>(x) * 4;
    pixel[0] = color.red;
    pixel[1] = color.green;
    pixel[2] = color.blue;
    pixel[3] = 255;
}

static void fillRect(uint8_t* pixels, size_t rowBytes, int width, int height,
                     int x, int y, int rectWidth, int rectHeight, const Color& color) {
    const int left = std::max(0, x);
    const int top = std::max(0, y);
    const int right = std::min(width, x + rectWidth);
    const int bottom = std::min(height, y + rectHeight);
    for (int row = top; row < bottom; ++row) {
        for (int column = left; column < right; ++column) {
            setPixel(pixels, rowBytes, column, row, color);
        }
    }
}

static void drawText(uint8_t* pixels, size_t rowBytes, int width, int height,
                     const char* text, int cell, int originX, int originY,
                     const Color& color) {
    int cursorX = originX;
    for (const char* character = text; *character; ++character) {
        if (*character == ' ') {
            cursorX += cell * 3;
            continue;
        }
        const Glyph* glyph = findGlyph(*character);
        if (glyph == nullptr) return;
        for (int row = 0; row < 7; ++row) {
            for (int column = 0; column < 5; ++column) {
                if (glyph->rows[row][column] == '1') {
                    fillRect(pixels, rowBytes, width, height,
                             cursorX + column * cell, originY + row * cell,
                             cell, cell, color);
                }
            }
        }
        cursorX += cell * 6;
    }
}

static bool paintFrame(const sp<GraphicBuffer>& buffer, unsigned frame,
                       int cell, int textX, int textY, int dotSize, int dotX, int dotY) {
    if (buffer == nullptr || buffer->initCheck() != NO_ERROR || buffer->handle == nullptr ||
        buffer->handle->numFds < 1 || buffer->format != PIXEL_FORMAT_RGBA_8888 ||
        buffer->getStride() < buffer->getWidth() || buffer->getWidth() < 1 ||
        buffer->getHeight() < 1) {
        logStatus("GraphicBuffer metadata invalid", frame, BAD_VALUE);
        return false;
    }
    const int width = static_cast<int>(buffer->getWidth());
    const int height = static_cast<int>(buffer->getHeight());
    const size_t rowBytes = static_cast<size_t>(buffer->getStride()) * 4;
    const size_t mapSize = rowBytes * buffer->getHeight();
    const int fd = buffer->handle->data[0];
    const off_t allocationSize = lseek(fd, 0, SEEK_END);
    if (allocationSize < 0 || static_cast<uint64_t>(allocationSize) < mapSize) {
        logStatus("dma-buf size query failed", frame,
                  allocationSize < 0 ? -errno : BAD_VALUE);
        return false;
    }

    dma_buf_sync sync{};
    sync.flags = DMA_BUF_SYNC_START | DMA_BUF_SYNC_WRITE;
    const bool syncStarted = ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync) == 0;
    void* mapped = mmap(nullptr, mapSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapped == MAP_FAILED) {
        const int error = errno;
        if (syncStarted) {
            sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE;
            ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync);
        }
        logStatus("dma-buf mmap failed", frame, -error);
        return false;
    }

    auto* pixels = static_cast<uint8_t*>(mapped);
    const Color background{4, 6, 10};
    const Color textColor{48, 255, 96};
    const Color squareColor = frame & 1 ? Color{255, 126, 24} : Color{36, 255, 40};
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) setPixel(pixels, rowBytes, x, y, background);
    }
    drawText(pixels, rowBytes, width, height, "TEST OK", cell, textX, textY, textColor);
    fillRect(pixels, rowBytes, width, height, dotX, dotY, dotSize, dotSize, squareColor);

    munmap(mapped, mapSize);
    if (syncStarted) {
        sync.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_WRITE;
        if (ioctl(fd, DMA_BUF_IOCTL_SYNC, &sync) != 0) {
            logStatus("dma-buf sync-end failed", frame, -errno);
        }
    }
    return true;
}

static status_t queueFrame(const sp<Surface>& producer, unsigned frame,
                           int cell, int textX, int textY, int dotSize, int dotX, int dotY) {
    sp<GraphicBuffer> buffer;
    sp<Fence> acquireFence;
    status_t result = producer->dequeueBuffer(&buffer, &acquireFence);
    if (result != NO_ERROR || buffer == nullptr) {
        const status_t error = result == NO_ERROR ? BAD_VALUE : result;
        logStatus("BufferQueue dequeue failed", frame, error);
        return error;
    }
    if (acquireFence != nullptr && acquireFence->isValid()) {
        result = acquireFence->waitForever("KikiTestUiNativeWindow");
        if (result != NO_ERROR) {
            producer->cancelBuffer(buffer, Fence::NO_FENCE);
            logStatus("BufferQueue acquire fence failed", frame, result);
            return result;
        }
    }
    if (!paintFrame(buffer, frame, cell, textX, textY, dotSize, dotX, dotY)) {
        producer->cancelBuffer(buffer, Fence::NO_FENCE);
        return NO_MEMORY;
    }
    result = producer->queueBuffer(buffer, Fence::NO_FENCE);
    if (result != NO_ERROR) logStatus("BufferQueue queue failed", frame, result);
    return result;
}

int main() {
    logStatus("waiting 25s for stable SurfaceFlinger/HWC", 0, 0);
    sleep(25);

    auto client = sp<SurfaceComposerClient>::make();
    status_t result = client->initCheck();
    if (result != NO_ERROR) {
        logStatus("SurfaceComposerClient initCheck failed", 0, result);
        return 1;
    }
    const auto displayIds = SurfaceComposerClient::getPhysicalDisplayIds();
    if (displayIds.empty()) {
        logStatus("no physical display", 0, NO_INIT);
        return 2;
    }
    const sp<IBinder> display = SurfaceComposerClient::getPhysicalDisplayToken(displayIds.front());
    if (display == nullptr) {
        logStatus("physical display token unavailable", 0, NO_INIT);
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
    const int textWidth = 39 * cell;
    const int textHeight = 7 * cell;
    const int textX = std::max(0, (width - textWidth) / 2);
    const int textY = std::max(0, height / 2 - textHeight);
    const int dotSize = std::max(24, std::min(width, height) / 12);
    const int dotY = std::min(height - dotSize, textY + textHeight + cell * 2);

    auto window = client->createSurface(String8("KikiTestNativeWindow"), width, height,
                                        PIXEL_FORMAT_RGBA_8888);
    if (window == nullptr || !window->isValid()) {
        logStatus("native Surface creation failed", 0, NO_INIT);
        return 4;
    }
    const sp<Surface> producer = window->getSurface();
    if (producer == nullptr) {
        logStatus("native Surface BufferQueue unavailable", 0, NO_INIT);
        return 4;
    }
    result = producer->connect(NATIVE_WINDOW_API_CPU, nullptr);
    if (result == NO_ERROR) result = producer->setBuffersDimensions(width, height);
    if (result == NO_ERROR) result = producer->setBuffersFormat(PIXEL_FORMAT_RGBA_8888);
    if (result == NO_ERROR) {
        result = producer->setUsage(GraphicBuffer::USAGE_HW_COMPOSER |
                                    GraphicBuffer::USAGE_SW_WRITE_OFTEN);
    }
    if (result != NO_ERROR) {
        logStatus("native Surface BufferQueue configuration failed", 0, result);
        return 4;
    }

    result = queueFrame(producer, 0, cell, textX, textY, dotSize, 24, dotY);
    if (result != NO_ERROR) {
        logStatus("initial BufferQueue frame failed", 0, result);
        return 4;
    }
    SurfaceComposerClient::Transaction show;
    show.setDisplayLayerStack(display, ui::DEFAULT_LAYER_STACK);
    show.setCrop(window, Rect(0, 0, width, height))
            .setPosition(window, 0, 0)
            .setLayer(window, 1)
            .show(window);
    result = show.apply(true);
    if (result != NO_ERROR) {
        logStatus("native Surface show transaction failed", 0, result);
        return 5;
    }
    logStatus("TEST OK single native BufferQueue Surface", 0, 0);

    const int travel = std::max(1, width - dotSize - 48);
    for (unsigned frame = 1;; ++frame) {
        const int phase = static_cast<int>(frame % 32);
        const int step = phase < 16 ? phase : 32 - phase;
        const int x = 24 + step * travel / 16;
        result = queueFrame(producer, frame, cell, textX, textY, dotSize, x, dotY);
        logStatus(result == NO_ERROR ? "native Surface frame queued" : "frame failed",
                  frame, result);
        usleep(500000);
    }
}
