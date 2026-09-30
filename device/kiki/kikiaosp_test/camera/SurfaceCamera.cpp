/*
 * Copyright (C) 2026 The KikiAOSP Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include <arpa/inet.h>
#include <dirent.h>
#include <endian.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/system_properties.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include <android-base/strings.h>
#include <log/log.h>
#include <system/camera_metadata.h>
#include <ui/GraphicBufferMapper.h>
#include <utils/SystemClock.h>

#include "BaseQemuCamera.h"
#include "CachedStreamBuffer.h"
#include "debug.h"
#include "SurfaceCamera.h"
#include "metadata_utils.h"

namespace android::hardware::camera::provider::implementation::hw {
namespace {

constexpr uint32_t kHostNv12 = 1;
constexpr uint32_t kCaptureWidth = 640;
constexpr uint32_t kCaptureHeight = 480;
constexpr size_t kMaxFrameBytes = 32 * 1024 * 1024;
constexpr char kVirtioPortName[] = "org.kikiaosp.camera";

struct Nv12Frame {
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t stride = 0;
  uint32_t sequence = 0;
  uint64_t timestamp100ns = 0;
  std::vector<uint8_t> pixels;
};

bool writeFully(int fd, const void *buffer, size_t size) {
  const uint8_t *cursor = static_cast<const uint8_t *>(buffer);
  while (size > 0) {
    const ssize_t written = write(fd, cursor, size);
    if (written < 0 && errno == EINTR)
      continue;
    if (written <= 0)
      return false;
    cursor += written;
    size -= static_cast<size_t>(written);
  }
  return true;
}

bool readFully(int fd, void *buffer, size_t size) {
  uint8_t *cursor = static_cast<uint8_t *>(buffer);
  while (size > 0) {
    const ssize_t received = read(fd, cursor, size);
    if (received < 0 && errno == EINTR)
      continue;
    if (received <= 0)
      return false;
    cursor += received;
    size -= static_cast<size_t>(received);
  }
  return true;
}

bool writeLine(int fd, const std::string &text) {
  return writeFully(fd, text.data(), text.size());
}

bool readLine(int fd, std::string *line) {
  line->clear();
  for (size_t i = 0; i < 512; ++i) {
    char ch;
    if (!readFully(fd, &ch, 1))
      return false;
    if (ch == '\n')
      return true;
    if (ch != '\r')
      line->push_back(ch);
  }
  return false;
}

bool readPortPath(std::string *devicePath) {
  DIR *directory = opendir("/sys/class/virtio-ports");
  if (!directory)
    return false;
  bool found = false;
  while (dirent *entry = readdir(directory)) {
    if (entry->d_name[0] == '.')
      continue;
    const std::string namePath =
        std::string("/sys/class/virtio-ports/") + entry->d_name + "/name";
    int nameFd = open(namePath.c_str(), O_RDONLY | O_CLOEXEC);
    if (nameFd < 0)
      continue;
    char name[128]{};
    const ssize_t count = read(nameFd, name, sizeof(name) - 1);
    close(nameFd);
    if (count <= 0)
      continue;
    name[count] = '\0';
    if (android::base::Trim(name) == kVirtioPortName) {
      *devicePath = std::string("/dev/") + entry->d_name;
      found = true;
      break;
    }
  }
  closedir(directory);
  return found;
}

bool waitForPort(std::string *devicePath) {
  for (int attempt = 0; attempt < 100; ++attempt) {
    if (readPortPath(devicePath))
      return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
  return false;
}

class SurfaceCameraTransport {
public:
  static SurfaceCameraTransport &instance() {
    static SurfaceCameraTransport transport;
    return transport;
  }

  bool acquire(const void *owner, const std::string &facing, uint32_t width,
               uint32_t height) {
    std::lock_guard<std::mutex> lock(mMutex);
    if (mOwner == owner && mFacing == facing && mWidth == width &&
        mHeight == height) {
      return true;
    }
    if (!ensurePortLocked())
      return false;
    if (mOwner != nullptr && !closeCameraLocked())
      return false;

    if (!writeLine(mFd, "OPEN " + facing + " " + std::to_string(width) + " " +
                            std::to_string(height) + "\n")) {
      resetLocked();
      return false;
    }
    std::string reply;
    if (!readLine(mFd, &reply)) {
      resetLocked();
      return false;
    }
    unsigned actualWidth = 0, actualHeight = 0, stride = 0;
    char actualFacing[16]{};
    if (sscanf(reply.c_str(), "READY %15s %u %u %u", actualFacing, &actualWidth,
               &actualHeight, &stride) != 4 ||
        facing != actualFacing || actualWidth != width ||
        actualHeight != height || stride < width) {
      ALOGE("Surface camera bridge rejected OPEN: %s", reply.c_str());
      resetLocked();
      return false;
    }
    mOwner = owner;
    mFacing = facing;
    mWidth = actualWidth;
    mHeight = actualHeight;
    mStride = stride;
    ALOGI("Opened real Surface %s camera at %ux%u", facing.c_str(), width,
          height);
    return true;
  }

  void release(const void *owner) {
    std::lock_guard<std::mutex> lock(mMutex);
    if (owner == mOwner)
      closeCameraLocked();
  }

  bool capture(const void *owner, Nv12Frame *frame) {
    std::lock_guard<std::mutex> lock(mMutex);
    if (owner != mOwner || mFd < 0 || !writeLine(mFd, "FRAME\n"))
      return false;

    // KCF1 wire header: magic (4), width/height/stride/format/sequence
    // (5 * 4), timestamp (8), payload size (4) = 36 bytes.
    std::array<uint8_t, 36> header{};
    if (!readFully(mFd, header.data(), 4)) {
      resetLocked();
      return false;
    }
    if (std::memcmp(header.data(), "KCF1", 4) != 0) {
      ALOGE("Surface camera bridge sent invalid header bytes=%02x %02x %02x %02x",
            header[0], header[1], header[2], header[3]);
      resetLocked();
      return false;
    }
    if (!readFully(mFd, header.data() + 4, header.size() - 4)) {
      resetLocked();
      return false;
    }

    uint32_t value32;
    std::memcpy(&value32, &header[4], 4);
    frame->width = ntohl(value32);
    std::memcpy(&value32, &header[8], 4);
    frame->height = ntohl(value32);
    std::memcpy(&value32, &header[12], 4);
    frame->stride = ntohl(value32);
    std::memcpy(&value32, &header[16], 4);
    const uint32_t format = ntohl(value32);
    std::memcpy(&value32, &header[20], 4);
    frame->sequence = ntohl(value32);
    uint64_t value64;
    std::memcpy(&value64, &header[24], 8);
    frame->timestamp100ns = be64toh(value64);
    std::memcpy(&value32, &header[32], 4);
    const uint32_t bytes = ntohl(value32);
    const uint64_t expected =
        static_cast<uint64_t>(frame->width) * frame->height * 3 / 2;
    if (format != kHostNv12 || frame->width != mWidth ||
        frame->height != mHeight || frame->stride != frame->width ||
        bytes != expected || bytes > kMaxFrameBytes) {
      ALOGE("Invalid Surface frame: %ux%u stride=%u format=%u bytes=%u",
            frame->width, frame->height, frame->stride, format, bytes);
      resetLocked();
      return false;
    }
    frame->pixels.resize(bytes);
    if (!readFully(mFd, frame->pixels.data(), frame->pixels.size())) {
      resetLocked();
      return false;
    }
    return true;
  }

private:
  bool ensurePortLocked() {
    if (mFd >= 0)
      return true;
    std::string path;
    if (!waitForPort(&path)) {
      ALOGE("virtio camera port %s did not appear", kVirtioPortName);
      return false;
    }
    mFd = open(path.c_str(), O_RDWR | O_CLOEXEC);
    if (mFd < 0)
      ALOGE("open(%s) failed: %s", path.c_str(), strerror(errno));
    return mFd >= 0;
  }

  bool closeCameraLocked() {
    if (mFd < 0 || mOwner == nullptr) {
      mOwner = nullptr;
      mFacing.clear();
      return true;
    }
    bool closed = writeLine(mFd, "CLOSE\n");
    std::string reply;
    closed = closed && readLine(mFd, &reply) && reply == "CLOSED";
    if (!closed) {
      ALOGW("Surface camera bridge did not acknowledge CLOSE; reset the "
            "transport");
      resetLocked();
      return false;
    }
    ALOGI("Released real Surface %s camera", mFacing.c_str());
    mOwner = nullptr;
    mFacing.clear();
    mWidth = mHeight = mStride = 0;
    return true;
  }

  void resetLocked() {
    if (mFd >= 0)
      close(mFd);
    mFd = -1;
    mOwner = nullptr;
    mFacing.clear();
    mWidth = mHeight = mStride = 0;
  }

  std::mutex mMutex;
  int mFd = -1;
  const void *mOwner = nullptr;
  std::string mFacing;
  uint32_t mWidth = 0;
  uint32_t mHeight = 0;
  uint32_t mStride = 0;
};

bool copyToYuv(const Nv12Frame &source, uint32_t dstWidth, uint32_t dstHeight,
               android_ycbcr &destination) {
  if (!destination.y || !destination.cb || !destination.cr || (dstWidth & 1) ||
      (dstHeight & 1))
    return false;
  for (uint32_t y = 0; y < dstHeight; ++y) {
    const uint32_t sy = static_cast<uint64_t>(y) * source.height / dstHeight;
    auto *row = static_cast<uint8_t *>(destination.y) + y * destination.ystride;
    for (uint32_t x = 0; x < dstWidth; ++x) {
      const uint32_t sx = static_cast<uint64_t>(x) * source.width / dstWidth;
      row[x] = source.pixels[static_cast<size_t>(sy) * source.width + sx];
    }
  }
  const uint8_t *sourceUv =
      source.pixels.data() + static_cast<size_t>(source.width) * source.height;
  for (uint32_t y = 0; y < dstHeight / 2; ++y) {
    const uint32_t sy =
        (static_cast<uint64_t>(y * 2) * source.height / dstHeight) & ~1U;
    for (uint32_t x = 0; x < dstWidth / 2; ++x) {
      const uint32_t sx =
          (static_cast<uint64_t>(x * 2) * source.width / dstWidth) & ~1U;
      const uint8_t u =
          sourceUv[static_cast<size_t>(sy / 2) * source.width + sx];
      const uint8_t v =
          sourceUv[static_cast<size_t>(sy / 2) * source.width + sx + 1];
      auto *cb = static_cast<uint8_t *>(destination.cb) +
                 y * destination.cstride + x * destination.chroma_step;
      auto *cr = static_cast<uint8_t *>(destination.cr) +
                 y * destination.cstride + x * destination.chroma_step;
      *cb = u;
      *cr = v;
    }
  }
  return true;
}

bool copyToScaledNv12(const Nv12Frame &source, uint32_t dstWidth,
                      uint32_t dstHeight, std::vector<uint8_t> *pixels,
                      android_ycbcr *destination) {
  if (!pixels || !destination || dstWidth == 0 || dstHeight == 0 ||
      (dstWidth & 1) || (dstHeight & 1) || dstWidth > source.width ||
      dstHeight > source.height) {
    return false;
  }

  const size_t yBytes = static_cast<size_t>(dstWidth) * dstHeight;
  pixels->resize(yBytes + yBytes / 2);
  auto *uv = pixels->data() + yBytes;
  destination->y = pixels->data();
  destination->cb = uv;
  destination->cr = uv + 1;
  destination->ystride = dstWidth;
  destination->cstride = dstWidth;
  destination->chroma_step = 2;
  return copyToYuv(source, dstWidth, dstHeight, *destination);
}

uint8_t clamp8(int value) {
  return static_cast<uint8_t>(std::clamp(value, 0, 255));
}

bool copyToRgba(const Nv12Frame &source, uint32_t dstWidth, uint32_t dstHeight,
                uint32_t dstStride, uint8_t *destination) {
  if (!destination || dstStride < dstWidth)
    return false;
  const uint8_t *sourceUv =
      source.pixels.data() + static_cast<size_t>(source.width) * source.height;
  for (uint32_t y = 0; y < dstHeight; ++y) {
    const uint32_t sy = static_cast<uint64_t>(y) * source.height / dstHeight;
    uint8_t *row = destination + static_cast<size_t>(y) * dstStride * 4;
    for (uint32_t x = 0; x < dstWidth; ++x) {
      const uint32_t sx = static_cast<uint64_t>(x) * source.width / dstWidth;
      const int yy = std::max(
          0, static_cast<int>(
                 source.pixels[static_cast<size_t>(sy) * source.width + sx]) -
                 16);
      const uint32_t uvIndex =
          static_cast<size_t>(sy / 2) * source.width + (sx & ~1U);
      const int u = static_cast<int>(sourceUv[uvIndex]) - 128;
      const int v = static_cast<int>(sourceUv[uvIndex + 1]) - 128;
      const size_t out = static_cast<size_t>(x) * 4;
      row[out] = clamp8((298 * yy + 409 * v + 128) >> 8);
      row[out + 1] = clamp8((298 * yy - 100 * u - 208 * v + 128) >> 8);
      row[out + 2] = clamp8((298 * yy + 516 * u + 128) >> 8);
      row[out + 3] = 255;
    }
  }
  return true;
}

} // namespace

SurfaceCamera::SurfaceCamera(const Parameters &params)
    : BaseQemuCamera(params) {}

std::tuple<PixelFormat, BufferUsage, Dataspace, int32_t>
SurfaceCamera::overrideStreamParams(PixelFormat format, BufferUsage usage,
                                    Dataspace dataspace) const {
  if (format == PixelFormat::RAW16) {
    return {format, usage, dataspace, kErrorBadFormat};
  }
  return BaseQemuCamera::overrideStreamParams(format, usage, dataspace);
}

Span<const PixelFormat> SurfaceCamera::getSupportedPixelFormats() const {
  static constexpr PixelFormat formats[] = {
      PixelFormat::IMPLEMENTATION_DEFINED,
      PixelFormat::YCBCR_420_888,
      PixelFormat::RGBA_8888,
      PixelFormat::BLOB,
  };
  return formats;
}

uint32_t SurfaceCamera::getAvailableCapabilitiesBitmap() const {
  return (1U << ANDROID_REQUEST_AVAILABLE_CAPABILITIES_BACKWARD_COMPATIBLE) |
         (1U << ANDROID_REQUEST_AVAILABLE_CAPABILITIES_READ_SENSOR_SETTINGS);
}

std::tuple<int32_t, int32_t, int32_t>
SurfaceCamera::getMaxNumOutputStreams() const {
  return {0, 2, 1}; // one JPEG stall stream, plus up to two processed streams.
}

bool SurfaceCamera::configure(const CameraMetadata &sessionParams,
                              size_t nStreams, const Stream *streams,
                              const HalStream *halStreams) {
  if (nStreams == 0)
    return false;
  std::vector<StreamInfo> streamInfo;
  streamInfo.reserve(nStreams);
  for (size_t i = 0; i < nStreams; ++i) {
    if (streams[i].id != halStreams[i].id || streams[i].width <= 0 ||
        streams[i].height <= 0 || (streams[i].width & 1) ||
        (streams[i].height & 1) || streams[i].width > kCaptureWidth ||
        streams[i].height > kCaptureHeight) {
      return false;
    }
    if (halStreams[i].overrideFormat != PixelFormat::BLOB &&
        halStreams[i].overrideFormat != PixelFormat::YCBCR_420_888 &&
        halStreams[i].overrideFormat != PixelFormat::RGBA_8888)
      return false;
    streamInfo.push_back({streams[i].id, halStreams[i].overrideFormat,
                          static_cast<uint32_t>(streams[i].width),
                          static_cast<uint32_t>(streams[i].height),
                          static_cast<uint32_t>(streams[i].bufferSize)});
  }

  // Surface's Windows camera stack serializes its front/rear sensors.
  // acquire() synchronously closes and releases the old source before it
  // issues OPEN for the new facing, including when old session teardown is
  // late.
  const std::string facing = mParams.isBackFacing ? "rear" : "front";
  if (!SurfaceCameraTransport::instance().acquire(this, facing, kCaptureWidth,
                                                  kCaptureHeight)) {
    ALOGE("Could not acquire the real Surface %s camera", facing.c_str());
    return false;
  }
  mStreams = std::move(streamInfo);
  applyMetadata(sessionParams);
  return true;
}

void SurfaceCamera::close() {
  SurfaceCameraTransport::instance().release(this);
  mStreams.clear();
}

std::tuple<int64_t, int64_t, CameraMetadata, std::vector<StreamBuffer>,
           std::vector<DelayedStreamBuffer>>
SurfaceCamera::processCaptureRequest(CameraMetadata metadataUpdate,
                                     Span<CachedStreamBuffer *> buffers) {
  static std::atomic<uint32_t> debugRequestCount{0};
  const uint32_t debugRequest = ++debugRequestCount;
  CameraMetadata resultMetadata =
      metadataUpdate.metadata.empty()
          ? updateCaptureResultMetadata()
          : applyMetadata(std::move(metadataUpdate));
  std::vector<StreamBuffer> outputBuffers;
  std::vector<DelayedStreamBuffer> delayedBuffers;
  outputBuffers.reserve(buffers.size());

  Nv12Frame frame;
  const bool haveFrame =
      SurfaceCameraTransport::instance().capture(this, &frame);
  if (debugRequest <= 8) {
    ALOGI("Surface camera frame request=%u available=%d size=%ux%u buffers=%zu",
          debugRequest, haveFrame, frame.width, frame.height, buffers.size());
  }
  if (haveFrame) {
    metadataSetShutterTimestamp(&resultMetadata,
                                systemTime(SYSTEM_TIME_MONOTONIC));
  }

  for (CachedStreamBuffer *buffer : buffers) {
    const bool fenceReady =
        buffer && haveFrame &&
        buffer->waitAcquireFence(mFrameDurationNs / 2000000);
    if (debugRequest <= 8) {
      ALOGI("Surface camera request=%u buffer=%p stream=%d fenceReady=%d",
            debugRequest, buffer,
            buffer ? buffer->getStreamId() : -1, fenceReady);
    }
    if (!buffer || !haveFrame || !fenceReady) {
      if (buffer)
        outputBuffers.push_back(buffer->finish(false));
      continue;
    }
    const int32_t streamId = buffer->getStreamId();
    const auto stream = std::find_if(mStreams.begin(), mStreams.end(),
                                     [streamId](const StreamInfo &candidate) {
                                       return candidate.id == streamId;
                                     });
    if (stream == mStreams.end()) {
      if (debugRequest <= 8) {
        ALOGI("Surface camera request=%u has unknown stream=%d", debugRequest,
              streamId);
      }
      outputBuffers.push_back(buffer->finish(false));
      continue;
    }

    bool success = false;
    const native_handle_t *handle = buffer->getBuffer();
    if (stream->format == PixelFormat::YCBCR_420_888) {
      android_ycbcr ycbcr{};
      if (GraphicBufferMapper::get().lockYCbCr(
              handle, static_cast<uint64_t>(BufferUsage::CPU_WRITE_OFTEN),
              {stream->width, stream->height}, &ycbcr) == NO_ERROR) {
        success = copyToYuv(frame, stream->width, stream->height, ycbcr);
        if (GraphicBufferMapper::get().unlock(handle) != NO_ERROR)
          success = false;
      }
    } else if (stream->format == PixelFormat::RGBA_8888) {
      void *pixels = nullptr;
      const status_t lockStatus = GraphicBufferMapper::get().lock(
          handle, static_cast<uint64_t>(BufferUsage::CPU_WRITE_OFTEN),
          {stream->width, stream->height}, &pixels);
      uint32_t dstStride = 0;
      const status_t strideStatus =
          GraphicBufferMapper::get().getStride(handle, &dstStride);
      if (debugRequest <= 8) {
        ALOGI("Surface camera RGBA request=%u lock=%d strideStatus=%d pixels=%p stride=%u",
              debugRequest, lockStatus, strideStatus, pixels, dstStride);
      }
      if (lockStatus == NO_ERROR && strideStatus == NO_ERROR &&
          dstStride >= stream->width) {
        success = copyToRgba(frame, stream->width, stream->height, dstStride,
                             static_cast<uint8_t *>(pixels));
        if (GraphicBufferMapper::get().unlock(handle) != NO_ERROR)
          success = false;
      } else if (pixels) {
        GraphicBufferMapper::get().unlock(handle);
      }
    } else if (stream->format == PixelFormat::BLOB) {
      if (stream->blobBufferSize > 0) {
        std::vector<uint8_t> yuvPixels;
        android_ycbcr ycbcr{};
        const Rect<uint16_t> imageSize{
            static_cast<uint16_t>(stream->width),
            static_cast<uint16_t>(stream->height)};
        if (copyToScaledNv12(frame, stream->width, stream->height, &yuvPixels,
                             &ycbcr)) {
          success = compressJpeg(imageSize, ycbcr, resultMetadata, handle,
                                 stream->blobBufferSize);
        }
      }
    }
    if (debugRequest <= 8) {
      ALOGI("Surface camera request=%u stream=%d format=%u size=%ux%u success=%d",
            debugRequest, streamId, static_cast<uint32_t>(stream->format),
            stream->width, stream->height, success);
    }
    outputBuffers.push_back(buffer->finish(success));
  }

  return std::make_tuple(haveFrame ? mFrameDurationNs : FAILURE(-1),
                         mSensorExposureDurationNs, std::move(resultMetadata),
                         std::move(outputBuffers), std::move(delayedBuffers));
}

} // namespace android::hardware::camera::provider::implementation::hw
