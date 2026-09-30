/*
 * Copyright (C) 2026 The KikiAOSP Project
 * SPDX-License-Identifier: Apache-2.0
 */

#include <memory>
#include <vector>

#include "BaseQemuCamera.h"
#include "HwCamera.h"
#include "SurfaceCamera.h"
#include "service_entry.h"

using android::hardware::camera::provider::implementation::serviceEntry;
using android::hardware::camera::provider::implementation::Span;
using android::hardware::camera::provider::implementation::hw::BaseQemuCamera;
using android::hardware::camera::provider::implementation::hw::HwCameraFactory;

namespace {
// Windows supplies upright, landscape NV12 frames for both Surface cameras.
// SENSOR_ORIENTATION describes these delivered pixels, not the virtual phone's
// portrait-shaped window. Reporting the old phone-style 270 degrees rotates an
// already upright image sideways. Let Android handle front-camera mirroring.
constexpr int32_t kWindowsFrameSensorOrientation = 0;

const BaseQemuCamera::Parameters kRearParameters{
    "Surface Camera Rear", {{320, 240}, {352, 288}, {640, 480}}, {{0, 0}, {160, 120}}, {640, 480}, true, kWindowsFrameSensorOrientation};

const BaseQemuCamera::Parameters kFrontParameters{
    "Surface Camera Front", {{320, 240}, {352, 288}, {640, 480}}, {{0, 0}, {160, 120}}, {640, 480}, false, kWindowsFrameSensorOrientation};
} // namespace

int main() {
  std::vector<HwCameraFactory> cameras;
  cameras.emplace_back([] {
    return std::make_unique<
        android::hardware::camera::provider::implementation::hw::SurfaceCamera>(
        kRearParameters);
  });
  cameras.emplace_back([] {
    return std::make_unique<
        android::hardware::camera::provider::implementation::hw::SurfaceCamera>(
        kFrontParameters);
  });

  return serviceEntry(
      0, Span<const HwCameraFactory>(cameras.begin(), cameras.end()), 4);
}
