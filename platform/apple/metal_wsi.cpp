/* Apple presentation driver for the pinned native DXVK build.
 * A HWND points at the shell's retained Metal presentation target. */
#include "wsi_platform.h"
#include "../util/util_error.h"
#include "metal_window.h"
#include <limits>
#include <atomic>
#include <vulkan/vulkan_metal.h>

using Ut3DisplayQuery = int (*)(uint32_t*, uint32_t*, uint32_t*);
using Ut3PresentNotify = void (*)(const void*, uint64_t, int32_t);
using Ut3WorkerEntry = void (*)();
static std::atomic<Ut3DisplayQuery> ut3DisplayQuery;
static std::atomic<Ut3PresentNotify> ut3PresentNotify;
static std::atomic<Ut3WorkerEntry> ut3WorkerEntry;
static std::atomic<PFN_vkGetInstanceProcAddr> ut3VulkanLoader;
extern "C" __attribute__((visibility("default"))) void ut3_dxvk_set_vulkan_loader(PFN_vkGetInstanceProcAddr loader) {
  ut3VulkanLoader.store(loader, std::memory_order_release);
}
extern "C" PFN_vkGetInstanceProcAddr ut3_dxvk_native_vulkan_loader() {
  return ut3VulkanLoader.load(std::memory_order_acquire);
}
extern "C" __attribute__((visibility("default"))) void ut3_dxvk_set_callbacks_v2(Ut3DisplayQuery display, Ut3PresentNotify present, Ut3WorkerEntry worker) {
  ut3DisplayQuery.store(display, std::memory_order_release);
  ut3PresentNotify.store(present, std::memory_order_release);
  ut3WorkerEntry.store(worker, std::memory_order_release);
}
extern "C" void ut3_dxvk_native_present_notify(const void* presenter, uint64_t frameId, int32_t result) {
  if (auto notify = ut3PresentNotify.load(std::memory_order_acquire)) notify(presenter, frameId, result);
}
extern "C" void ut3_dxvk_native_worker_enter() {
  if (auto enter = ut3WorkerEntry.load(std::memory_order_acquire)) enter();
}

namespace dxvk::wsi {
static HMONITOR virtualMonitor() { return reinterpret_cast<HMONITOR>(uintptr_t(1)); }
static bool displayMode(WsiMode* mode) {
  using GetMode = int (*)(uint32_t*, uint32_t*, uint32_t*);
  auto query = ut3DisplayQuery.load(std::memory_order_acquire);
  uint32_t width = 0, height = 0, refresh = 0;
  if (!mode || !query || query(&width, &height, &refresh) != 1 || !width || !height || !refresh
      || width > uint32_t(std::numeric_limits<int32_t>::max())
      || height > uint32_t(std::numeric_limits<int32_t>::max())) return false;
  *mode = {width, height, {refresh, 1}, 32, false};
  return true;
}
static bool monitorMode(HMONITOR monitor, WsiMode* mode) {
  return monitor == virtualMonitor() && displayMode(mode);
}
class AppleDriver final : public WsiDriver {
public:
  std::vector<const char*> getInstanceExtensions() override {
    return {VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME};
  }
  HMONITOR getDefaultMonitor() override { WsiMode mode; return displayMode(&mode) ? virtualMonitor() : nullptr; }
  HMONITOR enumMonitors(uint32_t index) override { return index ? nullptr : getDefaultMonitor(); }
  HMONITOR enumMonitors(const LUID*[], uint32_t, uint32_t index) override { return enumMonitors(index); }
  bool getDisplayName(HMONITOR monitor, WCHAR (&name)[32]) override {
    WsiMode mode;if (!monitorMode(monitor, &mode)) return false;
    for (auto& c : name) c = 0;
    const char text[] = "\\\\.\\DISPLAY1";
    for (size_t i = 0; i < sizeof(text) - 1; ++i) name[i] = WCHAR(text[i]);
    return true;
  }
  bool getDesktopCoordinates(HMONITOR monitor, RECT* rect) override {
    WsiMode mode;if (!rect || !monitorMode(monitor, &mode)) return false;
    *rect = {0, 0, LONG(mode.width), LONG(mode.height)};return true;
  }
  bool getDisplayMode(HMONITOR monitor, uint32_t index, WsiMode* mode) override {
    // D3D9 renders into a windowed back buffer, so these sizes are independent
    // of the host display's physical resolution or scale factor.
    static constexpr uint32_t resolutions[][2] = {
      {640, 480}, {800, 600}, {960, 540}, {1024, 768}, {1280, 720}, {1280, 1024},
      {1600, 900}, {1920, 1080}, {2560, 1440}
    };
    if (index >= std::size(resolutions) || !monitorMode(monitor, mode))
      return false;
    mode->width = resolutions[index][0];
    mode->height = resolutions[index][1];
    return true;
  }
  bool getCurrentDisplayMode(HMONITOR monitor, WsiMode* mode) override { return monitorMode(monitor, mode); }
  bool getDesktopDisplayMode(HMONITOR monitor, WsiMode* mode) override { return monitorMode(monitor, mode); }
  WsiEdidData getMonitorEdid(HMONITOR) override { return {}; }
  void getWindowSize(HWND w, uint32_t* width, uint32_t* height) override {
    const auto* window = static_cast<const ut3_metal_window*>(w);
    uint32_t wPixels = 0, hPixels = 0;
    if (window && window->read_drawable)
      window->read_drawable(window->context, &wPixels, &hPixels);
    if (width) *width = wPixels;
    if (height) *height = hPixels;
  }
  void resizeWindow(HWND window, DxvkWindowState*, uint32_t width, uint32_t height) override {
    WsiMode mode;
    if (window && displayMode(&mode) && width == mode.width && height == mode.height) return;
    throw DxvkError("Apple WSI: application-controlled resize is unsupported");
  }
  bool setWindowMode(HMONITOR, HWND, const WsiMode&) override { return false; }
  bool enterFullscreenMode(HMONITOR, HWND, DxvkWindowState*, bool) override { return false; }
  bool leaveFullscreenMode(HWND, DxvkWindowState*, bool) override { return false; }
  bool restoreDisplayMode() override { return false; }
  HMONITOR getWindowMonitor(HWND window) override { return window ? getDefaultMonitor() : nullptr; }
  bool isWindow(HWND w) override { return w != nullptr; }
  bool isMinimized(HWND w) override {
    uint32_t width, height;
    getWindowSize(w, &width, &height);
    return !width || !height;
  }
  bool isOccluded(HWND w) override { return isMinimized(w); }
  void updateFullscreenWindow(HMONITOR, HWND, bool) override {
    throw DxvkError("Apple WSI: fullscreen display control is unsupported");
  }
  VkResult createSurface(HWND w, PFN_vkGetInstanceProcAddr gipa,
                         VkInstance instance, VkSurfaceKHR* surface) override {
    const auto* window = static_cast<const ut3_metal_window*>(w);
    if (!window || !window->layer || !surface || !gipa) return VK_ERROR_INITIALIZATION_FAILED;
    auto create = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
      gipa(instance, "vkCreateMetalSurfaceEXT"));
    if (!create) return VK_ERROR_EXTENSION_NOT_PRESENT;
    VkMetalSurfaceCreateInfoEXT info = {VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    info.pLayer = static_cast<const CAMetalLayer*>(window->layer);
    return create(instance, &info, nullptr, surface);
  }
};
static bool createAppleDriver(WsiDriver** driver) {
  *driver = new AppleDriver();
  return true;
}
WsiBootstrap AppleWSI = {"Apple", createAppleDriver};
}
