#import "MetalPresentation.h"
#import <Metal/Metal.h>
#include "metal_window.h"
#include <atomic>
#include <mutex>

namespace {
struct Presentation {
    ut3_metal_window window;
    CAMetalLayer *layer;
    std::atomic<uint64_t> extent{0};
    std::atomic<unsigned> refs{1};
};
std::mutex presentationMutex;
Presentation *attached;
std::atomic<bool> hasPresented{false};

int read_extent(void *context, uint32_t *width, uint32_t *height)
{
    auto packed = static_cast<Presentation *>(context)->extent.load(std::memory_order_acquire);
    *width = uint32_t(packed >> 32);
    *height = uint32_t(packed);
    return *width && *height;
}

void release(Presentation *p)
{
    if (p && p->refs.fetch_sub(1, std::memory_order_acq_rel) == 1) delete p;
}
}

extern "C" int ut3_apple_metal_attach(CAMetalLayer *layer)
{
    layer.device = MTLCreateSystemDefaultDevice();
    if (!layer.device) return 0;
    std::lock_guard lock(presentationMutex);
    if (attached) return 0;
    auto *p = new Presentation;
    p->layer = layer;
    p->window = {(__bridge const void *)layer, p, read_extent};
    attached = p;
    hasPresented.store(false,std::memory_order_release);
    return 1;
}

extern "C" void ut3_apple_metal_resize(uint32_t width, uint32_t height)
{
    std::lock_guard lock(presentationMutex);
    if (attached) attached->extent.store(uint64_t(width) << 32 | height, std::memory_order_release);
}

extern "C" void ut3_apple_metal_detach(void)
{
    Presentation *p;
    {
        std::lock_guard lock(presentationMutex);
        p = attached;
        attached = nullptr;
        if (p) p->extent.store(0, std::memory_order_release);
    }
    release(p);
}

extern "C" void *ut3_dxvk_native_window()
{
    std::lock_guard lock(presentationMutex);
    if (!attached || !attached->extent.load(std::memory_order_acquire)) return nullptr;
    attached->refs.fetch_add(1, std::memory_order_relaxed);
    return &attached->window;
}

extern "C" void *ut3_apple_metal_current()
{
    std::lock_guard lock(presentationMutex);
    return attached && attached->extent.load(std::memory_order_acquire) ? &attached->window : nullptr;
}

extern "C" void ut3_apple_metal_release(void *window)
{
    release(static_cast<Presentation *>(static_cast<ut3_metal_window *>(window)->context));
}

extern "C" void ut3_apple_frame_presented()
{
    if (!hasPresented.exchange(true,std::memory_order_acq_rel)) fprintf(stderr, "[dxvk] first Vulkan present accepted by the Apple WSI\n");
}

extern "C" int ut3_apple_metal_has_presented(void)
{
    return hasPresented.load(std::memory_order_acquire);
}
