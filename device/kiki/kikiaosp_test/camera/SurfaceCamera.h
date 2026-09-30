/*
 * Copyright (C) 2026 The KikiAOSP Project
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once

#include <vector>

#include "BaseQemuCamera.h"

namespace android::hardware::camera::provider::implementation::hw {

class SurfaceCamera final : public BaseQemuCamera {
public:
  explicit SurfaceCamera(const Parameters &params);

  std::tuple<PixelFormat, BufferUsage, Dataspace, int32_t>
      overrideStreamParams(PixelFormat, BufferUsage, Dataspace) const override;
  Span<const PixelFormat> getSupportedPixelFormats() const override;
  uint32_t getAvailableCapabilitiesBitmap() const override;
  std::tuple<int32_t, int32_t, int32_t> getMaxNumOutputStreams() const override;

  bool configure(const CameraMetadata &, size_t, const Stream *,
                 const HalStream *) override;
  void close() override;
  std::tuple<int64_t, int64_t, CameraMetadata, std::vector<StreamBuffer>,
             std::vector<DelayedStreamBuffer>>
      processCaptureRequest(CameraMetadata,
                            Span<CachedStreamBuffer *>) override;

private:
  struct StreamInfo {
    int32_t id;
    PixelFormat format;
    uint32_t width;
    uint32_t height;
    uint32_t blobBufferSize;
  };
  std::vector<StreamInfo> mStreams;
};

} // namespace android::hardware::camera::provider::implementation::hw
