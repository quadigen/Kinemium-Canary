#include "kine_skia.h"

#include "include/core/SkCanvas.h"
#include "include/core/SkBlendMode.h"
#include "include/core/SkBlurTypes.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkColor.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkRRect.h"
#include "include/core/SkRect.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTextBlob.h"
#include "include/core/SkTileMode.h"
#include "include/core/SkFontScanner.h"
#include "include/core/SkTypeface.h"
#include "include/core/SkPathBuilder.h"
#include "include/core/SkFontMetrics.h"
#include "include/core/SkMaskFilter.h"
#include "include/effects/SkImageFilters.h"
#if defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#elif defined(__APPLE__)
#include "include/ports/SkFontMgr_mac_ct.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif
#include "modules/skshaper/include/SkShaper.h"
#include "modules/skshaper/include/SkShaper_skunicode.h"
#include "modules/skshaper/include/SkShaper_harfbuzz.h"

#ifndef KINE_SKIA_BUILD_VULKAN
#define KINE_SKIA_BUILD_VULKAN 0
#endif

#if KINE_SKIA_BUILD_VULKAN
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/vk/GrVkBackendSurface.h"
#include "include/gpu/ganesh/vk/GrVkDirectContext.h"
#include "include/gpu/ganesh/vk/GrVkTypes.h"
#include "include/gpu/vk/VulkanBackendContext.h"
#include "include/gpu/vk/VulkanTypes.h"
#include "include/private/gpu/vk/SkiaVulkan.h"
#include "src/gpu/GpuTypesPriv.h"
#include "src/gpu/vk/vulkanmemoryallocator/VulkanMemoryAllocatorPriv.h"
#endif

#include <cstdio>
#include <cstring>
#include <algorithm>
#include <cmath>
#include <string>
#include <unordered_map>
#include <utility>

struct KineSkiaSurface {
    sk_sp<SkSurface> surface;
    sk_sp<SkImage> backdrop;
#if KINE_SKIA_BUILD_VULKAN
    sk_sp<GrDirectContext> vulkanContext;
    GrBackendRenderTarget vulkanRenderTarget;
#endif
};

struct KineSkiaImage {
    sk_sp<SkImage> image;
};

struct KineSkiaVulkanContext {
#if KINE_SKIA_BUILD_VULKAN
    sk_sp<GrDirectContext> context;
    KineSkiaVulkanBackend backend;
#endif
};

/* ---------------- Paint helpers ---------------- */

static SkPaint kine_skia_paint(uint8_t r, uint8_t g, uint8_t b, uint8_t a, float strokeWidth)
{
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(SkColorSetARGB(a, r, g, b));
    if (strokeWidth > 0.0f) {
        paint.setStyle(SkPaint::kStroke_Style);
        paint.setStrokeWidth(strokeWidth);
    } else {
        paint.setStyle(SkPaint::kFill_Style);
    }
    return paint;
}

static SkPath kine_skia_squircle_path(
    float x, float y, float width, float height, float radius, float exponent)
{
    const float w = std::max(0.0f, width);
    const float h = std::max(0.0f, height);
    const float r = std::clamp(radius, 0.0f, std::min(w, h) * 0.5f);
    if (r <= 0.0f) {
        SkPathBuilder rectBuilder;
        rectBuilder.moveTo(x, y);
        rectBuilder.lineTo(x + w, y);
        rectBuilder.lineTo(x + w, y + h);
        rectBuilder.lineTo(x, y + h);
        rectBuilder.close();
        return rectBuilder.detach();
    }

    const float n = exponent > 0.0f ? std::max(2.0f, exponent) : 4.0f;
    const float power = 2.0f / n;

    SkPathBuilder builder;
    constexpr int kCornerSegments = 24;
    constexpr float kHalfPi = 1.57079632679f;

    auto cornerTo = [&](float cx, float cy, float start, float end) {
        for (int i = 1; i <= kCornerSegments; ++i) {
            const float t = start + (end - start) * (static_cast<float>(i) / kCornerSegments);
            const float c = std::cos(t);
            const float s = std::sin(t);
            const float px = cx + std::copysign(std::pow(std::abs(c), power) * r, c);
            const float py = cy + std::copysign(std::pow(std::abs(s), power) * r, s);
            builder.lineTo(px, py);
        }
    };

    builder.moveTo(x + r, y);
    builder.lineTo(x + w - r, y);
    cornerTo(x + w - r, y + r, -kHalfPi, 0.0f);
    builder.lineTo(x + w, y + h - r);
    cornerTo(x + w - r, y + h - r, 0.0f, kHalfPi);
    builder.lineTo(x + r, y + h);
    cornerTo(x + r, y + h - r, kHalfPi, 2.0f * kHalfPi);
    builder.lineTo(x, y + r);
    cornerTo(x + r, y + r, 2.0f * kHalfPi, 3.0f * kHalfPi);
    builder.close();
    return builder.detach();
}

/* ---------------- Font/typeface cache ---------------- */

static std::unordered_map<std::string, sk_sp<SkTypeface>>& kine_skia_typeface_cache()
{
    static std::unordered_map<std::string, sk_sp<SkTypeface>> cache;
    return cache;
}

static sk_sp<SkTypeface> kine_skia_get_typeface(const char* fontPath)
{
    std::string key = (fontPath && fontPath[0] != '\0') ? fontPath : "__default__";

    auto& cache = kine_skia_typeface_cache();
    auto it = cache.find(key);
    if (it != cache.end()) {
        return it->second;
    }

    #if defined(_WIN32)
        sk_sp<SkFontMgr> mgr = SkFontMgr_New_DirectWrite();
    #elif defined(__APPLE__)
        sk_sp<SkFontMgr> mgr = SkFontMgr_New_CoreText(nullptr);
    #else
        sk_sp<SkFontMgr> mgr = SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType());
    #endif
    sk_sp<SkTypeface> tf;

    if (fontPath && fontPath[0] != '\0') {
        tf = mgr->makeFromFile(fontPath, 0);
        if (!tf) {
            fprintf(stderr, "kine_skia: failed to load font '%s', falling back to default\n", fontPath);
        }
    }

    if (!tf) {
        tf = mgr->legacyMakeTypeface(nullptr, SkFontStyle());
    }

    cache[key] = tf;
    return tf;
}

extern "C" {

/* ---------------- Version ---------------- */

KINE_SKIA_API const char* Kine_Skia_GetVersion(void)
{
    return "kine_skia 0.2.0";
}

/* ---------------- Vulkan GPU context ---------------- */

KINE_SKIA_API KineSkiaVulkanContext* Kine_Skia_Vulkan_CreateContext(
    const KineSkiaVulkanBackend* backend)
{
    if (!backend || !backend->instance || !backend->physicalDevice || !backend->device ||
        !backend->queue || !backend->getInstanceProcAddr) {
        return nullptr;
    }

#if KINE_SKIA_BUILD_VULKAN
    auto* wrapper = new KineSkiaVulkanContext();
    wrapper->backend = *backend;

    auto getInstanceProc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend->getInstanceProcAddr);
    auto explicitGetDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(backend->getDeviceProcAddr);
    VkInstance backendInstance = reinterpret_cast<VkInstance>(backend->instance);

    skgpu::VulkanBackendContext vkContext;
    vkContext.fInstance = reinterpret_cast<VkInstance>(backend->instance);
    vkContext.fPhysicalDevice = reinterpret_cast<VkPhysicalDevice>(backend->physicalDevice);
    vkContext.fDevice = reinterpret_cast<VkDevice>(backend->device);
    vkContext.fQueue = reinterpret_cast<VkQueue>(backend->queue);
    vkContext.fGraphicsQueueIndex = backend->graphicsQueueFamilyIndex;
    vkContext.fMaxAPIVersion = backend->maxApiVersion;
    vkContext.fGetProc = [getInstanceProc, explicitGetDeviceProc, backendInstance](
        const char* procName,
        VkInstance instance,
        VkDevice device) -> PFN_vkVoidFunction {
        if (!procName || !getInstanceProc) {
            return nullptr;
        }
        if (device != VK_NULL_HANDLE) {
            PFN_vkGetDeviceProcAddr getDeviceProc = explicitGetDeviceProc;
            if (!getDeviceProc) {
                getDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
                    getInstanceProc(backendInstance, "vkGetDeviceProcAddr"));
            }
            if (getDeviceProc) {
                if (PFN_vkVoidFunction proc = getDeviceProc(device, procName)) {
                    return proc;
                }
            }
        }

        VkInstance lookupInstance = instance != VK_NULL_HANDLE ? instance : backendInstance;
        PFN_vkVoidFunction proc = getInstanceProc(lookupInstance, procName);
        if (!proc) {
            fprintf(stderr, "kine_skia: Vulkan procedure unavailable: %s\n", procName);
        }
        return proc;
    };

    vkContext.fMemoryAllocator =
        skgpu::VulkanMemoryAllocators::Make(vkContext, skgpu::ThreadSafe::kYes);
    if (!vkContext.fMemoryAllocator) {
        fprintf(stderr, "kine_skia: failed to create Skia Vulkan memory allocator\n");
        delete wrapper;
        return nullptr;
    }

    wrapper->context = GrDirectContexts::MakeVulkan(vkContext);
    if (!wrapper->context) {
        fprintf(stderr, "kine_skia: GrDirectContexts::MakeVulkan failed\n");
        delete wrapper;
        return nullptr;
    }

    return wrapper;
#else
    (void)backend;
    return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_Vulkan_DestroyContext(KineSkiaVulkanContext* context)
{
    if (!context) {
        return;
    }
#if KINE_SKIA_BUILD_VULKAN
    if (context->context) {
        context->context->flushAndSubmit();
        context->context->releaseResourcesAndAbandonContext();
        context->context.reset();
    }
#endif
    delete context;
}

/* ---------------- Surface lifecycle ---------------- */

KINE_SKIA_API KineSkiaSurface* Kine_Skia_Surface_Create(int width, int height)
{
    if (width <= 0 || height <= 0) {
        return nullptr;
    }

    SkImageInfo info = SkImageInfo::Make(
        width, height,
        kRGBA_8888_SkColorType,
        kPremul_SkAlphaType);

    sk_sp<SkSurface> surface = SkSurfaces::Raster(info);
    if (!surface) {
        return nullptr;
    }

    KineSkiaSurface* wrapper = new KineSkiaSurface();
    wrapper->surface = std::move(surface);
    wrapper->surface->getCanvas()->clear(SK_ColorTRANSPARENT);

    return wrapper;
}

KINE_SKIA_API KineSkiaSurface* Kine_Skia_Surface_CreateVulkanRenderTarget(
    KineSkiaVulkanContext* context,
    int width,
    int height,
    const KineSkiaVulkanImageInfo* imageInfo)
{
    if (width <= 0 || height <= 0 || !context || !imageInfo || !imageInfo->image) {
        return nullptr;
    }

#if KINE_SKIA_BUILD_VULKAN
    if (!context->context) {
        return nullptr;
    }

    GrVkImageInfo vkImageInfo;
    vkImageInfo.fImage = reinterpret_cast<VkImage>(imageInfo->image);
    vkImageInfo.fImageTiling = imageInfo->imageTiling
        ? static_cast<VkImageTiling>(imageInfo->imageTiling)
        : VK_IMAGE_TILING_OPTIMAL;
    vkImageInfo.fImageLayout = static_cast<VkImageLayout>(imageInfo->imageLayout);
    vkImageInfo.fFormat = static_cast<VkFormat>(imageInfo->format);
    vkImageInfo.fImageUsageFlags = static_cast<VkImageUsageFlags>(imageInfo->imageUsageFlags);
    vkImageInfo.fSampleCount = imageInfo->sampleCount ? imageInfo->sampleCount : 1;
    vkImageInfo.fLevelCount = imageInfo->levelCount ? imageInfo->levelCount : 1;
    vkImageInfo.fCurrentQueueFamily = imageInfo->currentQueueFamily;

    GrBackendRenderTarget renderTarget = GrBackendRenderTargets::MakeVk(width, height, vkImageInfo);
    if (!renderTarget.isValid()) {
        return nullptr;
    }

    SkColorType colorType = kRGBA_8888_SkColorType;
    if (vkImageInfo.fFormat == VK_FORMAT_B8G8R8A8_UNORM ||
        vkImageInfo.fFormat == VK_FORMAT_B8G8R8A8_SRGB) {
        colorType = kBGRA_8888_SkColorType;
    }

    sk_sp<SkSurface> surface = SkSurfaces::WrapBackendRenderTarget(
        context->context.get(),
        renderTarget,
        kTopLeft_GrSurfaceOrigin,
        colorType,
        nullptr,
        nullptr);

    if (!surface) {
        return nullptr;
    }

    KineSkiaSurface* wrapper = new KineSkiaSurface();
    wrapper->surface = std::move(surface);
    wrapper->vulkanContext = context->context;
    wrapper->vulkanRenderTarget = renderTarget;
    return wrapper;
#else
    (void)context;
    (void)imageInfo;
    return nullptr;
#endif
}

KINE_SKIA_API void Kine_Skia_Surface_Destroy(KineSkiaSurface* surface)
{
    delete surface;
}

KINE_SKIA_API int Kine_Skia_Surface_GetWidth(const KineSkiaSurface* surface)
{
    return surface && surface->surface ? surface->surface->width() : 0;
}

KINE_SKIA_API int Kine_Skia_Surface_GetHeight(const KineSkiaSurface* surface)
{
    return surface && surface->surface ? surface->surface->height() : 0;
}

KINE_SKIA_API size_t Kine_Skia_Surface_GetRowBytes(const KineSkiaSurface* surface)
{
    if (!surface || !surface->surface) {
        return 0;
    }

    SkPixmap pixmap;
    if (!surface->surface->peekPixels(&pixmap)) {
        return 0;
    }

    return pixmap.rowBytes();
}

KINE_SKIA_API void* Kine_Skia_Surface_GetPixels(KineSkiaSurface* surface)
{
    if (!surface || !surface->surface) {
        return nullptr;
    }

    SkPixmap pixmap;
    if (!surface->surface->peekPixels(&pixmap)) {
        return nullptr;
    }

    return pixmap.writable_addr();
}

KINE_SKIA_API void Kine_Skia_Surface_Flush(KineSkiaSurface* surface)
{
    if (!surface || !surface->surface) {
        return;
    }
#if KINE_SKIA_BUILD_VULKAN
    if (surface->vulkanContext) {
        skgpu::ganesh::FlushAndSubmit(surface->surface.get());
        surface->vulkanContext->flushAndSubmit();
    }
#endif
    /* Raster surfaces are synchronous. */
}

KINE_SKIA_API void Kine_Skia_Surface_SetBackdropFromSurface(
    KineSkiaSurface* surface,
    KineSkiaSurface* backdrop)
{
    if (!surface) {
        return;
    }

    surface->backdrop.reset();
    if (!backdrop || !backdrop->surface) {
        return;
    }

    Kine_Skia_Surface_Flush(backdrop);
    surface->backdrop = backdrop->surface->makeImageSnapshot();
}

KINE_SKIA_API void Kine_Skia_Surface_ClearBackdrop(KineSkiaSurface* surface)
{
    if (!surface) {
        return;
    }
    surface->backdrop.reset();
}

KINE_SKIA_API void Kine_Skia_Surface_GetPixel(
    KineSkiaSurface* surface,
    int x, int y,
    uint8_t* outR, uint8_t* outG, uint8_t* outB, uint8_t* outA)
{
    if (outR) *outR = 0;
    if (outG) *outG = 0;
    if (outB) *outB = 0;
    if (outA) *outA = 0;

    if (!surface || !surface->surface) {
        return;
    }

    SkPixmap pixmap;
    if (!surface->surface->peekPixels(&pixmap)) {
        return;
    }

    if (x < 0 || y < 0 || x >= pixmap.width() || y >= pixmap.height()) {
        return;
    }

    SkColor c = pixmap.getColor(x, y);
    if (outR) *outR = SkColorGetR(c);
    if (outG) *outG = SkColorGetG(c);
    if (outB) *outB = SkColorGetB(c);
    if (outA) *outA = SkColorGetA(c);
}

/* ---------------- Clear ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Clear(
    KineSkiaSurface* surface,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (!surface || !surface->surface) {
        return;
    }
    surface->surface->getCanvas()->clear(SkColorSetARGB(a, r, g, b));
}

/* ---------------- Shapes ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_DrawRect(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawRect(SkRect::MakeXYWH(x, y, width, height), paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawRoundRect(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radiusX, float radiusY,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawRRect(
        SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, width, height), radiusX, radiusY),
        paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawSquircle(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radius, float exponent,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawPath(
        kine_skia_squircle_path(x, y, width, height, radius, exponent),
        paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawUIShadow(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radius, float exponent,
    float offsetX, float offsetY,
    float blurSigma, float spread,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f || a == 0) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setStyle(SkPaint::kFill_Style);
    paint.setColor(SkColorSetARGB(a, r, g, b));
    if (blurSigma > 0.0f) {
        paint.setMaskFilter(SkMaskFilter::MakeBlur(kNormal_SkBlurStyle, blurSigma));
    }

    const float sx = x + offsetX - spread;
    const float sy = y + offsetY - spread;
    const float sw = width + spread * 2.0f;
    const float sh = height + spread * 2.0f;
    const float sr = std::max(0.0f, radius + spread);
    if (exponent > 2.0f && sr > 0.0f) {
        surface->surface->getCanvas()->drawPath(
            kine_skia_squircle_path(sx, sy, sw, sh, sr, exponent),
            paint);
    } else if (sr > 0.0f) {
        surface->surface->getCanvas()->drawRRect(
            SkRRect::MakeRectXY(SkRect::MakeXYWH(sx, sy, sw, sh), sr, sr),
            paint);
    } else {
        surface->surface->getCanvas()->drawRect(SkRect::MakeXYWH(sx, sy, sw, sh), paint);
    }
}

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurRect(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radiusX, float radiusY,
    float blurSigma,
    uint8_t alpha,
    uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA)
{
    if (!surface || !surface->surface || !surface->backdrop ||
        width <= 0.0f || height <= 0.0f || (alpha == 0 && tintA == 0)) {
        return;
    }

    SkCanvas* canvas = surface->surface->getCanvas();
    SkRect rect = SkRect::MakeXYWH(x, y, width, height);
    canvas->save();
    if (radiusX > 0.0f || radiusY > 0.0f) {
        canvas->clipRRect(SkRRect::MakeRectXY(rect, radiusX, radiusY), true);
    } else {
        canvas->clipRect(rect, SkClipOp::kIntersect, true);
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setAlphaf(alpha / 255.0f);
    if (blurSigma > 0.0f) {
        paint.setImageFilter(SkImageFilters::Blur(
            blurSigma, blurSigma, SkTileMode::kClamp, nullptr));
    }
    canvas->drawImageRect(
        surface->backdrop,
        rect,
        rect,
        SkSamplingOptions(SkFilterMode::kLinear),
        &paint,
        SkCanvas::kStrict_SrcRectConstraint);
    if (tintA > 0) {
        SkPaint tintPaint;
        tintPaint.setAntiAlias(true);
        tintPaint.setStyle(SkPaint::kFill_Style);
        tintPaint.setColor(SkColorSetARGB(tintA, tintR, tintG, tintB));
        canvas->drawRect(rect, tintPaint);
    }
    canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawBackdropBlurSquircle(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radius, float exponent,
    float blurSigma,
    uint8_t alpha,
    uint8_t tintR, uint8_t tintG, uint8_t tintB, uint8_t tintA)
{
    if (!surface || !surface->surface || !surface->backdrop ||
        width <= 0.0f || height <= 0.0f || (alpha == 0 && tintA == 0)) {
        return;
    }

    SkCanvas* canvas = surface->surface->getCanvas();
    SkRect rect = SkRect::MakeXYWH(x, y, width, height);
    canvas->save();
    canvas->clipPath(kine_skia_squircle_path(x, y, width, height, radius, exponent), true);

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setAlphaf(alpha / 255.0f);
    if (blurSigma > 0.0f) {
        paint.setImageFilter(SkImageFilters::Blur(
            blurSigma, blurSigma, SkTileMode::kClamp, nullptr));
    }
    canvas->drawImageRect(
        surface->backdrop,
        rect,
        rect,
        SkSamplingOptions(SkFilterMode::kLinear),
        &paint,
        SkCanvas::kStrict_SrcRectConstraint);
    if (tintA > 0) {
        SkPaint tintPaint;
        tintPaint.setAntiAlias(true);
        tintPaint.setStyle(SkPaint::kFill_Style);
        tintPaint.setColor(SkColorSetARGB(tintA, tintR, tintG, tintB));
        canvas->drawRect(rect, tintPaint);
    }
    canvas->restore();
}

KINE_SKIA_API void Kine_Skia_Surface_DrawCircle(
    KineSkiaSurface* surface,
    float cx, float cy, float radius,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || radius <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawCircle(cx, cy, radius, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawOval(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawOval(SkRect::MakeXYWH(x, y, width, height), paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawArc(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float startAngle, float sweepAngle, int useCenter,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawArc(
        SkRect::MakeXYWH(x, y, width, height),
        startAngle, sweepAngle, useCenter != 0, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawLine(
    KineSkiaSurface* surface,
    float x0, float y0, float x1, float y1,
    float strokeWidth,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (!surface || !surface->surface || strokeWidth <= 0.0f) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(SkColorSetARGB(a, r, g, b));
    paint.setStyle(SkPaint::kStroke_Style);
    paint.setStrokeWidth(strokeWidth);

    surface->surface->getCanvas()->drawLine(x0, y0, x1, y1, paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawPolygon(
    KineSkiaSurface* surface,
    const float* points, int pointCount,
    int closed,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    float strokeWidth)
{
    if (!surface || !surface->surface || !points || pointCount < 2) {
        return;
    }

    SkPathBuilder builder;
    builder.moveTo(points[0], points[1]);
    for (int i = 1; i < pointCount; ++i) {
        builder.lineTo(points[i * 2], points[i * 2 + 1]);
    }
    if (closed) {
        builder.close();
    }
    SkPath path = builder.detach();

    SkPaint paint = kine_skia_paint(r, g, b, a, strokeWidth);
    surface->surface->getCanvas()->drawPath(path, paint);
}

/* ---------------- Transform stack ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_Save(KineSkiaSurface* surface)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->save();
}

KINE_SKIA_API void Kine_Skia_Surface_Restore(KineSkiaSurface* surface)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->restore();
}


KINE_SKIA_API void Kine_Skia_Surface_Translate(KineSkiaSurface* surface, float dx, float dy)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->translate(dx, dy);
}

KINE_SKIA_API void Kine_Skia_Surface_Rotate(KineSkiaSurface* surface, float degrees)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->rotate(degrees);
}

KINE_SKIA_API void Kine_Skia_Surface_Scale(KineSkiaSurface* surface, float sx, float sy)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->scale(sx, sy);
}

KINE_SKIA_API void Kine_Skia_Surface_ClipRect(
    KineSkiaSurface* surface,
    float x, float y, float width, float height)
{
    if (!surface || !surface->surface) return;
    surface->surface->getCanvas()->clipRect(SkRect::MakeXYWH(x, y, width, height));
}

KINE_SKIA_API void Kine_Skia_Surface_ClipRoundRect(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radiusX, float radiusY)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) return;

    SkRRect rrect = SkRRect::MakeRectXY(
        SkRect::MakeXYWH(x, y, width, height), radiusX, radiusY);

    surface->surface->getCanvas()->clipRRect(rrect, /*doAntiAlias=*/true);
}

KINE_SKIA_API void Kine_Skia_Surface_ClipSquircle(
    KineSkiaSurface* surface,
    float x, float y, float width, float height,
    float radius, float exponent)
{
    if (!surface || !surface->surface || width <= 0.0f || height <= 0.0f) return;

    surface->surface->getCanvas()->clipPath(
        kine_skia_squircle_path(x, y, width, height, radius, exponent),
        /*doAntiAlias=*/true);
}

/* ---------------- Text ---------------- */

KINE_SKIA_API void Kine_Skia_Surface_DrawText(
    KineSkiaSurface* surface,
    const char* text,
    float x, float y,
    float fontSize,
    const char* fontPath,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    if (!surface || !surface->surface || !text || !text[0]) {
        return;
    }

    sk_sp<SkTypeface> typeface = kine_skia_get_typeface(fontPath);
    if (!typeface) {
        return;
    }

    SkFont font(typeface, fontSize);
    font.setEdging(SkFont::Edging::kAntiAlias);

    sk_sp<SkTextBlob> blob = SkTextBlob::MakeFromText(
        text, strlen(text), font, SkTextEncoding::kUTF8);
    if (!blob) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor(SkColorSetARGB(a, r, g, b));

    surface->surface->getCanvas()->drawTextBlob(blob, x, y, paint);
}

KINE_SKIA_API float Kine_Skia_Surface_MeasureText(
    const char* text,
    float fontSize,
    const char* fontPath)
{
    if (!text || fontSize <= 0.0f) {
        return 0.0f;
    }

    sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
    SkFont font(tf, fontSize);
    return font.measureText(text, strlen(text), SkTextEncoding::kUTF8);
}

KINE_SKIA_API float Kine_Skia_Surface_GetFontLineHeight(
    float fontSize,
    const char* fontPath)
{
    if (fontSize <= 0.0f) {
        return 0.0f;
    }

    sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
    SkFont font(tf, fontSize);

    SkFontMetrics metrics;
    font.getMetrics(&metrics);

    return (-metrics.fAscent) + metrics.fDescent + metrics.fLeading;
}

/* ---------------- Images ---------------- */

KINE_SKIA_API KineSkiaImage* Kine_Skia_Image_LoadFromFile(const char* path)
{
    if (!path || path[0] == '\0') {
        return nullptr;
    }

    sk_sp<SkData> data = SkData::MakeFromFileName(path);
    if (!data) {
        fprintf(stderr, "kine_skia: failed to read image file '%s'\n", path);
        return nullptr;
    }

    sk_sp<SkImage> image = SkImages::DeferredFromEncodedData(data);
    if (!image) {
        fprintf(stderr, "kine_skia: failed to decode image '%s'\n", path);
        return nullptr;
    }

    KineSkiaImage* wrapper = new KineSkiaImage();
    wrapper->image = std::move(image);
    return wrapper;
}

KINE_SKIA_API KineSkiaImage* Kine_Skia_Image_LoadFromMemory(const uint8_t* data, size_t size)
{
    if (!data || size == 0) {
        return nullptr;
    }

    sk_sp<SkData> skData = SkData::MakeWithCopy(data, size);
    sk_sp<SkImage> image = SkImages::DeferredFromEncodedData(skData);
    if (!image) {
        fprintf(stderr, "kine_skia: failed to decode image from memory buffer\n");
        return nullptr;
    }

    KineSkiaImage* wrapper = new KineSkiaImage();
    wrapper->image = std::move(image);
    return wrapper;
}

KINE_SKIA_API void Kine_Skia_Image_Destroy(KineSkiaImage* image)
{
    delete image;
}

KINE_SKIA_API int Kine_Skia_Image_GetWidth(const KineSkiaImage* image)
{
    return image && image->image ? image->image->width() : 0;
}

KINE_SKIA_API int Kine_Skia_Image_GetHeight(const KineSkiaImage* image)
{
    return image && image->image ? image->image->height() : 0;
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImage(
    KineSkiaSurface* surface,
    KineSkiaImage* image,
    float x, float y,
    uint8_t alpha)
{
    if (!surface || !surface->surface || !image || !image->image) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    if (alpha < 255) {
        paint.setAlphaf(alpha / 255.0f);
    }

    surface->surface->getCanvas()->drawImage(image->image, x, y, SkSamplingOptions(), &paint);
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageSized(
    KineSkiaSurface* surface,
    KineSkiaImage* image,
    float x, float y,
    float width, float height,
    uint8_t alpha)
{
    if (!surface || !surface->surface || !image || !image->image) {
        return;
    }

    if (width <= 0.0f || height <= 0.0f) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);

    if (alpha < 255) {
        paint.setAlphaf(alpha / 255.0f);
    }

    SkRect dst = SkRect::MakeXYWH(x, y, width, height);

    surface->surface->getCanvas()->drawImageRect(
        image->image,
        dst,
        SkSamplingOptions(SkFilterMode::kLinear),
        &paint
    );
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageOutlineSized(
    KineSkiaSurface* surface,
    KineSkiaImage* image,
    float x, float y,
    float width, float height,
    float thickness,
    uint8_t r, uint8_t g, uint8_t b, uint8_t a,
    uint8_t alpha)
{
    if (!surface || !surface->surface || !image || !image->image ||
        width <= 0.0f || height <= 0.0f || thickness <= 0.0f || a == 0) {
        return;
    }

    SkRect dst = SkRect::MakeXYWH(x, y, width, height);
    SkRect layerBounds = dst;
    layerBounds.outset(thickness, thickness);
    SkCanvas* canvas = surface->surface->getCanvas();

    SkPaint outlinePaint;
    outlinePaint.setAntiAlias(true);
    outlinePaint.setImageFilter(SkImageFilters::Dilate(thickness, thickness, nullptr));

    canvas->saveLayer(&layerBounds, nullptr);
    canvas->drawImageRect(
        image->image,
        dst,
        SkSamplingOptions(SkFilterMode::kLinear),
        &outlinePaint);

    SkPaint tintPaint;
    tintPaint.setAntiAlias(true);
    tintPaint.setStyle(SkPaint::kFill_Style);
    tintPaint.setColor(SkColorSetARGB(a, r, g, b));
    tintPaint.setBlendMode(SkBlendMode::kSrcIn);
    canvas->drawRect(layerBounds, tintPaint);
    canvas->restore();

    SkPaint imagePaint;
    imagePaint.setAntiAlias(true);
    if (alpha < 255) {
        imagePaint.setAlphaf(alpha / 255.0f);
    }
    canvas->drawImageRect(
        image->image,
        dst,
        SkSamplingOptions(SkFilterMode::kLinear),
        &imagePaint);
}

KINE_SKIA_API float Kine_Skia_Surface_GetFontAscent(
    float fontSize,
    const char* fontPath)
{
    if (fontSize <= 0.0f) {
        return 0.0f;
    }

    sk_sp<SkTypeface> tf = kine_skia_get_typeface(fontPath);
    SkFont font(tf, fontSize);

    SkFontMetrics metrics;
    font.getMetrics(&metrics);

    return -metrics.fAscent;
}

KINE_SKIA_API void Kine_Skia_Surface_DrawImageRect(
    KineSkiaSurface* surface,
    KineSkiaImage* image,
    float srcX, float srcY, float srcWidth, float srcHeight,
    float dstX, float dstY, float dstWidth, float dstHeight,
    uint8_t alpha)
{
    if (!surface || !surface->surface || !image || !image->image) {
        return;
    }
    if (srcWidth <= 0.0f || srcHeight <= 0.0f || dstWidth <= 0.0f || dstHeight <= 0.0f) {
        return;
    }

    SkPaint paint;
    paint.setAntiAlias(true);
    if (alpha < 255) {
        paint.setAlphaf(alpha / 255.0f);
    }

    SkRect src = SkRect::MakeXYWH(srcX, srcY, srcWidth, srcHeight);
    SkRect dst = SkRect::MakeXYWH(dstX, dstY, dstWidth, dstHeight);

    surface->surface->getCanvas()->drawImageRect(
        image->image, src, dst,
        SkSamplingOptions(SkFilterMode::kLinear),
        &paint,
        SkCanvas::kStrict_SrcRectConstraint);
}

}
