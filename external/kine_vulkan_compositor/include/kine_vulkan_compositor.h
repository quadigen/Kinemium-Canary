#ifndef KINE_VULKAN_COMPOSITOR_H
#define KINE_VULKAN_COMPOSITOR_H

#include <stdint.h>

#if defined(_WIN32)
  #if defined(KINE_VULKAN_COMPOSITOR_BUILD_EXPORTS)
    #define KINE_VULKAN_COMPOSITOR_API __declspec(dllexport)
  #else
    #define KINE_VULKAN_COMPOSITOR_API __declspec(dllimport)
  #endif
#else
  #define KINE_VULKAN_COMPOSITOR_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KineVulkanCompositor KineVulkanCompositor;

typedef struct KineVulkanCompositorInfo {
    void* instance;
    void* surface;
    void* physicalDevice;
    void* device;
    void* graphicsQueue;
    void* swapchain;
    uint32_t swapchainFormat;
    uint32_t swapchainImageCount;
    uint32_t graphicsQueueFamilyIndex;
    uint32_t graphicsQueueCount;
    uint32_t width;
    uint32_t height;
} KineVulkanCompositorInfo;

typedef struct KineVulkanCompositorBackend {
    void* instance;
    void* physicalDevice;
    void* device;
    void* queue;
    uint32_t graphicsQueueFamilyIndex;
    uint32_t maxApiVersion;
    void* getInstanceProcAddr;
    void* getDeviceProcAddr;
} KineVulkanCompositorBackend;

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindow(void* sdlWindow, int width, int height);

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
    void* sdlWindow,
    int width,
    int height,
    const KineVulkanCompositorBackend* backend);

KINE_VULKAN_COMPOSITOR_API void
Kine_VulkanCompositor_Destroy(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_Resize(
    KineVulkanCompositor* compositor,
    int width,
    int height);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsReady(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API const char*
Kine_VulkanCompositor_GetLastError(const KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetInfo(
    const KineVulkanCompositor* compositor,
    KineVulkanCompositorInfo* outInfo);

/* Returns the KineSkiaVulkanContext owned by the compositor. */
KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetSkiaContext(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetCurrentSkiaSurface(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetSwapchainImages(
    KineVulkanCompositor* compositor,
    void** outImages,
    uint32_t maxImages);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetDepthAttachment(
    KineVulkanCompositor* compositor,
    void** outImage,
    uint32_t* outFormat);

/* Flushes Skia and prepares the active swapchain image for Filament. Call on
   the render thread before Filament Renderer::beginFrame. */
KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_PrepareFilament(KineVulkanCompositor* compositor);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentAcquire(
    KineVulkanCompositor* compositor,
    uint32_t* outImageIndex,
    void** outImageReadySemaphore);

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentPresent(
    KineVulkanCompositor* compositor,
    uint32_t imageIndex,
    void* finishedDrawingSemaphore);

/* Acquires the next swapchain image and returns a KineSkiaSurface that draws
   directly into it. The surface is owned by the compositor until EndFrame. */
KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginFrame(KineVulkanCompositor* compositor);

/* Waits for Filament to finish rendering the active image, then returns a
   separate Skia surface for UI that must appear above the 3D scene. */
KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginOverlay(KineVulkanCompositor* compositor);

/* Flushes Skia work, transitions the image to present layout, and presents. */
KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_EndFrame(KineVulkanCompositor* compositor);

#ifdef __cplusplus
}
#endif

#endif
