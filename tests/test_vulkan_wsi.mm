// Standalone AppKit/Vulkan presentation check. The game and DXVK are absent.
#if defined(UT3_VULKAN_PROBE_LIBRARY)
#import <Foundation/Foundation.h>
#else
#import <AppKit/AppKit.h>
#endif
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <vector>

static void check(VkResult status, const char *call)
{
    if (status < 0) {
        fprintf(stderr, "%s failed with VkResult %d\n", call, status);
        throw std::runtime_error(call);
    }
}

template <typename T, typename Enumerate>
static std::vector<T> enumerate(Enumerate query)
{
    uint32_t count = 0;
    check(query(&count, nullptr), "enumerate count");
    std::vector<T> values(count);
    check(query(&count, values.data()), "enumerate values");
    values.resize(count);
    return values;
}

static bool has(const std::vector<VkExtensionProperties> &extensions, const char *name)
{
    return std::any_of(extensions.begin(), extensions.end(), [&](const auto &extension) {
        return !strcmp(extension.extensionName, name);
    });
}

struct Probe {
    VkInstance instance{};
    VkSurfaceKHR surface{};
    VkDevice device{};
    VkSwapchainKHR swapchain{};
    VkCommandPool pool{};
    VkFence acquired{};
    VkSemaphore complete{};
    VkBuffer buffer{};
    VkDeviceMemory memory{};
    void *mapped{};

    ~Probe()
    {
        if (device) {
            vkDeviceWaitIdle(device);
            if (mapped) vkUnmapMemory(device, memory);
            if (buffer) vkDestroyBuffer(device, buffer, nullptr);
            if (memory) vkFreeMemory(device, memory, nullptr);
            if (complete) vkDestroySemaphore(device, complete, nullptr);
            if (acquired) vkDestroyFence(device, acquired, nullptr);
            if (pool) vkDestroyCommandPool(device, pool, nullptr);
            if (swapchain) vkDestroySwapchainKHR(device, swapchain, nullptr);
            vkDestroyDevice(device, nullptr);
        }
        if (surface) vkDestroySurfaceKHR(instance, surface, nullptr);
        if (instance) vkDestroyInstance(instance, nullptr);
    }
};

static void present(CAMetalLayer *layer, const char *output)
{
    Probe p;
    auto instanceCaps = enumerate<VkExtensionProperties>([](auto count, auto values) {
        return vkEnumerateInstanceExtensionProperties(nullptr, count, values);
    });
    for (auto name : {VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME})
        if (!has(instanceCaps, name)) throw std::runtime_error(name);
    std::vector<const char *> instanceExtensions{VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME};
    VkInstanceCreateFlags flags = 0;
    if (has(instanceCaps, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)) {
        instanceExtensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "UT3 Metal Surface Probe";
    app.apiVersion = VK_API_VERSION_1_3;
    VkInstanceCreateInfo instanceInfo{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instanceInfo.pApplicationInfo = &app;
    instanceInfo.flags = flags;
    instanceInfo.enabledExtensionCount = uint32_t(instanceExtensions.size());
    instanceInfo.ppEnabledExtensionNames = instanceExtensions.data();
    check(vkCreateInstance(&instanceInfo, nullptr, &p.instance), "vkCreateInstance");

    auto createSurface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        vkGetInstanceProcAddr(p.instance, "vkCreateMetalSurfaceEXT"));
    if (!createSurface) throw std::runtime_error("vkCreateMetalSurfaceEXT unavailable");
    VkMetalSurfaceCreateInfoEXT surfaceInfo{VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    surfaceInfo.pLayer = layer;
    check(createSurface(p.instance, &surfaceInfo, nullptr, &p.surface), "vkCreateMetalSurfaceEXT");

    auto adapters = enumerate<VkPhysicalDevice>([&](auto count, auto values) {
        return vkEnumeratePhysicalDevices(p.instance, count, values);
    });
    VkPhysicalDevice adapter = VK_NULL_HANDLE;
    uint32_t family = 0;
    for (auto candidate : adapters) {
        auto queues = enumerate<VkQueueFamilyProperties>([&](auto count, auto values) {
            vkGetPhysicalDeviceQueueFamilyProperties(candidate, count, values);
            return VK_SUCCESS;
        });
        for (uint32_t i = 0; i < queues.size(); ++i) {
            VkBool32 supported = false;
            check(vkGetPhysicalDeviceSurfaceSupportKHR(candidate, i, p.surface, &supported), "present queue");
            if (supported && (queues[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
                adapter = candidate;
                family = i;
                break;
            }
        }
        if (adapter) break;
    }
    if (!adapter) throw std::runtime_error("no graphics/present queue");

    auto deviceCaps = enumerate<VkExtensionProperties>([&](auto count, auto values) {
        return vkEnumerateDeviceExtensionProperties(adapter, nullptr, count, values);
    });
    VkPhysicalDeviceDriverProperties driver{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES};
    VkPhysicalDeviceProperties2 properties{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &driver};
    vkGetPhysicalDeviceProperties2(adapter, &properties);
    const auto api = properties.properties.apiVersion;
    printf("Driver: %s (%s), device: %s, Vulkan %u.%u.%u\n", driver.driverName, driver.driverInfo,
           properties.properties.deviceName, VK_API_VERSION_MAJOR(api), VK_API_VERSION_MINOR(api), VK_API_VERSION_PATCH(api));
    for (const auto &extension : deviceCaps) printf("Device extension: %s\n", extension.extensionName);
    VkPhysicalDeviceFeatures features;
    vkGetPhysicalDeviceFeatures(adapter, &features);
    printf("Features: textureCompressionBC=%d occlusionQueryPrecise=%d\n",
           features.textureCompressionBC, features.occlusionQueryPrecise);
    VkPhysicalDeviceRobustness2FeaturesEXT robust{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
    if (has(deviceCaps, "VK_EXT_robustness2") || has(deviceCaps, "VK_KHR_robustness2")) {
        VkPhysicalDeviceFeatures2 chain{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &robust};
        vkGetPhysicalDeviceFeatures2(adapter, &chain);
        printf("Robustness2: robustBufferAccess2=%d robustImageAccess2=%d nullDescriptor=%d\n",
               robust.robustBufferAccess2, robust.robustImageAccess2, robust.nullDescriptor);
    }
    for (auto format : {VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_R16G16B16A16_SFLOAT, VK_FORMAT_D24_UNORM_S8_UINT,
                        VK_FORMAT_D32_SFLOAT_S8_UINT, VK_FORMAT_BC1_RGBA_UNORM_BLOCK, VK_FORMAT_BC2_UNORM_BLOCK,
                        VK_FORMAT_BC3_UNORM_BLOCK, VK_FORMAT_BC4_UNORM_BLOCK, VK_FORMAT_BC5_UNORM_BLOCK}) {
        VkFormatProperties caps;
        vkGetPhysicalDeviceFormatProperties(adapter, format, &caps);
        printf("Format %d optimal features: %#x\n", format, caps.optimalTilingFeatures);
    }

    const float priority = 1;
    VkDeviceQueueCreateInfo queueInfo{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queueInfo.queueFamilyIndex = family;
    queueInfo.queueCount = 1;
    queueInfo.pQueuePriorities = &priority;
    std::vector<const char *> deviceExtensions{VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    if (has(deviceCaps, "VK_KHR_portability_subset")) deviceExtensions.push_back("VK_KHR_portability_subset");
    VkDeviceCreateInfo deviceInfo{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    deviceInfo.queueCreateInfoCount = 1;
    deviceInfo.pQueueCreateInfos = &queueInfo;
    deviceInfo.enabledExtensionCount = uint32_t(deviceExtensions.size());
    deviceInfo.ppEnabledExtensionNames = deviceExtensions.data();
    check(vkCreateDevice(adapter, &deviceInfo, nullptr, &p.device), "vkCreateDevice");
    VkQueue queue;
    vkGetDeviceQueue(p.device, family, 0, &queue);

    VkSurfaceCapabilitiesKHR caps;
    check(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(adapter, p.surface, &caps), "surface capabilities");
    auto formats = enumerate<VkSurfaceFormatKHR>([&](auto count, auto values) {
        return vkGetPhysicalDeviceSurfaceFormatsKHR(adapter, p.surface, count, values);
    });
    auto format = std::find_if(formats.begin(), formats.end(), [](auto value) {
        return value.format == VK_FORMAT_B8G8R8A8_UNORM || value.format == VK_FORMAT_R8G8B8A8_UNORM;
    });
    if (format == formats.end()) throw std::runtime_error("no 8-bit UNORM surface format");
    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX) {
        extent.width = std::clamp(uint32_t(layer.drawableSize.width), caps.minImageExtent.width, caps.maxImageExtent.width);
        extent.height = std::clamp(uint32_t(layer.drawableSize.height), caps.minImageExtent.height, caps.maxImageExtent.height);
    }
    constexpr auto usage = VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if ((caps.supportedUsageFlags & usage) != usage) throw std::runtime_error("swapchain transfer usage unavailable");
    VkSwapchainCreateInfoKHR swapInfo{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    swapInfo.surface = p.surface;
    swapInfo.minImageCount = caps.minImageCount;
    swapInfo.imageFormat = format->format;
    swapInfo.imageColorSpace = format->colorSpace;
    swapInfo.imageExtent = extent;
    swapInfo.imageArrayLayers = 1;
    swapInfo.imageUsage = usage;
    swapInfo.preTransform = caps.currentTransform;
    swapInfo.compositeAlpha = VkCompositeAlphaFlagBitsKHR(caps.supportedCompositeAlpha & -caps.supportedCompositeAlpha);
    swapInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    swapInfo.clipped = VK_TRUE;
    check(vkCreateSwapchainKHR(p.device, &swapInfo, nullptr, &p.swapchain), "vkCreateSwapchainKHR");
    auto images = enumerate<VkImage>([&](auto count, auto values) {
        return vkGetSwapchainImagesKHR(p.device, p.swapchain, count, values);
    });

    const VkDeviceSize bytes = VkDeviceSize(extent.width) * extent.height * 4;
    VkBufferCreateInfo bufferInfo{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bufferInfo.size = bytes;
    bufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    check(vkCreateBuffer(p.device, &bufferInfo, nullptr, &p.buffer), "vkCreateBuffer");
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(p.device, p.buffer, &requirements);
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(adapter, &memProperties);
    uint32_t memoryIndex = 0;
    constexpr auto cpuMemory = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    for (; memoryIndex < memProperties.memoryTypeCount; ++memoryIndex)
        if ((requirements.memoryTypeBits & (1u << memoryIndex)) &&
            (memProperties.memoryTypes[memoryIndex].propertyFlags & cpuMemory) == cpuMemory) break;
    if (memoryIndex == memProperties.memoryTypeCount) throw std::runtime_error("no coherent readback memory");
    VkMemoryAllocateInfo alloc{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    alloc.allocationSize = requirements.size;
    alloc.memoryTypeIndex = memoryIndex;
    check(vkAllocateMemory(p.device, &alloc, nullptr, &p.memory), "vkAllocateMemory");
    check(vkBindBufferMemory(p.device, p.buffer, p.memory, 0), "vkBindBufferMemory");
    check(vkMapMemory(p.device, p.memory, 0, bytes, 0, &p.mapped), "vkMapMemory");

    VkCommandPoolCreateInfo poolInfo{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    poolInfo.queueFamilyIndex = family;
    check(vkCreateCommandPool(p.device, &poolInfo, nullptr, &p.pool), "vkCreateCommandPool");
    VkCommandBufferAllocateInfo cmdAlloc{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cmdAlloc.commandPool = p.pool;
    cmdAlloc.commandBufferCount = 1;
    VkCommandBuffer commands;
    check(vkAllocateCommandBuffers(p.device, &cmdAlloc, &commands), "vkAllocateCommandBuffers");
    VkFenceCreateInfo fenceInfo{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkSemaphoreCreateInfo semaphoreInfo{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    check(vkCreateFence(p.device, &fenceInfo, nullptr, &p.acquired), "vkCreateFence");
    check(vkCreateSemaphore(p.device, &semaphoreInfo, nullptr, &p.complete), "vkCreateSemaphore");
    uint32_t index;
    VkResult acquired = vkAcquireNextImageKHR(p.device, p.swapchain, 1000000000, VK_NULL_HANDLE, p.acquired, &index);
    if (acquired != VK_SUCCESS && acquired != VK_SUBOPTIMAL_KHR) throw std::runtime_error("swapchain acquire failed");
    if (vkWaitForFences(p.device, 1, &p.acquired, VK_TRUE, 1000000000) != VK_SUCCESS)
        throw std::runtime_error("swapchain acquire fence did not signal");

    VkCommandBufferBeginInfo begin{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(vkBeginCommandBuffer(commands, &begin), "vkBeginCommandBuffer");
    VkImageSubresourceRange color{VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    auto transition = [&](VkImageLayout oldLayout, VkImageLayout newLayout, VkAccessFlags srcAccess,
                          VkAccessFlags dstAccess, VkPipelineStageFlags src, VkPipelineStageFlags dst) {
        VkImageMemoryBarrier barrier{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};
        barrier.oldLayout = oldLayout;
        barrier.newLayout = newLayout;
        barrier.srcAccessMask = srcAccess;
        barrier.dstAccessMask = dstAccess;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = images[index];
        barrier.subresourceRange = color;
        vkCmdPipelineBarrier(commands, src, dst, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    };
    transition(VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 0, VK_ACCESS_TRANSFER_WRITE_BIT,
               VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
    VkClearColorValue clear{{37.f / 255, 160.f / 255, 123.f / 255, 1.f}};
    vkCmdClearColorImage(commands, images[index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clear, 1, &color);
    transition(VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_ACCESS_TRANSFER_WRITE_BIT,
               VK_ACCESS_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT);
    VkBufferImageCopy copy{};
    copy.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    copy.imageExtent = {extent.width, extent.height, 1};
    vkCmdCopyImageToBuffer(commands, images[index], VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, p.buffer, 1, &copy);
    transition(VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, VK_ACCESS_TRANSFER_READ_BIT, 0,
               VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
    check(vkEndCommandBuffer(commands), "vkEndCommandBuffer");
    VkSubmitInfo submit{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &commands;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &p.complete;
    check(vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE), "vkQueueSubmit");
    VkPresentInfoKHR info{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    info.waitSemaphoreCount = 1;
    info.pWaitSemaphores = &p.complete;
    info.swapchainCount = 1;
    info.pSwapchains = &p.swapchain;
    info.pImageIndices = &index;
    check(vkQueuePresentKHR(queue, &info), "vkQueuePresentKHR");
    check(vkQueueWaitIdle(queue), "present queue idle");

    bool bgra = format->format == VK_FORMAT_B8G8R8A8_UNORM;
    const auto *pixels = static_cast<const uint8_t *>(p.mapped);
    std::vector<char> rgb(bytes / 4 * 3);
    for (size_t i = 0; i < bytes / 4; ++i) {
        rgb[3*i] = char(pixels[4*i+(bgra ? 2 : 0)]);
        rgb[3*i+1] = char(pixels[4*i+1]);
        rgb[3*i+2] = char(pixels[4*i+(bgra ? 0 : 2)]);
        if (uint8_t(rgb[3*i]) != 37 || uint8_t(rgb[3*i+1]) != 160 || uint8_t(rgb[3*i+2]) != 123)
            throw std::runtime_error("clear did not reach swapchain image readback");
    }
    std::ofstream image(output, std::ios::binary);
    image << "P6\n" << extent.width << ' ' << extent.height << "\n255\n";
    image.write(rgb.data(), rgb.size());
    if (!image) throw std::runtime_error("could not write readback");
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
    printf("VULKAN METAL PRESENT PASS: %ux%u, RGB 37 160 123\n", extent.width, extent.height);
}

#if defined(UT3_VULKAN_PROBE_LIBRARY)
extern "C" int ut3_apple_validate_vulkan(CAMetalLayer *layer, const char *output)
{
    try { present(layer, output); }
    catch (const std::exception &error) { fprintf(stderr, "FAIL: %s\n", error.what()); return 1; }
    return 0;
}
#else
int main(int argc, const char **argv)
{
    if (argc != 2) { fprintf(stderr, "usage: test-vulkan-wsi output.ppm\n"); return 64; }
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (!NSScreen.screens.count) return 69;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
                                                     styleMask:NSWindowStyleMaskTitled
                                                       backing:NSBackingStoreBuffered defer:NO];
        window.title = @"UT3 Vulkan Metal Surface Probe";
        window.releasedWhenClosed = NO;
        NSView *view = window.contentView;
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = MTLCreateSystemDefaultDevice();
        layer.delegate = (id)view;
        view.layer = layer;
        view.wantsLayer = YES;
        [window center];
        [NSApp activate];
        [window makeKeyAndOrderFront:nil];
        layer.contentsScale = window.backingScaleFactor;
        layer.drawableSize = [view convertSizeToBacking:view.bounds.size];
        [CATransaction flush];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
        int result = 0;
        try { present(layer, argv[1]); }
        catch (const std::exception &error) { fprintf(stderr, "FAIL: %s\n", error.what()); result = 1; }
        [window close];
        return result;
    }
}
#endif
