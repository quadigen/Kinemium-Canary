#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#endif
#include "kine_filament_shim.h"

#include "kine_default_package.h"

#ifndef KINE_WITH_ASSIMP
#define KINE_WITH_ASSIMP 0
#endif
#ifndef KINE_FILAMENT_USE_VULKAN
#define KINE_FILAMENT_USE_VULKAN 0
#endif
#ifndef KINE_FILAMENT_ENABLE_VULKAN_READBACK
#define KINE_FILAMENT_ENABLE_VULKAN_READBACK 0
#endif

#include <filament/Engine.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/SwapChain.h>
#include <filament/Texture.h>
#include <filament/RenderTarget.h>
#include <filament/Viewport.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/RenderableManager.h>
#include <filament/TransformManager.h>
#include <filament/LightManager.h>
#include <filament/VertexBuffer.h>
#include <filament/IndexBuffer.h>
#include <filament/InstanceBuffer.h>
#include <filament/TextureSampler.h>
#include <filament/Color.h>
#include <filament/Skybox.h>
#include <filament/IndirectLight.h>
#include <backend/DriverEnums.h>
#include <backend/Platform.h>
#if KINE_FILAMENT_USE_VULKAN
#include <backend/platforms/VulkanPlatform.h>
#include "kine_vulkan_compositor.h"
#endif
#include <SDL3/SDL_properties.h>
#include <SDL3/SDL_video.h>
#include <SDL3/SDL_vulkan.h>
#include <utils/EntityManager.h>
#include <utils/Entity.h>
#include <math/vec2.h>
#include <math/vec3.h>
#include <math/vec4.h>
#include <math/mat4.h>
#include "kine_neon_package.h"
#include "kine_glass_package.h"
#include "kine_water_package.h"
#include "kine_decal_package.h"
#include "kine_outline_package.h"

#include <geometry/SurfaceOrientation.h>
using namespace filament::geometry;

#if KINE_FILAMENT_USE_VULKAN
struct VkInstance_T;
struct VkPhysicalDevice_T;
struct VkDevice_T;
struct VkQueue_T;
#endif

#if KINE_WITH_ASSIMP
#include <assimp/Importer.hpp>
#include <assimp/postprocess.h>
#include <assimp/scene.h>
#endif

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <limits>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#if !KINE_FILAMENT_USE_VULKAN
#if defined(_WIN32)
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <GL/gl.h>
    static void* kine_get_current_gl_context() { return (void*)wglGetCurrentContext(); }
#elif defined(__APPLE__)
    // Apple's OpenGL headers are deprecated as of 10.14+ but still ship and work;
    // silence the barrage of warnings rather than fight the toolchain.
    #define GL_SILENCE_DEPRECATION
    #include <OpenGL/OpenGL.h>
    #include <OpenGL/gl.h>
    static void* kine_get_current_gl_context() { return (void*)CGLGetCurrentContext(); }
#else
    #include <GL/glx.h>
    #include <GL/gl.h>
    static void* kine_get_current_gl_context() { return (void*)glXGetCurrentContext(); }
#endif

// MSVC's bundled GL/gl.h only declares GL 1.1. These are core since GL 1.2/1.3
// but the constant values are part of the stable GL spec, safe to hardcode.
#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE 0x812F
#endif
#ifndef GL_TEXTURE0
#define GL_TEXTURE0 0x84C0
#endif

// GL_RGBA / GL_UNSIGNED_BYTE are in GL 1.1 on all platforms.
// glReadPixels is also GL 1.0, but on Windows MSVC's gl.h only has the
// prototype if _WIN32 is defined and we include it correctly -- which we do
// above.  No extra declaration needed.
// glBindFramebuffer / GL_FRAMEBUFFER are OpenGL 3.0 core.
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER 0x8D40
#endif
#ifndef GL_COLOR_ATTACHMENT0
#define GL_COLOR_ATTACHMENT0 0x8CE0
#endif

// APIENTRY is only ever defined for us by <windows.h>. On Linux/macOS the GL
// calling convention is just the platform default, so make it a no-op there
// instead of hardcoding a Windows-only calling convention into these typedefs.
#ifndef APIENTRY
#define APIENTRY
#endif

typedef void    (APIENTRY* PFNGLBINDFRAMEBUFFERPROC)(GLenum, GLuint);
typedef void    (APIENTRY* PFNGLGETFRAMEBUFFERATTACHMENTPARAMETERIVPROC)(GLenum, GLenum, GLenum, GLint*);
typedef void    (APIENTRY* PFNGLGENFRAMEBUFFERSPROC)(GLsizei, GLuint*);
typedef void    (APIENTRY* PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei, const GLuint*);
typedef void    (APIENTRY* PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum, GLenum, GLenum, GLuint, GLint);

#define GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME 0x8CD1

static PFNGLBINDFRAMEBUFFERPROC          kine_glBindFramebuffer    = nullptr;
static PFNGLGENFRAMEBUFFERSPROC          kine_glGenFramebuffers    = nullptr;
static PFNGLDELETEFRAMEBUFFERSPROC       kine_glDeleteFramebuffers = nullptr;
static PFNGLFRAMEBUFFERTEXTURE2DPROC     kine_glFramebufferTexture2D = nullptr;

typedef void (APIENTRY* PFNGLBLITFRAMEBUFFERPROC)(GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLint,GLbitfield,GLenum);
static PFNGLBLITFRAMEBUFFERPROC kine_glBlitFramebuffer = nullptr;

#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CA8
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif
#ifndef GL_COLOR_BUFFER_BIT
#define GL_COLOR_BUFFER_BIT 0x4000
#endif

static void kine_init_gl_ext() {
    static bool done = false;
    if (done) return;
    done = true;
#if defined(_WIN32)
    kine_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)wglGetProcAddress("glBlitFramebuffer");
    kine_glBindFramebuffer     = (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress("glBindFramebuffer");
    kine_glGenFramebuffers     = (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress("glGenFramebuffers");
    kine_glDeleteFramebuffers  = (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress("glDeleteFramebuffers");
    kine_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress("glFramebufferTexture2D");
#elif defined(__APPLE__)
    kine_glBlitFramebuffer = &glBlitFramebuffer;
    // Apple's OpenGL framework has always linked these directly (core since
    // GL 3.0, and macOS's GL implementation tops out at 4.1 core) -- no
    // runtime lookup needed or even possible via a "wgl/glX"-style API.
    kine_glBindFramebuffer      = &glBindFramebuffer;
    kine_glGenFramebuffers      = &glGenFramebuffers;
    kine_glDeleteFramebuffers   = &glDeleteFramebuffers;
    kine_glFramebufferTexture2D = &glFramebufferTexture2D;
#else
    kine_glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)glXGetProcAddress((const GLubyte*)"glBlitFramebuffer");
    kine_glBindFramebuffer      = (PFNGLBINDFRAMEBUFFERPROC)glXGetProcAddress((const GLubyte*)"glBindFramebuffer");
    kine_glGenFramebuffers      = (PFNGLGENFRAMEBUFFERSPROC)glXGetProcAddress((const GLubyte*)"glGenFramebuffers");
    kine_glDeleteFramebuffers   = (PFNGLDELETEFRAMEBUFFERSPROC)glXGetProcAddress((const GLubyte*)"glDeleteFramebuffers");
    kine_glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)glXGetProcAddress((const GLubyte*)"glFramebufferTexture2D");
#endif
}
#endif

using namespace filament;
using namespace utils;

// ---------------------------------------------------------------------------
// Minimal embedded lit material (unlit flat color + optional texture).
// Built with: matc -a opengl -p mobile -o default_lit.filamat default_lit.mat
// We embed it as a raw byte array generated from the uberarchive shaders.
// For now we use a very simple unlit material that takes baseColor + texture.
// ---------------------------------------------------------------------------

// Material data provided by kine_default_package.h
// ---------------------------------------------------------------------------
// Vertex layout for procedural meshes: position (float3) + normal (float3) + uv (float2)
// ---------------------------------------------------------------------------
struct KineVertex {
    float px, py, pz;
    float nx, ny, nz;
    float u,  v;
};

struct vector3 { float x, y, z; };

struct KineMesh {
    VertexBuffer* vb       = nullptr;
    IndexBuffer*  ib       = nullptr;
    uint32_t      indexCount = 0;
    std::vector<KineVertex>  vertices;
    std::vector<uint16_t>    indices;
    Box localBounds;
};

struct KineTexHandle {
    Texture* tex       = nullptr;
    Texture* normalTex = nullptr;
    Texture* ormTex    = nullptr;
};

// ---------------------------------------------------------------------------
// Automatic instanced batching.
//
// Kine_Filament_DrawMeshEx no longer builds a Filament Entity per call. It
// just records the world transform under a key describing "everything about
// this draw that isn't the transform" (mesh + material kind + color/params +
// shadow/culling flags). Calls that share a key are, by definition, the same
// mesh drawn with the same material settings, so they can legally share one
// MaterialInstance and be issued as a single GPU-instanced draw call.
//
// kine_update_batches() turns each accumulated batch into one or more
// RenderableManager entities using InstanceBuffers. Stable batches retain
// their entities, materials, and buffers across frames; animation only
// uploads transforms and updates bounds. Batches bigger than
// Engine::getMaxAutomaticInstances() are split into multiple draw calls.
// ---------------------------------------------------------------------------

struct KineBatchKey {
    KineMesh* mesh          = nullptr;
    uint64_t  streamId      = 0;
    int       materialKind  = 0;
    float     r = 0, g = 0, b = 0;
    float     param1 = 0, param2 = 0, param3 = 0;
    float     transmission  = 0;
    bool      castShadow    = false;
    bool      receiveShadow = false;
    bool      culling       = true;

    KineTexHandle* texture;

    bool operator==(const KineBatchKey& o) const noexcept
    {
        return mesh == o.mesh && streamId == o.streamId && materialKind == o.materialKind &&
               r == o.r && g == o.g && b == o.b &&
               param1 == o.param1 && param2 == o.param2 && param3 == o.param3 &&
               transmission == o.transmission &&
               castShadow == o.castShadow && receiveShadow == o.receiveShadow &&
               culling == o.culling && texture == o.texture;
    }
};

struct KineBatchKeyHash {
    size_t operator()(const KineBatchKey& k) const noexcept
    {
        size_t h = std::hash<void*>()(k.mesh);
        auto mix = [&h](size_t v) { h ^= v + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2); };
        mix(std::hash<uint64_t>()(k.streamId));
        mix(std::hash<int>()(k.materialKind));
        mix(std::hash<float>()(k.r));
        mix(std::hash<float>()(k.g));
        mix(std::hash<float>()(k.b));
        mix(std::hash<float>()(k.param1));
        mix(std::hash<float>()(k.param2));
        mix(std::hash<float>()(k.param3));
        mix(std::hash<float>()(k.transmission));
        mix(std::hash<bool>()(k.castShadow));
        mix(std::hash<bool>()(k.receiveShadow));
        mix(std::hash<bool>()(k.culling));
        mix(std::hash<void*>()(k.texture));
        return h;
    }
};

struct KinePendingBatch {
    std::vector<math::mat4f> transforms;
    uint64_t lastQueuedFrame = 0;
};

struct KineBuiltBatch {
    Entity            entity;
    InstanceBuffer*   instanceBuffer = nullptr;
    size_t             instanceCount = 0;
};

struct KinePersistentBatch {
    MaterialInstance* matInst = nullptr;
    std::vector<KineBuiltBatch> chunks;
    uint64_t lastUsedFrame = 0;
};

struct KineRetainedListState {
    uint64_t version = 0;
    bool initialized = false;
    std::vector<KineBatchKey> keys;
};

struct KineDecalResource {
    Entity entity;
    MaterialInstance* material = nullptr;
    KineMesh* mesh = nullptr;
};

struct KineFilamentContext {
    Engine*          engine       = nullptr;
    SwapChain*       swapChain    = nullptr;
    Renderer*        renderer     = nullptr;
    Scene*           scene        = nullptr;
    View*            view         = nullptr;
    Camera*          camera       = nullptr;
    Entity           cameraEntity;
    math::double3    cameraEye{0,0,0};
    math::double3    cameraTarget{0,0,-1};
    math::double3    cameraUp{0,1,0};
    Texture*         colorTarget      = nullptr;
    Texture*         depthTarget      = nullptr;
    RenderTarget*    renderTarget     = nullptr;
    unsigned int     colorTextureId   = 0;
    unsigned int     readFboId        = 0;
    void*            nativeWindow     = nullptr;
    bool             renderToSwapChain = false;
    bool             useFilamentOwnedCompositor = false;
    bool             loggedFirstFrame = false;
    int              viewportX = 0;
    int              viewportY = 0;
    int              viewportWidth = 0;
    int              viewportHeight = 0;
    int              width  = 0;
    int              height = 0;
    Texture* whiteTex = nullptr;

    Material*        defaultMaterial = nullptr;
    Entity           sunLight;

    Material* neonMaterial  = nullptr;
    Material* glassMaterial = nullptr;
    Material* waterMaterial = nullptr;
    Material* decalMaterial = nullptr;
    Material* outlineMaterial = nullptr;
    float     time = 0.0f;   // accumulate once per frame for animation

    // Host GL context, captured at Create() time so we can hand control
    // back after we've made Filament's own shared context current.
    //   Windows : hostCtx = HGLRC,          hostDC = HDC
    //   macOS   : hostCtx = CGLContextObj   (no separate "DC" concept)
    //   Linux   : hostCtx = GLXContext,     hostDisplay = Display*,
    //             hostDrawable = GLXDrawable
    void*         hostCtx      = nullptr;
    void*         hostDC       = nullptr;
    void*         hostDisplay  = nullptr;
    unsigned long hostDrawable = 0;

#if KINE_FILAMENT_USE_VULKAN
    std::unique_ptr<backend::Platform> vulkanPlatform;
    backend::VulkanPlatform::VulkanSharedContext vulkanSharedContext;
    void* vulkanCompositor = nullptr;
#endif

    Skybox*        skybox        = nullptr;
    Texture*       skyTexture    = nullptr;
    IndirectLight* indirectLight = nullptr;
    void* filamentCtx = nullptr;
    math::float4 skyColor = {0.53f, 0.81f, 0.92f, 1.0f};

    // Batch keys and transform storage survive across frames. Stable scenes
    // therefore update InstanceBuffers instead of rebuilding GPU resources.
    std::unordered_map<KineBatchKey, KinePendingBatch, KineBatchKeyHash> pendingBatches;
    std::unordered_map<KineBatchKey, KinePersistentBatch, KineBatchKeyHash> builtBatches;
    std::unordered_map<uint64_t, KineRetainedListState> retainedLists;
    uint64_t batchFrame = 1;
    std::vector<KineDecalResource> decals;
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK
    std::vector<unsigned char> readbackPixels;
#endif
};

#if KINE_FILAMENT_USE_VULKAN
struct KineFilamentCompositorSwapChain : backend::Platform::SwapChain {};

using KineFilamentVulkanPlatformBase = backend::VulkanPlatform;

class KineFilamentCompositorVulkanPlatform final : public KineFilamentVulkanPlatformBase {
public:
    KineFilamentCompositorVulkanPlatform(void* sdlWindow, int width, int height)
        : mSdlWindow(sdlWindow),
          mWidth(width),
          mHeight(height) {}

    ~KineFilamentCompositorVulkanPlatform() override
    {
        this->destroyCompositor();
    }

    KineVulkanCompositor* compositor() const noexcept
    {
        return mCompositor;
    }

    void setExtent(int width, int height) noexcept
    {
        mWidth = width;
        mHeight = height;
    }

    void destroyCompositor() noexcept
    {
        if (mCompositor) {
            Kine_VulkanCompositor_Destroy(mCompositor);
            mCompositor = nullptr;
        }
    }

    Customization getCustomization() const noexcept override
    {
        Customization customization{};
        customization.transitionSwapChainImageLayoutForPresent = false;
        return customization;
    }

    SwapChainBundle getSwapChainBundle(SwapChainPtr handle) override
    {
        (void)handle;
        SwapChainBundle bundle{};
        if (!mCompositor) {
            return bundle;
        }

        KineVulkanCompositorInfo info{};
        if (!Kine_VulkanCompositor_GetInfo(mCompositor, &info)) {
            return bundle;
        }

        uint32_t count = Kine_VulkanCompositor_GetSwapchainImages(mCompositor, nullptr, 0);
        std::vector<void*> images(count);
        if (count > 0) {
            Kine_VulkanCompositor_GetSwapchainImages(mCompositor, images.data(), count);
        }

        bundle.colors = utils::FixedCapacityVector<VkImage>::with_capacity(count);
        for (uint32_t i = 0; i < count; ++i) {
            bundle.colors.push_back(reinterpret_cast<VkImage>(images[i]));
        }

        void* depthImage = nullptr;
        uint32_t depthFormat = 0;
        if (Kine_VulkanCompositor_GetDepthAttachment(mCompositor, &depthImage, &depthFormat)) {
            bundle.depth = reinterpret_cast<VkImage>(depthImage);
            bundle.depthFormat = static_cast<VkFormat>(depthFormat);
        }
        bundle.colorFormat = static_cast<VkFormat>(info.swapchainFormat);
        bundle.extent = { info.width, info.height };
        bundle.layerCount = 1;
        bundle.isProtected = false;
        if (!mLoggedBundle) {
            fprintf(stderr,
                "[Kine] Filament compositor bundle: colors=%u colorFormat=%u depth=%p depthFormat=%u extent=%ux%u\n",
                count,
                static_cast<uint32_t>(bundle.colorFormat),
                static_cast<void*>(bundle.depth),
                static_cast<uint32_t>(bundle.depthFormat),
                bundle.extent.width,
                bundle.extent.height);
            mLoggedBundle = true;
        }
        return bundle;
    }

    VkResult acquire(SwapChainPtr handle, ImageSyncData* outImageSyncData) override
    {
        (void)handle;
        if (!outImageSyncData || !mCompositor) {
            return VK_ERROR_INITIALIZATION_FAILED;
        }

        void* imageReadySemaphore = nullptr;
        uint32_t imageIndex = ImageSyncData::INVALID_IMAGE_INDEX;
        VkResult result = static_cast<VkResult>(Kine_VulkanCompositor_FilamentAcquire(
            mCompositor,
            &imageIndex,
            &imageReadySemaphore));
        if (result == VK_SUCCESS) {
            outImageSyncData->imageIndex = imageIndex;
            outImageSyncData->imageReadySemaphore = reinterpret_cast<VkSemaphore>(imageReadySemaphore);
            if (!mLoggedAcquire) {
                fprintf(stderr,
                    "[Kine] Filament compositor acquire: image=%u readySemaphore=%p\n",
                    imageIndex,
                    imageReadySemaphore);
                mLoggedAcquire = true;
            }
        }
        return result;
    }

    VkResult present(SwapChainPtr handle, uint32_t index, VkSemaphore finishedDrawing) override
    {
        (void)handle;
        if (!mCompositor) {
            return VK_ERROR_INITIALIZATION_FAILED;
        }
        if (!mLoggedPresent) {
            fprintf(stderr,
                "[Kine] Filament compositor present hook: image=%u finishedSemaphore=%p\n",
                index,
                static_cast<void*>(finishedDrawing));
            mLoggedPresent = true;
        }
        return static_cast<VkResult>(Kine_VulkanCompositor_FilamentPresent(
            mCompositor,
            index,
            reinterpret_cast<void*>(finishedDrawing)));
    }

    bool hasResized(SwapChainPtr handle) override
    {
        (void)handle;
        return false;
    }

    bool isProtected(SwapChainPtr handle) override
    {
        (void)handle;
        return false;
    }

    VkResult recreate(SwapChainPtr handle) override
    {
        (void)handle;
        return VK_SUCCESS;
    }

    SwapChainPtr createSwapChain(void* nativeWindow, uint64_t flags = 0,
            VkExtent2D extent = {0, 0}) override
    {
        (void)nativeWindow;
        (void)flags;
        if (extent.width > 0 && extent.height > 0) {
            mWidth = static_cast<int>(extent.width);
            mHeight = static_cast<int>(extent.height);
        }
        if (!mCompositor && mSdlWindow && mWidth > 0 && mHeight > 0) {
            auto getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
                SDL_Vulkan_GetVkGetInstanceProcAddr());
            PFN_vkGetDeviceProcAddr getDeviceProcAddr = nullptr;
            if (getInstanceProcAddr && this->getInstance()) {
                getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
                    getInstanceProcAddr(this->getInstance(), "vkGetDeviceProcAddr"));
            }

            KineVulkanCompositorBackend backend{};
            backend.instance = this->getInstance();
            backend.physicalDevice = this->getPhysicalDevice();
            backend.device = this->getDevice();
            backend.queue = this->getGraphicsQueue();
            backend.graphicsQueueFamilyIndex = this->getGraphicsQueueFamilyIndex();
            backend.maxApiVersion = VK_API_VERSION_1_1;
            backend.getInstanceProcAddr = reinterpret_cast<void*>(getInstanceProcAddr);
            backend.getDeviceProcAddr = reinterpret_cast<void*>(getDeviceProcAddr);

            fprintf(stderr,
                "[Kine] creating compositor from Filament Vulkan device queueFamily=%u queueIndex=%u size=%dx%d\n",
                this->getGraphicsQueueFamilyIndex(),
                this->getGraphicsQueueIndex(),
                mWidth,
                mHeight);
            mCompositor = Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
                mSdlWindow,
                mWidth,
                mHeight,
                &backend);
            if (!Kine_VulkanCompositor_IsReady(mCompositor)) {
                const char* error = Kine_VulkanCompositor_GetLastError(mCompositor);
                fprintf(stderr,
                    "[Kine] compositor-from-Filament creation failed: %s\n",
                    error && error[0] ? error : "unknown error");
                Kine_VulkanCompositor_Destroy(mCompositor);
                mCompositor = nullptr;
                return nullptr;
            }
        } else if (mCompositor &&
                   !Kine_VulkanCompositor_Resize(mCompositor, mWidth, mHeight)) {
            const char* error = Kine_VulkanCompositor_GetLastError(mCompositor);
            fprintf(stderr,
                "[Kine] compositor resize failed: %s\n",
                error && error[0] ? error : "unknown error");
            return nullptr;
        }
        return new KineFilamentCompositorSwapChain();
    }

    void destroy(SwapChainPtr handle) override
    {
        delete static_cast<KineFilamentCompositorSwapChain*>(handle);
    }

protected:
    ExtensionSet getSwapchainInstanceExtensions() const override
    {
        ExtensionSet extensions;
        uint32_t count = 0;
        char const* const* required = SDL_Vulkan_GetInstanceExtensions(&count);
        if (required) {
            for (uint32_t i = 0; i < count; ++i) {
                if (required[i]) {
                    extensions.emplace(utils::CString(required[i]));
                }
            }
        }
#if defined(__APPLE__)
        extensions.emplace(utils::CString("VK_KHR_portability_enumeration"));
#endif
        return extensions;
    }

    SurfaceBundle createVkSurfaceKHR(void* nativeWindow, VkInstance instance,
            uint64_t flags) const noexcept override
    {
        (void)nativeWindow;
        (void)instance;
        (void)flags;
        return { VK_NULL_HANDLE, {0, 0} };
    }

    VkInstance createVkInstance(VkInstanceCreateInfo const& createInfo) noexcept override
    {
        std::vector<const char*> extensions;
        if (createInfo.enabledExtensionCount > 0 && createInfo.ppEnabledExtensionNames) {
            extensions.assign(
                createInfo.ppEnabledExtensionNames,
                createInfo.ppEnabledExtensionNames + createInfo.enabledExtensionCount);
        }
#if defined(__APPLE__)
        if (std::none_of(extensions.begin(), extensions.end(), [](const char* extension) {
                return extension && std::strcmp(extension, "VK_KHR_portability_enumeration") == 0;
            })) {
            extensions.push_back("VK_KHR_portability_enumeration");
        }
#endif

        VkInstanceCreateInfo compositorCreateInfo = createInfo;
        compositorCreateInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
        compositorCreateInfo.ppEnabledExtensionNames = extensions.data();
#if defined(__APPLE__) && defined(VK_KHR_portability_enumeration)
        compositorCreateInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
#endif
        fprintf(stderr,
            "[Kine] Filament Vulkan creating instance with %u extensions\n",
            compositorCreateInfo.enabledExtensionCount);
        VkInstance instance = KineFilamentVulkanPlatformBase::createVkInstance(compositorCreateInfo);
        fprintf(stderr, "[Kine] Filament Vulkan instance created: %p\n",
            static_cast<void*>(instance));
        return instance;
    }

    VkDevice createVkDevice(VkDeviceCreateInfo const& createInfo) noexcept override
    {
        std::vector<const char*> extensions;
        if (createInfo.enabledExtensionCount > 0 && createInfo.ppEnabledExtensionNames) {
            extensions.assign(
                createInfo.ppEnabledExtensionNames,
                createInfo.ppEnabledExtensionNames + createInfo.enabledExtensionCount);
        }
        const bool hasSwapchain = std::any_of(
            extensions.begin(),
            extensions.end(),
            [](const char* extension) {
                return extension &&
                    strcmp(extension, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0;
            });
        if (!hasSwapchain) {
            extensions.push_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
        }
#if defined(__APPLE__)
        const bool hasPortabilitySubset = std::any_of(
            extensions.begin(),
            extensions.end(),
            [](const char* extension) {
                return extension && std::strcmp(extension, "VK_KHR_portability_subset") == 0;
            });
        if (!hasPortabilitySubset) {
            extensions.push_back("VK_KHR_portability_subset");
        }
#endif

        VkDeviceCreateInfo compositorCreateInfo = createInfo;
        compositorCreateInfo.enabledExtensionCount =
            static_cast<uint32_t>(extensions.size());
        compositorCreateInfo.ppEnabledExtensionNames = extensions.data();

        fprintf(stderr,
            "[Kine] Filament Vulkan creating device with %u extensions and %u queue groups\n",
            compositorCreateInfo.enabledExtensionCount,
            compositorCreateInfo.queueCreateInfoCount);
        VkDevice device = KineFilamentVulkanPlatformBase::createVkDevice(compositorCreateInfo);
        fprintf(stderr, "[Kine] Filament Vulkan device created: %p\n",
            static_cast<void*>(device));
        return device;
    }

private:
    KineVulkanCompositor* mCompositor = nullptr;
    void* mSdlWindow = nullptr;
    int mWidth = 0;
    int mHeight = 0;
    bool mLoggedBundle = false;
    bool mLoggedAcquire = false;
    bool mLoggedPresent = false;
};
#endif

// Material kinds are in header

// ---------------------------------------------------------------------------
// Platform GL-context save/restore helpers.
//
// Create() needs to: (1) remember the host's current context, (2) drop it so
// Filament's Engine::create() can set up its own shared context cleanly, and
// (3) hand control back to the host once Filament is initialized. Destroy()
// needs to (1) again on the way out so Filament's teardown calls land on the
// right context.
// ---------------------------------------------------------------------------

#if !KINE_FILAMENT_USE_VULKAN
static void kine_capture_host_context(KineFilamentContext* ctx)
{
#if defined(_WIN32)
    ctx->hostCtx = (void*)wglGetCurrentContext();
    ctx->hostDC  = (void*)wglGetCurrentDC();
#elif defined(__APPLE__)
    ctx->hostCtx = (void*)CGLGetCurrentContext();
#else
    ctx->hostCtx      = (void*)glXGetCurrentContext();
    ctx->hostDisplay  = (void*)glXGetCurrentDisplay();
    ctx->hostDrawable = (unsigned long)glXGetCurrentDrawable();
#endif
}

static void kine_release_current_gl_context()
{
#if defined(_WIN32)
    wglMakeCurrent(nullptr, nullptr);
#elif defined(__APPLE__)
    CGLSetCurrentContext(nullptr);
#else
    Display* dpy = glXGetCurrentDisplay();
    if (dpy) glXMakeCurrent(dpy, None, nullptr);
#endif
}

static void kine_restore_host_context(KineFilamentContext* ctx)
{
    if (!ctx || !ctx->hostCtx) return;
#if defined(_WIN32)
    wglMakeCurrent((HDC)ctx->hostDC, (HGLRC)ctx->hostCtx);
#elif defined(__APPLE__)
    CGLSetCurrentContext((CGLContextObj)ctx->hostCtx);
#else
    if (ctx->hostDisplay)
        glXMakeCurrent((Display*)ctx->hostDisplay,
                        (GLXDrawable)ctx->hostDrawable,
                        (GLXContext)ctx->hostCtx);
#endif
}
#endif

// ---------------------------------------------------------------------------
// Embedded minimal unlit+texture material bytes.
// Generated offline with:
//   matc -a opengl -o kine_default.filamat kine_default.mat
// and then xxd -i into this array.
// Since we can't run matc at build time here, we use the uberarchive's
// "defaultMaterial" entry by reading it at runtime from the SDK.
// ---------------------------------------------------------------------------

namespace {

// ---------------------------------------------------------------------------
// Procedural mesh generators
// ---------------------------------------------------------------------------

#if !KINE_FILAMENT_USE_VULKAN
static unsigned int createGLColorTexture(int width, int height)
{
    GLuint id = 0;
    glGenTextures(1, &id);
    if (id == 0) return 0;
    glBindTexture(GL_TEXTURE_2D, id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindTexture(GL_TEXTURE_2D, 0);
    return (unsigned int)id;
}
#endif

bool rebuildRenderTarget(KineFilamentContext* ctx, int width, int height)
{
#if !KINE_FILAMENT_USE_VULKAN
    if (ctx->readFboId) { GLuint f=(GLuint)ctx->readFboId; kine_glDeleteFramebuffers(1,&f); ctx->readFboId=0; }
#endif
    if (ctx->renderTarget) { ctx->engine->destroy(ctx->renderTarget); ctx->renderTarget = nullptr; }
    if (ctx->colorTarget)  { ctx->engine->destroy(ctx->colorTarget);  ctx->colorTarget  = nullptr; }
    if (ctx->depthTarget)  { ctx->engine->destroy(ctx->depthTarget);  ctx->depthTarget  = nullptr; }

    // engine->destroy() posts to a command queue — flush and wait so the backend
    // has fully released the imported GL texture before we call glDeleteTextures.
    ctx->engine->flushAndWait();

#if !KINE_FILAMENT_USE_VULKAN
    if (ctx->colorTextureId) {
        GLuint old = (GLuint)ctx->colorTextureId;
        glDeleteTextures(1, &old);
        ctx->colorTextureId = 0;
    }
#endif

#if KINE_FILAMENT_USE_VULKAN
    ctx->colorTarget = Texture::Builder()
        .width(uint32_t(width)).height(uint32_t(height)).levels(1)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::RGBA8)
        .build(*ctx->engine);
#else
    unsigned int glId = createGLColorTexture(width, height);
    if (glId == 0) return false;
    ctx->colorTarget = Texture::Builder()
        .width(uint32_t(width)).height(uint32_t(height)).levels(1)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::RGBA8)
        .import(glId)
        .build(*ctx->engine);
#endif
    if (!ctx->colorTarget) return false;

    ctx->depthTarget = Texture::Builder()
        .width(uint32_t(width)).height(uint32_t(height)).levels(1)
        .usage(Texture::Usage::DEPTH_ATTACHMENT | Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::DEPTH24)
        .build(*ctx->engine);
    if (!ctx->depthTarget) return false;

    ctx->renderTarget = RenderTarget::Builder()
        .texture(RenderTarget::AttachmentPoint::COLOR, ctx->colorTarget)
        .texture(RenderTarget::AttachmentPoint::DEPTH, ctx->depthTarget) 
        .build(*ctx->engine);
    if (!ctx->renderTarget) return false;

    ctx->view->setRenderTarget(ctx->renderTarget);
    ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});
    ctx->viewportX = 0;
    ctx->viewportY = 0;
    ctx->viewportWidth = width;
    ctx->viewportHeight = height;
#if KINE_FILAMENT_USE_VULKAN
    ctx->colorTextureId = 0;
#else
    ctx->colorTextureId = glId;
#endif
    ctx->width  = width;
    ctx->height = height;
    return true;
}

static bool useDefaultSwapChainRenderTarget(KineFilamentContext* ctx, int width, int height)
{
    if (!ctx || !ctx->view) {
        return false;
    }

    if (ctx->readFboId) {
#if !KINE_FILAMENT_USE_VULKAN
        GLuint f = (GLuint)ctx->readFboId;
        kine_glDeleteFramebuffers(1, &f);
#endif
        ctx->readFboId = 0;
    }
    if (ctx->renderTarget) {
        ctx->engine->destroy(ctx->renderTarget);
        ctx->renderTarget = nullptr;
    }
    if (ctx->colorTarget) {
        ctx->engine->destroy(ctx->colorTarget);
        ctx->colorTarget = nullptr;
    }
    if (ctx->depthTarget) {
        ctx->engine->destroy(ctx->depthTarget);
        ctx->depthTarget = nullptr;
    }
    if (ctx->colorTextureId) {
#if !KINE_FILAMENT_USE_VULKAN
        GLuint old = (GLuint)ctx->colorTextureId;
        glDeleteTextures(1, &old);
#endif
        ctx->colorTextureId = 0;
    }

    ctx->view->setRenderTarget(nullptr);
    ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});
    ctx->viewportX = 0;
    ctx->viewportY = 0;
    ctx->viewportWidth = width;
    ctx->viewportHeight = height;
    ctx->width = width;
    ctx->height = height;
    return true;
}

static void* getFilamentNativeWindowFromSDL(void* sdlWindow)
{
    if (!sdlWindow) {
        return nullptr;
    }

    Uint64 flags = SDL_GetWindowFlags((SDL_Window*)sdlWindow);
    SDL_PropertiesID props = SDL_GetWindowProperties((SDL_Window*)sdlWindow);
    if (!props) {
        fprintf(stderr, "[Kine] SDL_GetWindowProperties failed for Vulkan window, flags=0x%llx\n",
            (unsigned long long)flags);
        return nullptr;
    }

#if defined(_WIN32)
    void* hwnd = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, nullptr);
    if (hwnd) {
        fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx hwnd=%p\n",
            (unsigned long long)flags, hwnd);
        return hwnd;
    }
    void* hdc = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HDC_POINTER, nullptr);
    fprintf(stderr, "[Kine] SDL Vulkan native window missing HWND, flags=0x%llx hdc=%p\n",
        (unsigned long long)flags, hdc);
    return nullptr;
#elif defined(__APPLE__)
    void* cocoaWindow = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nullptr);
    fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx cocoaWindow=%p\n",
        (unsigned long long)flags, cocoaWindow);
    return cocoaWindow;
#else
    void* waylandSurface = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, nullptr);
    if (waylandSurface) {
        fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx waylandSurface=%p\n",
            (unsigned long long)flags, waylandSurface);
        return waylandSurface;
    }
    Sint64 x11Window = SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
    fprintf(stderr, "[Kine] SDL Vulkan native window: flags=0x%llx x11Window=0x%llx\n",
        (unsigned long long)flags, (unsigned long long)x11Window);
    return x11Window ? (void*)(uintptr_t)x11Window : nullptr;
#endif
}

static KineMesh* buildCube()
{
    auto* m = new KineMesh();

    // 6 faces x 4 vertices = 24, 6 faces x 2 tris x 3 verts = 36 indices
    const float n = 0.5f;
    struct Face { float nx,ny,nz; float ax,ay,az; float bx,by,bz; };
    Face faces[6] = {
        { 0, 0,  1,  1, 0, 0,  0, 1, 0}, // +Z
        { 0, 0, -1, -1, 0, 0,  0, 1, 0}, // -Z
        { 1, 0,  0,  0, 1, 0,  0, 0, 1}, // +X
        {-1, 0,  0,  0, 1, 0,  0, 0,-1}, // -X
        { 0, 1,  0,  1, 0, 0,  0, 0,-1}, // +Y
        { 0,-1,  0,  1, 0, 0,  0, 0, 1}, // -Y
    };

    for (int f = 0; f < 6; f++) {
        uint16_t base = (uint16_t)(m->vertices.size());
        float nx = faces[f].nx, ny = faces[f].ny, nz = faces[f].nz;
        float ax = faces[f].ax, ay = faces[f].ay, az = faces[f].az;
        float bx = faces[f].bx, by = faces[f].by, bz = faces[f].bz;
        // center of this face
        float cx = nx*n, cy = ny*n, cz = nz*n;
        // 4 corners
        float signs[4][2] = {{-1,-1},{1,-1},{1,1},{-1,1}};
        for (auto& s : signs) {
            KineVertex v;
            v.px = cx + s[0]*ax*n + s[1]*bx*n;
            v.py = cy + s[0]*ay*n + s[1]*by*n;
            v.pz = cz + s[0]*az*n + s[1]*bz*n;
            v.nx = nx; v.ny = ny; v.nz = nz;
            v.u = (s[0]+1)*0.5f; v.v = (s[1]+1)*0.5f;
            m->vertices.push_back(v);
        }
        m->indices.push_back(base+0); m->indices.push_back(base+1); m->indices.push_back(base+2);
        m->indices.push_back(base+0); m->indices.push_back(base+2); m->indices.push_back(base+3);
    }
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static KineMesh* buildSphere(int slices = 16, int stacks = 12)
{
    auto* m = new KineMesh();
    for (int j = 0; j <= stacks; j++) {
        float phi = (float)M_PI * j / stacks;
        for (int i = 0; i <= slices; i++) {
            float theta = 2.0f * (float)M_PI * i / slices;
            KineVertex v;
            v.nx = sinf(phi) * cosf(theta);
            v.ny = cosf(phi);
            v.nz = sinf(phi) * sinf(theta);
            v.px = v.nx * 0.5f;
            v.py = v.ny * 0.5f;
            v.pz = v.nz * 0.5f;
            v.u = (float)i / slices;
            v.v = (float)j / stacks;
            m->vertices.push_back(v);
        }
    }
    for (int j = 0; j < stacks; j++) {
        for (int i = 0; i < slices; i++) {
            uint16_t a = (uint16_t)(j*(slices+1)+i);
            uint16_t b = (uint16_t)(a+slices+1);
            m->indices.push_back(a);   m->indices.push_back(b);   m->indices.push_back(a+1);
            m->indices.push_back(b);   m->indices.push_back(b+1); m->indices.push_back(a+1);
        }
    }
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static KineMesh* buildPyramid()
{
    auto* m = new KineMesh();
    // 4 triangular sides + 1 square base = 16 verts, 6 tris
    const float h = 0.5f, b = 0.5f;
    float apex[3] = {0, h, 0};
    float base4[4][3] = {{-b,0,-b},{b,0,-b},{b,0,b},{-b,0,b}};
    // Side faces
    for (int i = 0; i < 4; i++) {
        float* p0 = base4[i];
        float* p1 = base4[(i+1)%4];
        // Normal = cross(p1-p0, apex-p0)
        float ax = p1[0]-p0[0], ay = p1[1]-p0[1], az = p1[2]-p0[2];
        float bx = apex[0]-p0[0], by2 = apex[1]-p0[1], bz = apex[2]-p0[2];
        float nx = ay*bz - az*by2, ny = az*bx - ax*bz, nz = ax*by2 - ay*bx;
        float len = sqrtf(nx*nx+ny*ny+nz*nz)+1e-9f;
        nx/=len; ny/=len; nz/=len;
        uint16_t base = (uint16_t)m->vertices.size();
        m->vertices.push_back({apex[0], apex[1], apex[2], nx, ny, nz, 0.5f, 1.0f});
        m->vertices.push_back({p0[0],   p0[1],   p0[2],   nx, ny, nz, 0.0f, 0.0f});
        m->vertices.push_back({p1[0],   p1[1],   p1[2],   nx, ny, nz, 1.0f, 0.0f});
        m->indices.push_back(base); m->indices.push_back(base+1); m->indices.push_back(base+2);
    }
    // Base (square, two tris)
    uint16_t base = (uint16_t)m->vertices.size();
    for (auto& p : base4) {
        float u = (p[0]/b+1)*0.5f, v2 = (p[2]/b+1)*0.5f;
        m->vertices.push_back({p[0], p[1], p[2], 0,-1,0, u, v2});
    }
    m->indices.push_back(base); m->indices.push_back(base+2); m->indices.push_back(base+1);
    m->indices.push_back(base); m->indices.push_back(base+3); m->indices.push_back(base+2);
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static KineMesh* buildDecalQuad()
{
    auto* m = new KineMesh();
    m->vertices = {
        {-0.5f, 0.0f, -0.5f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f},
        { 0.5f, 0.0f, -0.5f, 0.0f, 1.0f, 0.0f, 1.0f, 0.0f},
        { 0.5f, 0.0f,  0.5f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f},
        {-0.5f, 0.0f,  0.5f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f},
    };
    m->indices = {0, 1, 2, 0, 2, 3};
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static void appendCuboid(KineMesh* m, float cx, float cy, float cz, float sx, float sy, float sz)
{
    const float x0 = cx - sx * 0.5f, x1 = cx + sx * 0.5f;
    const float y0 = cy - sy * 0.5f, y1 = cy + sy * 0.5f;
    const float z0 = cz - sz * 0.5f, z1 = cz + sz * 0.5f;

    struct Face { float n[3]; float p[4][3]; };
    const Face faces[6] = {
        {{ 1, 0, 0}, {{x1,y0,z0},{x1,y1,z0},{x1,y1,z1},{x1,y0,z1}}},
        {{-1, 0, 0}, {{x0,y0,z1},{x0,y1,z1},{x0,y1,z0},{x0,y0,z0}}},
        {{ 0, 1, 0}, {{x0,y1,z0},{x0,y1,z1},{x1,y1,z1},{x1,y1,z0}}},
        {{ 0,-1, 0}, {{x0,y0,z1},{x0,y0,z0},{x1,y0,z0},{x1,y0,z1}}},
        {{ 0, 0, 1}, {{x0,y0,z1},{x1,y0,z1},{x1,y1,z1},{x0,y1,z1}}},
        {{ 0, 0,-1}, {{x1,y0,z0},{x0,y0,z0},{x0,y1,z0},{x1,y1,z0}}},
    };

    for (const Face& f : faces) {
        uint16_t base = (uint16_t)m->vertices.size();
        m->vertices.push_back({f.p[0][0], f.p[0][1], f.p[0][2], f.n[0], f.n[1], f.n[2], 0, 0});
        m->vertices.push_back({f.p[1][0], f.p[1][1], f.p[1][2], f.n[0], f.n[1], f.n[2], 0, 1});
        m->vertices.push_back({f.p[2][0], f.p[2][1], f.p[2][2], f.n[0], f.n[1], f.n[2], 1, 1});
        m->vertices.push_back({f.p[3][0], f.p[3][1], f.p[3][2], f.n[0], f.n[1], f.n[2], 1, 0});
        m->indices.push_back(base + 0); m->indices.push_back(base + 1); m->indices.push_back(base + 2);
        m->indices.push_back(base + 0); m->indices.push_back(base + 2); m->indices.push_back(base + 3);
    }
}

static KineMesh* buildMoveGizmo()
{
    auto* m = new KineMesh();
    appendCuboid(m, 0.55f, 0.0f, 0.0f, 1.10f, 0.045f, 0.045f);
    appendCuboid(m, 1.17f, 0.0f, 0.0f, 0.22f, 0.16f, 0.16f);
    appendCuboid(m, 0.0f, 0.55f, 0.0f, 0.045f, 1.10f, 0.045f);
    appendCuboid(m, 0.0f, 1.17f, 0.0f, 0.16f, 0.22f, 0.16f);
    appendCuboid(m, 0.0f, 0.0f, 0.55f, 0.045f, 0.045f, 1.10f);
    appendCuboid(m, 0.0f, 0.0f, 1.17f, 0.16f, 0.16f, 0.22f);
    appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

struct KineGizmoAxisMeshes {
    KineMesh* x      = nullptr;
    KineMesh* y      = nullptr;
    KineMesh* z      = nullptr;
    KineMesh* center = nullptr;
};

} // namespace

struct KineFilamentGizmo {
    int type = KINE_GIZMO_MOVE;
    KineGizmoAxisMeshes axes;
};

namespace {

static KineGizmoAxisMeshes buildMoveGizmoAxes()
{
    KineGizmoAxisMeshes g;

    g.x = new KineMesh();
    appendCuboid(g.x, 0.55f, 0.0f, 0.0f, 1.10f, 0.045f, 0.045f);
    appendCuboid(g.x, 1.17f, 0.0f, 0.0f, 0.22f, 0.16f, 0.16f);
    g.x->indexCount = (uint32_t)g.x->indices.size();

    g.y = new KineMesh();
    appendCuboid(g.y, 0.0f, 0.55f, 0.0f, 0.045f, 1.10f, 0.045f);
    appendCuboid(g.y, 0.0f, 1.17f, 0.0f, 0.16f, 0.22f, 0.16f);
    g.y->indexCount = (uint32_t)g.y->indices.size();

    g.z = new KineMesh();
    appendCuboid(g.z, 0.0f, 0.0f, 0.55f, 0.045f, 0.045f, 1.10f);
    appendCuboid(g.z, 0.0f, 0.0f, 1.17f, 0.16f, 0.16f, 0.22f);
    g.z->indexCount = (uint32_t)g.z->indices.size();

    g.center = new KineMesh();
    appendCuboid(g.center, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
    g.center->indexCount = (uint32_t)g.center->indices.size();

    return g;
}

static KineMesh* buildScaleGizmo()
{
    auto* m = new KineMesh();
    appendCuboid(m, 0.50f, 0.0f, 0.0f, 1.00f, 0.04f, 0.04f);
    appendCuboid(m, 1.08f, 0.0f, 0.0f, 0.20f, 0.20f, 0.20f);
    appendCuboid(m, 0.0f, 0.50f, 0.0f, 0.04f, 1.00f, 0.04f);
    appendCuboid(m, 0.0f, 1.08f, 0.0f, 0.20f, 0.20f, 0.20f);
    appendCuboid(m, 0.0f, 0.0f, 0.50f, 0.04f, 0.04f, 1.00f);
    appendCuboid(m, 0.0f, 0.0f, 1.08f, 0.20f, 0.20f, 0.20f);
    appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static KineGizmoAxisMeshes buildScaleGizmoAxes()
{
    KineGizmoAxisMeshes g;

    g.x = new KineMesh();
    appendCuboid(g.x, 0.50f, 0.0f, 0.0f, 1.00f, 0.04f, 0.04f);
    appendCuboid(g.x, 1.08f, 0.0f, 0.0f, 0.20f, 0.20f, 0.20f);
    g.x->indexCount = (uint32_t)g.x->indices.size();

    g.y = new KineMesh();
    appendCuboid(g.y, 0.0f, 0.50f, 0.0f, 0.04f, 1.00f, 0.04f);
    appendCuboid(g.y, 0.0f, 1.08f, 0.0f, 0.20f, 0.20f, 0.20f);
    g.y->indexCount = (uint32_t)g.y->indices.size();

    g.z = new KineMesh();
    appendCuboid(g.z, 0.0f, 0.0f, 0.50f, 0.04f, 0.04f, 1.00f);
    appendCuboid(g.z, 0.0f, 0.0f, 1.08f, 0.20f, 0.20f, 0.20f);
    g.z->indexCount = (uint32_t)g.z->indices.size();

    g.center = new KineMesh();
    appendCuboid(g.center, 0.0f, 0.0f, 0.0f, 0.13f, 0.13f, 0.13f);
    g.center->indexCount = (uint32_t)g.center->indices.size();

    return g;
}

static void appendTorus(KineMesh* m, int axis, float radius, float tubeRadius, int segments, int sides)
{
    uint16_t base = (uint16_t)m->vertices.size();
    for (int i = 0; i < segments; ++i) {
        float a = 2.0f * (float)M_PI * (float)i / (float)segments;
        float ca = cosf(a), sa = sinf(a);
        for (int j = 0; j < sides; ++j) {
            float b = 2.0f * (float)M_PI * (float)j / (float)sides;
            float cb = cosf(b), sb = sinf(b);
            float r = radius + tubeRadius * cb;
            float p[3] = {0,0,0};
            float n[3] = {0,0,0};
            if (axis == 0) {
                p[0] = tubeRadius * sb; p[1] = r * ca; p[2] = r * sa;
                n[0] = sb; n[1] = cb * ca; n[2] = cb * sa;
            } else if (axis == 1) {
                p[0] = r * ca; p[1] = tubeRadius * sb; p[2] = r * sa;
                n[0] = cb * ca; n[1] = sb; n[2] = cb * sa;
            } else {
                p[0] = r * ca; p[1] = r * sa; p[2] = tubeRadius * sb;
                n[0] = cb * ca; n[1] = cb * sa; n[2] = sb;
            }
            m->vertices.push_back({p[0], p[1], p[2], n[0], n[1], n[2], (float)i / segments, (float)j / sides});
        }
    }

    for (int i = 0; i < segments; ++i) {
        int ni = (i + 1) % segments;
        for (int j = 0; j < sides; ++j) {
            int nj = (j + 1) % sides;
            uint16_t a = base + (uint16_t)(i * sides + j);
            uint16_t b = base + (uint16_t)(ni * sides + j);
            uint16_t c = base + (uint16_t)(ni * sides + nj);
            uint16_t d = base + (uint16_t)(i * sides + nj);
            m->indices.push_back(a); m->indices.push_back(b); m->indices.push_back(c);
            m->indices.push_back(a); m->indices.push_back(c); m->indices.push_back(d);
        }
    }
}

static KineMesh* buildRotateGizmo()
{
    auto* m = new KineMesh();
    appendTorus(m, 0, 0.85f, 0.018f, 64, 8);
    appendTorus(m, 1, 0.92f, 0.018f, 64, 8);
    appendTorus(m, 2, 0.99f, 0.018f, 64, 8);
    appendCuboid(m, 0.0f, 0.0f, 0.0f, 0.07f, 0.07f, 0.07f);
    m->indexCount = (uint32_t)m->indices.size();
    return m;
}

static KineGizmoAxisMeshes buildRotateGizmoAxes()
{
    KineGizmoAxisMeshes g;

    g.x = new KineMesh();
    appendTorus(g.x, 0, 0.85f, 0.018f, 64, 8);
    g.x->indexCount = (uint32_t)g.x->indices.size();

    g.y = new KineMesh();
    appendTorus(g.y, 1, 0.92f, 0.018f, 64, 8);
    g.y->indexCount = (uint32_t)g.y->indices.size();

    g.z = new KineMesh();
    appendTorus(g.z, 2, 0.99f, 0.018f, 64, 8);
    g.z->indexCount = (uint32_t)g.z->indices.size();

    return g;
}

#if KINE_WITH_ASSIMP
static KineMesh* loadMeshWithAssimp(const char* path)
{
    Assimp::Importer importer;
    const aiScene* scene = importer.ReadFile(
        path,
        aiProcess_Triangulate |
        aiProcess_JoinIdenticalVertices |
        aiProcess_GenSmoothNormals |
        aiProcess_PreTransformVertices |
        aiProcess_ImproveCacheLocality |
        aiProcess_RemoveRedundantMaterials |
        aiProcess_SortByPType
    );
    if (!scene || !scene->HasMeshes()) {
        fprintf(stderr, "[Kine] Assimp failed to load mesh '%s': %s\n", path, importer.GetErrorString());
        return nullptr;
    }

    auto* m = new KineMesh();
    for (unsigned int meshIndex = 0; meshIndex < scene->mNumMeshes; ++meshIndex) {
        const aiMesh* src = scene->mMeshes[meshIndex];
        if (!src || src->mNumVertices == 0 || src->mNumFaces == 0) continue;
        if (m->vertices.size() + src->mNumVertices > 65535) {
            fprintf(stderr, "[Kine] Assimp mesh '%s' exceeds the current 65535 vertex limit\n", path);
            delete m;
            return nullptr;
        }

        uint16_t base = (uint16_t)m->vertices.size();
        for (unsigned int i = 0; i < src->mNumVertices; ++i) {
            const aiVector3D& p = src->mVertices[i];
            aiVector3D n = src->HasNormals() ? src->mNormals[i] : aiVector3D(0.0f, 1.0f, 0.0f);
            aiVector3D uv = src->HasTextureCoords(0) ? src->mTextureCoords[0][i] : aiVector3D(0.0f, 0.0f, 0.0f);
            m->vertices.push_back({p.x, p.y, p.z, n.x, n.y, n.z, uv.x, uv.y});
        }

        for (unsigned int i = 0; i < src->mNumFaces; ++i) {
            const aiFace& f = src->mFaces[i];
            if (f.mNumIndices != 3) continue;
            m->indices.push_back(base + (uint16_t)f.mIndices[0]);
            m->indices.push_back(base + (uint16_t)f.mIndices[1]);
            m->indices.push_back(base + (uint16_t)f.mIndices[2]);
        }
    }

    if (m->vertices.empty() || m->indices.empty()) {
        delete m;
        return nullptr;
    }

    m->indexCount = (uint32_t)m->indices.size();
    return m;
}
#endif

static void uploadMesh(KineMesh* m, Engine* engine)
{
    if (!m || m->vertices.empty()) return;

    math::float3 boundsMin{
        std::numeric_limits<float>::max(),
        std::numeric_limits<float>::max(),
        std::numeric_limits<float>::max()
    };
    math::float3 boundsMax{
        std::numeric_limits<float>::lowest(),
        std::numeric_limits<float>::lowest(),
        std::numeric_limits<float>::lowest()
    };
    for (const KineVertex& vertex : m->vertices) {
        boundsMin.x = std::min(boundsMin.x, vertex.px);
        boundsMin.y = std::min(boundsMin.y, vertex.py);
        boundsMin.z = std::min(boundsMin.z, vertex.pz);
        boundsMax.x = std::max(boundsMax.x, vertex.px);
        boundsMax.y = std::max(boundsMax.y, vertex.py);
        boundsMax.z = std::max(boundsMax.z, vertex.pz);
    }
    m->localBounds.set(boundsMin, boundsMax);

    size_t vsize = m->vertices.size() * sizeof(KineVertex);
    size_t isize = m->indices.size()  * sizeof(uint16_t);

    // --- compute packed tangent frames from the normals we already have ---
    std::vector<math::float3> normals(m->vertices.size());
    for (size_t i = 0; i < m->vertices.size(); ++i)
        normals[i] = { m->vertices[i].nx, m->vertices[i].ny, m->vertices[i].nz };

    std::vector<math::short4> quats(m->vertices.size());
    auto orientation = SurfaceOrientation::Builder()
        .vertexCount((uint32_t)m->vertices.size())
        .normals(normals.data())
        .build();
    orientation->getQuats(quats.data(), (uint32_t)m->vertices.size());

    delete orientation;

    m->vb = VertexBuffer::Builder()
        .vertexCount((uint32_t)m->vertices.size())
        .bufferCount(2)   // buffer 0 = interleaved pos/uv, buffer 1 = tangents
        .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, offsetof(KineVertex, px), sizeof(KineVertex))
        .attribute(VertexAttribute::UV0,      0, VertexBuffer::AttributeType::FLOAT2, offsetof(KineVertex, u),  sizeof(KineVertex))
        .attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::SHORT4, 0, sizeof(math::short4))
        .normalized(VertexAttribute::TANGENTS)
        .build(*engine);

    // buffer 0: interleaved position/normal/uv, as before
    void* vcopy = malloc(vsize);
    memcpy(vcopy, m->vertices.data(), vsize);
    m->vb->setBufferAt(*engine, 0,
        VertexBuffer::BufferDescriptor(vcopy, vsize,
            [](void* buf, size_t, void*){ free(buf); }, nullptr));

    // buffer 1: packed tangent-frame quaternions
    size_t qsize = quats.size() * sizeof(math::short4);
    void* qcopy = malloc(qsize);
    memcpy(qcopy, quats.data(), qsize);
    m->vb->setBufferAt(*engine, 1,
        VertexBuffer::BufferDescriptor(qcopy, qsize,
            [](void* buf, size_t, void*){ free(buf); }, nullptr));

    m->ib = IndexBuffer::Builder()
        .indexCount(m->indexCount)
        .bufferType(IndexBuffer::IndexType::USHORT)
        .build(*engine);

    void* icopy = malloc(isize);
    memcpy(icopy, m->indices.data(), isize);
    m->ib->setBuffer(*engine,
        IndexBuffer::BufferDescriptor(icopy, isize,
            [](void* buf, size_t, void*){ free(buf); }, nullptr));
}

bool rebuildRenderTarget(KineFilamentContext* ctx, unsigned int textureId, int width, int height)
{
    if (ctx->renderTarget) { ctx->engine->destroy(ctx->renderTarget); ctx->renderTarget = nullptr; }
    if (ctx->colorTarget)  { ctx->engine->destroy(ctx->colorTarget);  ctx->colorTarget  = nullptr; }

    ctx->engine->flushAndWait();


    ctx->colorTarget = Texture::Builder()
        .width(uint32_t(width))
        .height(uint32_t(height))
        .levels(1)
        .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::RGBA8)
        .import(textureId)
        .build(*ctx->engine);

    if (!ctx->colorTarget) return false;

    ctx->renderTarget = RenderTarget::Builder()
        .texture(RenderTarget::AttachmentPoint::COLOR, ctx->colorTarget)
        .build(*ctx->engine);

    if (!ctx->renderTarget) return false;

    ctx->view->setRenderTarget(ctx->renderTarget);
    ctx->view->setViewport({0, 0, uint32_t(width), uint32_t(height)});

    ctx->width  = width;
    ctx->height = height;
    return true;
}

// ---------------------------------------------------------------------------
// Applies a batch's shared color/params to a freshly-created MaterialInstance.
// Every draw call folded into a given batch was queued with an identical
// KineBatchKey, so it's correct for all of that batch's GPU instances to
// share one MaterialInstance built this way.
// ---------------------------------------------------------------------------
static void kine_apply_material_params(MaterialInstance* mi, const KineBatchKey& key, float time, Texture* whiteTex)
{
    if (key.materialKind == KINE_MAT_GLASS) {
        mi->setParameter("baseColor", RgbType::LINEAR, math::float3{key.r, key.g, key.b});
        mi->setParameter("roughness",    key.param1);
        mi->setParameter("ior",          key.param2);
        mi->setParameter("thickness",    key.param3);
        mi->setParameter("transmission", key.transmission);
    } else if (key.materialKind == KINE_MAT_NEON) {
        mi->setParameter("emissiveColor", RgbType::LINEAR, math::float3{key.r, key.g, key.b});
        mi->setParameter("intensity",     key.param1);
    } else if (key.materialKind == KINE_MAT_WATER) {
        mi->setParameter("baseColor", RgbType::LINEAR, math::float3{key.r, key.g, key.b});
        mi->setParameter("roughness",   key.param1);       // ~0.05-0.15 for calm water
        mi->setParameter("ior",         key.param2);       // 1.33
        mi->setParameter("thickness",   key.param3);
        mi->setParameter("transmission", key.transmission);
        mi->setParameter("time",        time);
        mi->setParameter("waveScale",   4.0f);
        mi->setParameter("waveSpeed",   1.0f);
        mi->setParameter("foamAmount",  0.3f);
    } else if (key.materialKind == KINE_MAT_OUTLINE) {
        mi->setParameter("baseColor", RgbType::LINEAR, math::float3{key.r, key.g, key.b});
        mi->setParameter("thickness", key.param1);
    } else {
        mi->setParameter("baseColor", RgbaType::LINEAR, math::float4{key.r, key.g, key.b, 1.0f});
        mi->setParameter("roughness", key.param1);
        mi->setParameter("metallic",  key.param2);
        float uvScale = key.param3 > 0.0f ? key.param3 : 1.0f;
        mi->setParameter("uvScale", math::float2{uvScale, uvScale});

        TextureSampler repeatSampler(
            TextureSampler::MinFilter::LINEAR,
            TextureSampler::MagFilter::LINEAR,
            TextureSampler::WrapMode::REPEAT
        );

        if (key.texture && key.texture->tex) {
            mi->setParameter("hasTexture", 1.0f);
            mi->setParameter("baseColorMap", key.texture->tex, repeatSampler);
        } else {
            mi->setParameter("hasTexture", 0.0f);
            mi->setParameter("baseColorMap", whiteTex, repeatSampler);
        }

        if (key.texture && key.texture->normalTex) {
            mi->setParameter("hasNormalMap", 1.0f);
            mi->setParameter("normalMap", key.texture->normalTex, repeatSampler);
        } else {
            mi->setParameter("hasNormalMap", 0.0f);
            mi->setParameter("normalMap", whiteTex, repeatSampler);
        }

        if (key.texture && key.texture->ormTex) {
            mi->setParameter("hasOrmMap", 1.0f);
            mi->setParameter("ormMap", key.texture->ormTex, repeatSampler);
        } else {
            mi->setParameter("hasOrmMap", 0.0f);
            mi->setParameter("ormMap", whiteTex, repeatSampler);
        }
    }
}

// ---------------------------------------------------------------------------
// Filament culls all instances of a renderable against one shared box. Union
// the real transformed mesh bounds so large, rotated, or elongated parts are
// included in both the camera and shadow-caster passes.
// ---------------------------------------------------------------------------
static Box kine_compute_batch_bounds(
    const KineMesh* mesh,
    const math::mat4f* transforms,
    size_t count)
{
    Box bounds = rigidTransform(mesh->localBounds, transforms[0]);
    for (size_t i = 1; i < count; i++) {
        bounds.unionSelf(rigidTransform(mesh->localBounds, transforms[i]));
    }
    return bounds;
}

static void kine_destroy_batch_chunks(
    KineFilamentContext* ctx,
    KinePersistentBatch& batch)
{
    for (KineBuiltBatch& chunk : batch.chunks) {
        if (!chunk.entity.isNull()) {
            ctx->scene->remove(chunk.entity);
            ctx->engine->destroy(chunk.entity);
            EntityManager::get().destroy(chunk.entity);
        }
        if (chunk.instanceBuffer) {
            ctx->engine->destroy(chunk.instanceBuffer);
        }
    }
    batch.chunks.clear();
}

static void kine_destroy_persistent_batch(
    KineFilamentContext* ctx,
    KinePersistentBatch& batch)
{
    kine_destroy_batch_chunks(ctx, batch);
    if (batch.matInst) {
        ctx->engine->destroy(batch.matInst);
        batch.matInst = nullptr;
    }
}

// ---------------------------------------------------------------------------
// Turns every batch accumulated this frame (via Kine_Filament_DrawMeshEx)
// into one GPU-instanced RenderableManager entity apiece, splitting into
// multiple chunks/draw calls if a batch exceeds the engine's automatic
// instancing limit. Called from Kine_Filament_RenderFrame, right before
// rendering.
// ---------------------------------------------------------------------------
static void kine_update_batches(KineFilamentContext* ctx)
{
    size_t maxInstances = ctx->engine->getMaxAutomaticInstances();
    if (maxInstances == 0) maxInstances = 1;

    std::vector<std::pair<KineBatchKey, KinePendingBatch*>> sortedBatches;
    sortedBatches.reserve(ctx->pendingBatches.size());
    for (auto& kv : ctx->pendingBatches) {
        if (kv.second.lastQueuedFrame == ctx->batchFrame &&
            !kv.second.transforms.empty() && kv.first.mesh) {
            sortedBatches.push_back({kv.first, &kv.second});
        }
    }
    std::sort(sortedBatches.begin(), sortedBatches.end(),
        [](const auto& a, const auto& b) {
            return a.first.materialKind < b.first.materialKind;
        });

    for (auto& [key, pending] : sortedBatches) {
        KineMesh* m = key.mesh;
        if (!m->vb || !m->ib) continue;

        Material* base = ctx->defaultMaterial;
        if (key.materialKind == KINE_MAT_GLASS) base = ctx->glassMaterial;
        if (key.materialKind == KINE_MAT_NEON)  base = ctx->neonMaterial;
        if (key.materialKind == KINE_MAT_WATER) base = ctx->waterMaterial;
        if (key.materialKind == KINE_MAT_OUTLINE) base = ctx->outlineMaterial;
        if (!base) continue;

        KinePersistentBatch& batch = ctx->builtBatches[key];
        batch.lastUsedFrame = ctx->batchFrame;
        if (!batch.matInst) {
            batch.matInst = base->createInstance();
        }
        kine_apply_material_params(batch.matInst, key, ctx->time, ctx->whiteTex);

        std::vector<math::mat4f>& transforms = pending->transforms;
        const size_t requiredChunks = (transforms.size() + maxInstances - 1) / maxInstances;
        bool rebuildChunks = batch.chunks.size() != requiredChunks;
        if (!rebuildChunks) {
            for (size_t chunkIndex = 0; chunkIndex < requiredChunks; chunkIndex++) {
                const size_t offset = chunkIndex * maxInstances;
                const size_t count = std::min(maxInstances, transforms.size() - offset);
                if (batch.chunks[chunkIndex].instanceCount != count) {
                    rebuildChunks = true;
                    break;
                }
            }
        }

        if (rebuildChunks) {
            kine_destroy_batch_chunks(ctx, batch);
        }

        size_t offset = 0;
        size_t chunkIndex = 0;
        while (offset < transforms.size()) {
            const size_t count = std::min(maxInstances, transforms.size() - offset);
            const math::mat4f* chunkTransforms = transforms.data() + offset;
            const Box bounds = kine_compute_batch_bounds(m, chunkTransforms, count);

            if (rebuildChunks) {
                InstanceBuffer* instanceBuffer = InstanceBuffer::Builder(count).build(*ctx->engine);
                instanceBuffer->setLocalTransforms(chunkTransforms, count, 0);

                Entity entity = EntityManager::get().create();
                RenderableManager::Builder(1)
                    .boundingBox(bounds)
                    .material(0, batch.matInst)
                    .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, m->vb, m->ib, 0, m->indexCount)
                    .culling(key.culling)
                    .receiveShadows(key.receiveShadow)
                    .castShadows(key.castShadow)
                    .instances(count, instanceBuffer)
                    .build(*ctx->engine, entity);

                ctx->scene->addEntity(entity);
                batch.chunks.push_back({entity, instanceBuffer, count});
            } else {
                KineBuiltBatch& chunk = batch.chunks[chunkIndex];
                chunk.instanceBuffer->setLocalTransforms(chunkTransforms, count, 0);
                RenderableManager& rm = ctx->engine->getRenderableManager();
                RenderableManager::Instance renderable = rm.getInstance(chunk.entity);
                if (renderable.isValid()) {
                    rm.setAxisAlignedBoundingBox(renderable, bounds);
                }
            }

            offset += count;
            chunkIndex++;
        }
    }

    // Retained water batches still need their time uniform advanced even
    // when their transforms and material properties are unchanged.
    for (auto& [key, batch] : ctx->builtBatches) {
        if (batch.lastUsedFrame == ctx->batchFrame &&
            key.materialKind == KINE_MAT_WATER && batch.matInst) {
            kine_apply_material_params(batch.matInst, key, ctx->time, ctx->whiteTex);
        }
    }

    for (auto it = ctx->builtBatches.begin(); it != ctx->builtBatches.end();) {
        if (it->second.lastUsedFrame != ctx->batchFrame) {
            kine_destroy_persistent_batch(ctx, it->second);
            it = ctx->builtBatches.erase(it);
        } else {
            ++it;
        }
    }
}

static void kine_finish_batch_frame(KineFilamentContext* ctx)
{
    ctx->batchFrame++;
    for (auto it = ctx->pendingBatches.begin(); it != ctx->pendingBatches.end();) {
        if (ctx->batchFrame - it->second.lastQueuedFrame > 120) {
            it = ctx->pendingBatches.erase(it);
        } else {
            ++it;
        }
    }
}

static void kine_destroy_built_batches(KineFilamentContext* ctx)
{
    for (auto& [key, batch] : ctx->builtBatches) {
        (void)key;
        kine_destroy_persistent_batch(ctx, batch);
    }
    ctx->builtBatches.clear();
}

static void kine_invalidate_batches(
    KineFilamentContext* ctx,
    const KineMesh* mesh,
    const KineTexHandle* texture)
{
    auto matches = [mesh, texture](const KineBatchKey& key) {
        return (mesh && key.mesh == mesh) || (texture && key.texture == texture);
    };

    for (auto it = ctx->builtBatches.begin(); it != ctx->builtBatches.end();) {
        if (matches(it->first)) {
            kine_destroy_persistent_batch(ctx, it->second);
            it = ctx->builtBatches.erase(it);
        } else {
            ++it;
        }
    }
    for (auto it = ctx->pendingBatches.begin(); it != ctx->pendingBatches.end();) {
        if (matches(it->first)) {
            it = ctx->pendingBatches.erase(it);
        } else {
            ++it;
        }
    }
    for (auto& [streamId, state] : ctx->retainedLists) {
        (void)streamId;
        const size_t oldSize = state.keys.size();
        state.keys.erase(
            std::remove_if(state.keys.begin(), state.keys.end(), matches),
            state.keys.end());
        if (state.keys.size() != oldSize) {
            state.initialized = false;
        }
    }
}

static void kine_destroy_decal(KineFilamentContext* ctx, KineDecalResource& decal)
{
    if (!decal.entity.isNull()) {
        ctx->scene->remove(decal.entity);
        ctx->engine->destroy(decal.entity);
        EntityManager::get().destroy(decal.entity);
        decal.entity = {};
    }
    if (decal.material) {
        ctx->engine->destroy(decal.material);
        decal.material = nullptr;
    }
    if (decal.mesh) {
        if (decal.mesh->vb) ctx->engine->destroy(decal.mesh->vb);
        if (decal.mesh->ib) ctx->engine->destroy(decal.mesh->ib);
        delete decal.mesh;
        decal.mesh = nullptr;
    }
}

}

static Material* buildDefaultMaterial(Engine* engine)
{
    return Material::Builder()
        .package(KINE_DEFAULT_PACKAGE_KINE_DEFAULT_DATA, KINE_DEFAULT_PACKAGE_KINE_DEFAULT_SIZE)
        .build(*engine);
}

static Material* buildWaterMaterial(Engine* engine) {
    return Material::Builder()
        .package(KINE_WATER_PACKAGE_KINE_WATER_DATA, KINE_WATER_PACKAGE_KINE_WATER_SIZE)
        .build(*engine);
}

static Material* buildNeonMaterial(Engine* engine) {
    return Material::Builder()
        .package(KINE_NEON_PACKAGE_KINE_NEON_DATA, KINE_NEON_PACKAGE_KINE_NEON_SIZE)
        .build(*engine);
}

static Material* buildGlassMaterial(Engine* engine) {
    return Material::Builder()
        .package(KINE_GLASS_PACKAGE_KINE_GLASS_DATA, KINE_GLASS_PACKAGE_KINE_GLASS_SIZE)
        .build(*engine);
}

static Material* buildDecalMaterial(Engine* engine) {
    return Material::Builder()
        .package(KINE_DECAL_PACKAGE_KINE_DECAL_DATA, KINE_DECAL_PACKAGE_KINE_DECAL_SIZE)
        .build(*engine);
}

static Material* buildOutlineMaterial(Engine* engine) {
    return Material::Builder()
        .package(KINE_OUTLINE_PACKAGE_KINE_OUTLINE_DATA, KINE_OUTLINE_PACKAGE_KINE_OUTLINE_SIZE)
        .build(*engine);
}

static Texture* kine_create_uploaded_rgba_texture(
    Engine* engine,
    int width, int height,
    int rowBytes,
    const void* pixelsRGBA8)
{
    if (!engine || !pixelsRGBA8 || width <= 0 || height <= 0 || rowBytes <= 0)
        return nullptr;

    size_t bytes = (size_t)rowBytes * height;
    uint8_t* copy = (uint8_t*)malloc(bytes);
    if (!copy) return nullptr;
    memcpy(copy, pixelsRGBA8, bytes);

    Texture* tex = Texture::Builder()
        .width((uint32_t)width)
        .height((uint32_t)height)
        .levels(1)
        .usage(Texture::Usage::UPLOADABLE | Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::RGBA8)
        .build(*engine);

    if (!tex) {
        free(copy);
        return nullptr;
    }

    uint32_t strideTexels = (uint32_t)(rowBytes / 4);
    Texture::PixelBufferDescriptor pb(
        copy, bytes,
        Texture::Format::RGBA, Texture::Type::UBYTE,
        /*alignment*/ 1, /*left*/ 0, /*top*/ 0, /*stride*/ strideTexels,
        [](void* buffer, size_t, void*) { free(buffer); });

    tex->setImage(*engine, 0, 0, 0,
                  (uint32_t)width, (uint32_t)height, std::move(pb));
    return tex;
}

extern "C" {

static KineFilamentContext* Kine_Filament_CreateInternal(
    int width,
    int height,
    void* nativeWindow,
    void* vulkanCompositor = nullptr,
    bool useFilamentOwnedCompositor = false)
{
    setvbuf(stderr, nullptr, _IONBF, 0);
    if (width <= 0 || height <= 0) return nullptr;

    auto* ctx = new KineFilamentContext();
    ctx->nativeWindow = nativeWindow;
    ctx->useFilamentOwnedCompositor = useFilamentOwnedCompositor;
    ctx->renderToSwapChain = nativeWindow != nullptr || vulkanCompositor != nullptr ||
        useFilamentOwnedCompositor;

#if KINE_FILAMENT_USE_VULKAN
    if (useFilamentOwnedCompositor) {
        ctx->vulkanPlatform = std::make_unique<KineFilamentCompositorVulkanPlatform>(
            nativeWindow,
            width,
            height);
        fprintf(stderr, "[Kine] creating Filament-owned Vulkan compositor engine\n");
        ctx->engine = Engine::create(
            backend::Backend::VULKAN,
            ctx->vulkanPlatform.get(),
            nullptr);
    } else if (vulkanCompositor) {
        ctx->vulkanCompositor = vulkanCompositor;
        KineVulkanCompositorInfo info{};
        if (!Kine_VulkanCompositor_GetInfo(
                reinterpret_cast<KineVulkanCompositor*>(vulkanCompositor),
                &info)) {
            delete ctx;
            return nullptr;
        }

        ctx->vulkanSharedContext.instance = reinterpret_cast<VkInstance>(info.instance);
        ctx->vulkanSharedContext.physicalDevice = reinterpret_cast<VkPhysicalDevice>(info.physicalDevice);
        ctx->vulkanSharedContext.logicalDevice = reinterpret_cast<VkDevice>(info.device);
        ctx->vulkanSharedContext.graphicsQueueFamilyIndex = info.graphicsQueueFamilyIndex;
        ctx->vulkanSharedContext.graphicsQueueIndex = info.graphicsQueueCount > 1 ? 1 : 0;
        ctx->vulkanPlatform = nullptr;
        fprintf(stderr,
            "[Kine] creating Filament shared Vulkan engine queueFamily=%u queueIndex=%u queueCount=%u\n",
            ctx->vulkanSharedContext.graphicsQueueFamilyIndex,
            ctx->vulkanSharedContext.graphicsQueueIndex,
            info.graphicsQueueCount);
        ctx->engine = Engine::create(
            backend::Backend::VULKAN,
            ctx->vulkanPlatform.get(),
            &ctx->vulkanSharedContext);
    } else {
        ctx->engine = Engine::create(backend::Backend::VULKAN);
    }
    if (!ctx->engine) { delete ctx; return nullptr; }
#else
    (void)vulkanCompositor;
    void* sharedGLContext = kine_get_current_gl_context();
    if (!sharedGLContext) { delete ctx; return nullptr; }

    kine_capture_host_context(ctx);

    kine_release_current_gl_context();

    ctx->engine = Engine::create(backend::Backend::OPENGL, nullptr, sharedGLContext);
    if (!ctx->engine) { delete ctx; return nullptr; }

#if !KINE_FILAMENT_USE_VULKAN
    kine_restore_host_context(ctx);
#endif

    kine_init_gl_ext();
#endif

    if (ctx->useFilamentOwnedCompositor) {
        fprintf(stderr, "[Kine] creating Filament-owned compositor swapchain size=%dx%d\n", width, height);
        // Use the native-window overload so Filament treats this as a
        // presentable swapchain and invokes VulkanPlatform::present(). The
        // width/height overload is always classified as headless internally.
        ctx->swapChain = ctx->engine->createSwapChain(nativeWindow);
        ctx->engine->flushAndWait();
        if (ctx->vulkanPlatform) {
            auto* platform = static_cast<KineFilamentCompositorVulkanPlatform*>(ctx->vulkanPlatform.get());
            ctx->vulkanCompositor = platform->compositor();
        }
    } else if (ctx->renderToSwapChain && ctx->nativeWindow) {
        fprintf(stderr, "[Kine] creating Filament native swapchain for window=%p size=%dx%d\n",
            ctx->nativeWindow, width, height);
        ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
    } else if (vulkanCompositor) {
        fprintf(stderr, "[Kine] creating Filament compositor swapchain size=%dx%d\n", width, height);
        ctx->swapChain = ctx->engine->createSwapChain(width, height);
    } else {
        fprintf(stderr, "[Kine] creating Filament headless swapchain size=%dx%d\n", width, height);
        ctx->swapChain = ctx->engine->createSwapChain(width, height);
    }
    if (!ctx->swapChain) {
        fprintf(stderr, "[Kine] createSwapChain failed\n");
        Kine_Filament_Destroy(ctx);
        return nullptr;
    }
    ctx->renderer  = ctx->engine->createRenderer();
    ctx->scene     = ctx->engine->createScene();
    ctx->view      = ctx->engine->createView();

    ctx->cameraEntity = EntityManager::get().create();
    ctx->camera = ctx->engine->createCamera(ctx->cameraEntity);
    ctx->camera->setProjection(60.0, double(width) / double(height), 1.0, 500.0);

    ctx->view->setScene(ctx->scene);
    ctx->view->setCamera(ctx->camera);
    ctx->view->setPostProcessingEnabled(false);

    Renderer::ClearOptions clearOptions;
    clearOptions.clearColor = ctx->skyColor;
    clearOptions.clear = !ctx->useFilamentOwnedCompositor;
    clearOptions.discard = !ctx->useFilamentOwnedCompositor;
    ctx->renderer->setClearOptions(clearOptions);

    ctx->defaultMaterial = buildDefaultMaterial(ctx->engine);
    ctx->neonMaterial  = buildNeonMaterial(ctx->engine);
    ctx->glassMaterial = buildGlassMaterial(ctx->engine);
    ctx->waterMaterial = buildWaterMaterial(ctx->engine);
    ctx->decalMaterial = buildDecalMaterial(ctx->engine);
    ctx->outlineMaterial = buildOutlineMaterial(ctx->engine);

    static const uint8_t whitePixel[4] = {255, 255, 255, 255};
    ctx->whiteTex = Texture::Builder()
        .width(1).height(1).levels(1)
        .format(Texture::InternalFormat::RGBA8)
        .build(*ctx->engine);

    Texture::PixelBufferDescriptor pb(
        whitePixel, 4, Texture::Format::RGBA, Texture::Type::UBYTE);
    ctx->whiteTex->setImage(*ctx->engine, 0, std::move(pb));

    ctx->sunLight = EntityManager::get().create();
    math::float3 sunDir = normalize(math::float3{0.5f, -1.0f, 0.8f});
    LightManager::Builder(LightManager::Type::SUN)
        .color(Color::toLinear<ACCURATE>({1.0f, 0.98f, 0.95f}))
        .intensity(100000.0f)
        .direction(sunDir)
        .sunAngularRadius(1.9f)
        .castShadows(true)
        .build(*ctx->engine, ctx->sunLight);
    ctx->scene->addEntity(ctx->sunLight);

    if (ctx->renderToSwapChain) {
        fprintf(stderr, "[Kine] using native swapchain render target\n");
        if (!useDefaultSwapChainRenderTarget(ctx, width, height)) {
            fprintf(stderr, "[Kine] native swapchain render target setup failed\n");
            Kine_Filament_Destroy(ctx);
            return nullptr;
        }
    } else {
        fprintf(stderr, "[Kine] calling rebuildRenderTarget\n");
        if (!rebuildRenderTarget(ctx, width, height)) {
            fprintf(stderr, "[Kine] rebuildRenderTarget failed\n");
            Kine_Filament_Destroy(ctx);
            return nullptr;
        }
    }

#if !KINE_FILAMENT_USE_VULKAN
    kine_restore_host_context(ctx);
#endif

    fprintf(stderr, "[Kine] Create succeeded, colorTextureId=%u\n", ctx->colorTextureId);
    return ctx;
}

KINE_API KineFilamentContext* Kine_Filament_Create(int width, int height)
{
    return Kine_Filament_CreateInternal(width, height, nullptr);
}

KINE_API KineFilamentContext* Kine_Filament_CreateForSDLWindow(void* sdlWindow, int width, int height)
{
#if KINE_FILAMENT_USE_VULKAN
    void* nativeWindow = getFilamentNativeWindowFromSDL(sdlWindow);
    if (!nativeWindow) {
        fprintf(stderr, "[Kine] failed to resolve SDL native window for Filament Vulkan swapchain\n");
        return nullptr;
    }
    return Kine_Filament_CreateInternal(width, height, nativeWindow);
#else
    (void)sdlWindow;
    return Kine_Filament_CreateInternal(width, height, nullptr);
#endif
}

KINE_API KineFilamentContext* Kine_Filament_CreateForVulkanCompositor(
    void* vulkanCompositor,
    int width,
    int height)
{
#if KINE_FILAMENT_USE_VULKAN
    if (!vulkanCompositor) {
        return nullptr;
    }
    return Kine_Filament_CreateInternal(width, height, nullptr, vulkanCompositor);
#else
    (void)vulkanCompositor;
    (void)width;
    (void)height;
    return nullptr;
#endif
}

KINE_API KineFilamentContext* Kine_Filament_CreateForVulkanCompositorWindow(
    void* sdlWindow,
    int width,
    int height)
{
#if KINE_FILAMENT_USE_VULKAN
    if (!sdlWindow) {
        return nullptr;
    }
    return Kine_Filament_CreateInternal(width, height, sdlWindow, nullptr, true);
#else
    (void)sdlWindow;
    (void)width;
    (void)height;
    return nullptr;
#endif
}

KINE_API void* Kine_Filament_GetVulkanCompositor(KineFilamentContext* ctx)
{
#if KINE_FILAMENT_USE_VULKAN
    return ctx ? ctx->vulkanCompositor : nullptr;
#else
    (void)ctx;
    return nullptr;
#endif
}

KINE_API unsigned int Kine_Filament_GetColorTextureId(KineFilamentContext* ctx)
{
    return ctx ? ctx->colorTextureId : 0;
}

KINE_API bool Kine_Filament_GetVulkanBackend(KineFilamentContext* ctx, KineFilamentVulkanBackend* outBackend)
{
    if (!outBackend) {
        return false;
    }
    memset(outBackend, 0, sizeof(*outBackend));

#if KINE_FILAMENT_USE_VULKAN
    if (!ctx || !ctx->engine || ctx->engine->getBackend() != backend::Backend::VULKAN) {
        return false;
    }

    backend::Platform* platform = ctx->engine->getPlatform();
    if (!platform) {
        return false;
    }

    auto* vulkanPlatform = reinterpret_cast<backend::VulkanPlatform*>(platform);
    void* getInstanceProcAddr = (void*)SDL_Vulkan_GetVkGetInstanceProcAddr();
    if (!getInstanceProcAddr) {
        return false;
    }

    outBackend->instance = vulkanPlatform->getInstance();
    outBackend->physicalDevice = vulkanPlatform->getPhysicalDevice();
    outBackend->device = vulkanPlatform->getDevice();
    outBackend->queue = vulkanPlatform->getGraphicsQueue();
    outBackend->graphicsQueueFamilyIndex = vulkanPlatform->getGraphicsQueueFamilyIndex();
    outBackend->maxApiVersion = VK_API_VERSION_1_1;
    outBackend->getInstanceProcAddr = getInstanceProcAddr;
    outBackend->getDeviceProcAddr = nullptr;

    return outBackend->instance && outBackend->physicalDevice &&
        outBackend->device && outBackend->queue;
#else
    (void)ctx;
    return false;
#endif
}

KINE_API void Kine_Filament_CreateSky(KineFilamentContext* ctx, float r, float g, float b, float a)
{
    ctx->skybox = Skybox::Builder()
    .color({r, g, b,a})
    .build(*ctx->engine);
    ctx->scene->setSkybox(ctx->skybox);
}


KINE_API void Kine_Filament_SetPostProcessing(KineFilamentContext* ctx, bool enabled)
{
    ctx->view->setPostProcessingEnabled(enabled);
}

// ---------------------------------------------------------------------------
// Kine_Filament_SetSkyAtmosphere
//
// Procedural atmospheric sky without a custom .filamat material.
// We generate a 32x32 cubemap on the CPU every time this is called, evaluating
// the gradient for every pixel based on its elevation (Y component).
// We also point the built-in sun light entity at the supplied direction and
// scale its intensity.
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_SetSkyAtmosphere(
    KineFilamentContext* ctx,
    float sunDirX,  float sunDirY,  float sunDirZ,
    float skyR,     float skyG,     float skyB,
    float horizonR, float horizonG, float horizonB,
    float groundR,  float groundG,  float groundB,
    float sunIntensity)
{
    if (!ctx || !ctx->engine) return;

    // --- normalise sun direction -------------------------------------------
    float len = sqrtf(sunDirX*sunDirX + sunDirY*sunDirY + sunDirZ*sunDirZ);
    if (len < 1e-6f) { sunDirX = 0.f; sunDirY = 1.f; sunDirZ = 0.f; }
    else { sunDirX /= len; sunDirY /= len; sunDirZ /= len; }

    float lightDirX = -sunDirX;
    float lightDirY = -sunDirY;
    float lightDirZ = -sunDirZ;

    // --- update sun light entity ------------------------------------------
    if (!ctx->sunLight.isNull()) {
        auto& lm = ctx->engine->getLightManager();
        auto inst = lm.getInstance(ctx->sunLight);
        if (inst.isValid()) {
            lm.setDirection(inst, {lightDirX, lightDirY, lightDirZ});
            float elevFactor = (sunDirY + 0.05f) / 0.15f;
            if (elevFactor < 0.f) elevFactor = 0.f;
            if (elevFactor > 1.f) elevFactor = 1.f;
            lm.setIntensity(inst, sunIntensity * elevFactor);
        }
    }

    // Determine the average clear color (used for the renderer background)
    // using the sun's elevation just like the old logic, so things like fog
    // or clear-screen match the predominant sky color.
    float elev = sunDirY;
    float fr, fg, fb;
    if (elev >= 0.15f) { fr = skyR; fg = skyG; fb = skyB; }
    else if (elev >= 0.0f) {
        float t = elev / 0.15f;
        fr = horizonR + t * (skyR - horizonR);
        fg = horizonG + t * (skyG - horizonG);
        fb = horizonB + t * (skyB - horizonB);
    } else if (elev >= -0.10f) {
        float t = (elev + 0.10f) / 0.10f;
        fr = groundR + t * (horizonR - groundR);
        fg = groundG + t * (horizonG - groundG);
        fb = groundB + t * (horizonB - groundB);
    } else { fr = groundR; fg = groundG; fb = groundB; }
    
    auto clamp01 = [](float v) { return v < 0.f ? 0.f : v > 1.f ? 1.f : v; };
    ctx->skyColor = {clamp01(fr), clamp01(fg), clamp01(fb), 1.0f};

    // --- generate procedural cubemap gradient -----------------------------
    const uint32_t faceSize = 32;
    const size_t faceBytes = faceSize * faceSize * 4;
    const size_t totalBytes = 6 * faceBytes;
    
    // Allocated memory will be freed by the PixelBufferDescriptor callback
    uint8_t* pixels = (uint8_t*)malloc(totalBytes);
    if (!pixels) return;

    auto evalSky = [&](float dy) {
        float r, g, b;
        if (dy >= 0.15f) { r = skyR; g = skyG; b = skyB; }
        else if (dy >= 0.0f) {
            float t = dy / 0.15f;
            r = horizonR + t * (skyR - horizonR);
            g = horizonG + t * (skyG - horizonG);
            b = horizonB + t * (skyB - horizonB);
        } else if (dy >= -0.10f) {
            float t = (dy + 0.10f) / 0.10f;
            r = groundR + t * (horizonR - groundR);
            g = groundG + t * (horizonG - groundG);
            b = groundB + t * (horizonB - groundB);
        } else { r = groundR; g = groundG; b = groundB; }
        return std::make_tuple(clamp01(r), clamp01(g), clamp01(b));
    };

    // Fill 6 faces: +X, -X, +Y, -Y, +Z, -Z
    for (int face = 0; face < 6; ++face) {
        uint8_t* facePixels = pixels + face * faceBytes;
        for (uint32_t y = 0; y < faceSize; ++y) {
            for (uint32_t x = 0; x < faceSize; ++x) {
                // map (x,y) to [-1, 1] range
                float u = (2.0f * (x + 0.5f) / faceSize) - 1.0f;
                // Filament (OpenGL convention): +Y is DOWN for texture coordinates? 
                // Wait, standard cubemap: v goes from -1 to 1 top to bottom.
                // We'll just map v from +1 to -1 so Y is up.
                float v = 1.0f - (2.0f * (y + 0.5f) / faceSize);
                
                float dx = 0, dy = 0, dz = 0;
                switch (face) {
                    case 0: dx =  1.0f; dy = v; dz = -u; break; // +X
                    case 1: dx = -1.0f; dy = v; dz =  u; break; // -X
                    case 2: dx =  u; dy =  1.0f; dz = -v; break; // +Y
                    case 3: dx =  u; dy = -1.0f; dz =  v; break; // -Y
                    case 4: dx =  u; dy = v; dz =  1.0f; break; // +Z
                    case 5: dx = -u; dy = v; dz = -1.0f; break; // -Z
                }
                
                float dlen = sqrtf(dx*dx + dy*dy + dz*dz);
                dy /= dlen; // we only need the normalized Y component
                
                auto [pr, pg, pb] = evalSky(dy);
                
                size_t idx = (y * faceSize + x) * 4;
                facePixels[idx + 0] = (uint8_t)(pr * 255.0f);
                facePixels[idx + 1] = (uint8_t)(pg * 255.0f);
                facePixels[idx + 2] = (uint8_t)(pb * 255.0f);
                facePixels[idx + 3] = 255;
            }
        }
    }

    // If we already have a procedural texture, destroy it
    if (ctx->skyTexture) {
        ctx->engine->destroy(ctx->skyTexture);
    }
    
    ctx->skyTexture = Texture::Builder()
        .width(faceSize).height(faceSize).levels(1)
        .sampler(Texture::Sampler::SAMPLER_CUBEMAP)
        .format(Texture::InternalFormat::RGBA8)
        .build(*ctx->engine);

    Texture::PixelBufferDescriptor pb(
        pixels, totalBytes,
        Texture::Format::RGBA, Texture::Type::UBYTE,
        [](void* buffer, size_t size, void* user) { free(buffer); }
    );

    // Cubemaps are treated as a 2D array of 6 layers. We upload all 6 faces in one go.
    ctx->skyTexture->setImage(*ctx->engine, 0, 0, 0, 0, faceSize, faceSize, 6, std::move(pb));

    if (ctx->skybox) {
        ctx->engine->destroy(ctx->skybox);
        ctx->skybox = nullptr;
    }
    
    ctx->skybox = Skybox::Builder()
        .environment(ctx->skyTexture)
        .showSun(true)
        .build(*ctx->engine);
        
    ctx->scene->setSkybox(ctx->skybox);
}

KINE_API void Kine_Filament_CreateSkyboxCubemap(
    KineFilamentContext* ctx,
    const KineGLTextureInfo* texPosX, const KineGLTextureInfo* texNegX,
    const KineGLTextureInfo* texPosY, const KineGLTextureInfo* texNegY,
    const KineGLTextureInfo* texPosZ, const KineGLTextureInfo* texNegZ)
{
#if KINE_FILAMENT_USE_VULKAN
    (void)ctx;
    (void)texPosX; (void)texNegX;
    (void)texPosY; (void)texNegY;
    (void)texPosZ; (void)texNegZ;
    fprintf(stderr,
        "[Kine] CreateSkyboxCubemap cannot import OpenGL texture IDs on the Vulkan backend.\n");
#else
    if (!ctx || !ctx->engine) return;
    
    const KineGLTextureInfo* textures[6] = {
        texPosX, texNegX,
        texPosY, texNegY,
        texPosZ, texNegZ
    };
    
    int width = textures[0] ? textures[0]->width : 0;
    int height = textures[0] ? textures[0]->height : 0;
    if (width <= 0 || height <= 0 || width != height) {
        fprintf(stderr, "[Kine] CreateSkyboxCubemap: Faces must be square and > 0.\n");
        return;
    }
    for (int i=1; i<6; ++i) {
        if (!textures[i] || textures[i]->width != width || textures[i]->height != height) {
            fprintf(stderr, "[Kine] CreateSkyboxCubemap: All faces must have identical square dimensions.\n");
            return;
        }
    }
    
    size_t faceBytes = (size_t)width * height * 4;
    size_t totalBytes = faceBytes * 6;
    uint8_t* pixels = (uint8_t*)malloc(totalBytes);
    if (!pixels) return;
    
    // Read pixels from the 6 OpenGL textures to RAM
    for (int i=0; i<6; ++i) {
        glBindTexture(GL_TEXTURE_2D, textures[i]->id);
        glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels + i * faceBytes);
    }
    glBindTexture(GL_TEXTURE_2D, 0);
    
    if (ctx->skyTexture) {
        ctx->engine->destroy(ctx->skyTexture);
    }
    
    ctx->skyTexture = Texture::Builder()
        .width(width).height(height).levels(1)
        .sampler(Texture::Sampler::SAMPLER_CUBEMAP)
        .format(Texture::InternalFormat::RGBA8)
        .build(*ctx->engine);

    Texture::PixelBufferDescriptor pb(
        pixels, totalBytes,
        Texture::Format::RGBA, Texture::Type::UBYTE,
        [](void* buffer, size_t size, void* user) { free(buffer); }
    );
    
    ctx->skyTexture->setImage(*ctx->engine, 0, 0, 0, 0, width, height, 6, std::move(pb));
    
    if (ctx->skybox) {
        ctx->engine->destroy(ctx->skybox);
    }
    
    ctx->skybox = Skybox::Builder()
        .environment(ctx->skyTexture)
        .showSun(true)
        .build(*ctx->engine);

    ctx->scene->setSkybox(ctx->skybox);
#endif
}

KINE_API void Kine_Filament_SetSun(
    KineFilamentContext* ctx,
    float sunDirX, float sunDirY, float sunDirZ,
    float sunIntensity)
{
    if (!ctx || !ctx->engine || ctx->sunLight.isNull()) return;

    float len = sqrtf(sunDirX*sunDirX + sunDirY*sunDirY + sunDirZ*sunDirZ);
    if (len < 1e-6f) { sunDirX = 0.f; sunDirY = 1.f; sunDirZ = 0.f; }
    else { sunDirX /= len; sunDirY /= len; sunDirZ /= len; }

    float lightDirX = -sunDirX;
    float lightDirY = -sunDirY;
    float lightDirZ = -sunDirZ;

    auto& lm = ctx->engine->getLightManager();
    auto inst = lm.getInstance(ctx->sunLight);
    if (inst.isValid()) {
        lm.setDirection(inst, {lightDirX, lightDirY, lightDirZ});
        lm.setIntensity(inst, sunIntensity);
    }
}


KINE_API void Kine_Filament_Destroy(KineFilamentContext* ctx)
{
    if (!ctx) return;

#if !KINE_FILAMENT_USE_VULKAN
    kine_restore_host_context(ctx);
#endif

    if (ctx->engine) {
        kine_destroy_built_batches(ctx);
        ctx->pendingBatches.clear();
        for (auto& decal : ctx->decals) {
            kine_destroy_decal(ctx, decal);
        }
        ctx->decals.clear();

        // Material instance destruction is queued. Drain it before destroying
        // the materials that own those instances.
        ctx->engine->flushAndWait();

        if (!ctx->sunLight.isNull()) {
            ctx->scene->remove(ctx->sunLight);
            ctx->engine->destroy(ctx->sunLight);
            EntityManager::get().destroy(ctx->sunLight);
        }
        if (ctx->skybox) {
            ctx->scene->setSkybox(nullptr);
            ctx->engine->destroy(ctx->skybox);
            ctx->skybox = nullptr;
        }
        if (ctx->indirectLight) {
            ctx->scene->setIndirectLight(nullptr);
            ctx->engine->destroy(ctx->indirectLight);
            ctx->indirectLight = nullptr;
        }
        if (ctx->skyTexture) {
            ctx->engine->destroy(ctx->skyTexture);
            ctx->skyTexture = nullptr;
        }
        if (ctx->renderTarget)  ctx->engine->destroy(ctx->renderTarget);
        if (ctx->colorTarget)   ctx->engine->destroy(ctx->colorTarget);
        if (ctx->depthTarget)   ctx->engine->destroy(ctx->depthTarget);
        if (ctx->whiteTex)      ctx->engine->destroy(ctx->whiteTex);
        if (ctx->defaultMaterial) ctx->engine->destroy(ctx->defaultMaterial);
        if (ctx->neonMaterial)    ctx->engine->destroy(ctx->neonMaterial);
        if (ctx->glassMaterial)   ctx->engine->destroy(ctx->glassMaterial);
        if (ctx->waterMaterial)   ctx->engine->destroy(ctx->waterMaterial);
        if (ctx->decalMaterial)   ctx->engine->destroy(ctx->decalMaterial);
        if (ctx->outlineMaterial) ctx->engine->destroy(ctx->outlineMaterial);
        if (ctx->colorTextureId) {
#if !KINE_FILAMENT_USE_VULKAN
            GLuint id = (GLuint)ctx->colorTextureId;
            glDeleteTextures(1, &id);
#endif
            ctx->colorTextureId = 0;
        }
        if (!ctx->cameraEntity.isNull()) {
            ctx->engine->destroyCameraComponent(ctx->cameraEntity);
            EntityManager::get().destroy(ctx->cameraEntity);
        }
        if (ctx->view)       ctx->engine->destroy(ctx->view);
        if (ctx->scene)      ctx->engine->destroy(ctx->scene);
        if (ctx->renderer)   ctx->engine->destroy(ctx->renderer);
        if (ctx->swapChain) {
            ctx->engine->destroy(ctx->swapChain);
            ctx->swapChain = nullptr;
        }
        ctx->engine->flushAndWait();
        if (ctx->useFilamentOwnedCompositor && ctx->vulkanPlatform) {
            auto* platform = static_cast<KineFilamentCompositorVulkanPlatform*>(ctx->vulkanPlatform.get());
            platform->destroyCompositor();
            ctx->vulkanCompositor = nullptr;
        }
        Engine::destroy(&ctx->engine);
    }

    delete ctx;
}

KINE_API void Kine_Filament_DebugPrintPixel(KineFilamentContext* ctx)
{
#if KINE_FILAMENT_USE_VULKAN
    fprintf(stderr, "[Kine] DebugPrintPixel uses the OpenGL texture path and is unavailable on Vulkan\n");
    (void)ctx;
    return;
#else
    if (!ctx || ctx->colorTextureId == 0 || ctx->width <= 0 || ctx->height <= 0) return;

    std::vector<unsigned char> buf((size_t)ctx->width * ctx->height * 4);

    glBindTexture(GL_TEXTURE_2D, (GLuint)ctx->colorTextureId);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
    glBindTexture(GL_TEXTURE_2D, 0);

    int cx = ctx->width / 2;
    int cy = ctx->height / 2;
    size_t idx = ((size_t)cy * ctx->width + cx) * 4;

    glBindTexture(GL_TEXTURE_2D, (GLuint)ctx->colorTextureId);
    glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf.data());
    GLenum err = glGetError();
    if (err != GL_NO_ERROR) {
        fprintf(stderr, "[Kine] glGetTexImage GL error: 0x%x\n", err);
    }
    glBindTexture(GL_TEXTURE_2D, 0);

    fprintf(stderr, "[Kine] center pixel RGBA = %d %d %d %d\n",
        buf[idx + 0], buf[idx + 1], buf[idx + 2], buf[idx + 3]);
#endif
}

KINE_API void Kine_Filament_RenderFrame(KineFilamentContext* ctx, float deltaTime)
{
    if (!ctx || !ctx->engine) return;
    ctx->time += deltaTime;

    // Update this frame's persistent GPU-instanced renderables.

#if !KINE_FILAMENT_USE_VULKAN
    glEnable(GL_DEPTH_TEST);   // guard against the host renderer having disabled this last frame
    glDepthMask(GL_TRUE);
#endif

#if KINE_FILAMENT_USE_VULKAN
    if (ctx->useFilamentOwnedCompositor && ctx->vulkanCompositor) {
        if (!Kine_VulkanCompositor_PrepareFilament(
                static_cast<KineVulkanCompositor*>(ctx->vulkanCompositor))) {
            const char* error = Kine_VulkanCompositor_GetLastError(
                static_cast<KineVulkanCompositor*>(ctx->vulkanCompositor));
            fprintf(stderr, "[Kine] compositor prepare for Filament failed: %s\n",
                error && error[0] ? error : "unknown error");
            kine_finish_batch_frame(ctx);
            return;
        }
    }
#endif

    // Filament buffer updates come after Skia has finished with the single
    // shared Vulkan queue, so backend uploads cannot overlap Skia.
    kine_update_batches(ctx);

    if (ctx->renderer->beginFrame(ctx->swapChain)) {
        if (!ctx->loggedFirstFrame) {
            fprintf(stderr, "[Kine] Filament beginFrame OK (%s swapchain, %dx%d)\n",
                ctx->renderToSwapChain ? "native" : "headless",
                ctx->width, ctx->height);
            ctx->loggedFirstFrame = true;
        }
        Renderer::ClearOptions clearOptions;
        clearOptions.clearColor = ctx->skyColor;
        clearOptions.clear = !ctx->useFilamentOwnedCompositor;
        clearOptions.discard = !ctx->useFilamentOwnedCompositor;
        ctx->renderer->setClearOptions(clearOptions);

        ctx->renderer->render(ctx->view);
#if KINE_FILAMENT_USE_VULKAN && KINE_FILAMENT_ENABLE_VULKAN_READBACK
        ctx->readbackPixels.resize((size_t)ctx->width * (size_t)ctx->height * 4);
        backend::PixelBufferDescriptor pb(
            ctx->readbackPixels.data(),
            ctx->readbackPixels.size(),
            backend::PixelDataFormat::RGBA,
            backend::PixelDataType::UBYTE
        );
        ctx->renderer->readPixels(0, 0, (uint32_t)ctx->width, (uint32_t)ctx->height, std::move(pb));
#endif
        ctx->renderer->endFrame();
#if KINE_FILAMENT_USE_VULKAN
        if (ctx->useFilamentOwnedCompositor) {
            // Push the frame to Filament's backend thread. The compositor
            // waits for its present callback without waiting for the GPU.
            ctx->engine->flush();
        }
#endif
    } else {
        fprintf(stderr, "[Kine] beginFrame FAILED this frame\n");
    }
    
    kine_finish_batch_frame(ctx);

#if !KINE_FILAMENT_USE_VULKAN
    if (kine_glBindFramebuffer) {
        kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    glViewport(0, 0, ctx->width, ctx->height);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);
    glDisable(GL_SCISSOR_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    kine_restore_host_context(ctx);
#endif
}

KINE_API void Kine_Filament_Resize(KineFilamentContext* ctx, int width, int height)
{
    if (!ctx || !ctx->engine) return;
    if (width <= 0 || height <= 0) return;
    if (ctx->width == width && ctx->height == height) return;

    // Drain any pending GPU commands that may still reference the old render target
    // textures before we destroy them. Without this, the driver can segfault
    // accessing freed GL objects on the backend thread.
    ctx->engine->flushAndWait();

    if (ctx->swapChain) {
        ctx->engine->destroy(ctx->swapChain);
        ctx->swapChain = nullptr;
    }
    if (ctx->useFilamentOwnedCompositor) {
        fprintf(stderr, "[Kine] recreating Filament-owned compositor swapchain size=%dx%d\n",
            width, height);
        auto* platform = static_cast<KineFilamentCompositorVulkanPlatform*>(ctx->vulkanPlatform.get());
        platform->setExtent(width, height);
        ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
        ctx->engine->flushAndWait();
        if (ctx->vulkanPlatform) {
            ctx->vulkanCompositor = platform->compositor();
        }
        useDefaultSwapChainRenderTarget(ctx, width, height);
    } else if (ctx->renderToSwapChain && ctx->nativeWindow) {
        fprintf(stderr, "[Kine] recreating Filament native swapchain for window=%p size=%dx%d\n",
            ctx->nativeWindow, width, height);
        ctx->swapChain = ctx->engine->createSwapChain(ctx->nativeWindow);
        useDefaultSwapChainRenderTarget(ctx, width, height);
    } else {
        fprintf(stderr, "[Kine] recreating Filament headless swapchain size=%dx%d\n", width, height);
        ctx->swapChain = ctx->engine->createSwapChain(width, height);
        rebuildRenderTarget(ctx, width, height);
    }
    ctx->loggedFirstFrame = false;
    ctx->camera->setProjection(60.0, double(width) / double(height), 1.0, 500.0);
}

KINE_API void Kine_Filament_SetViewport(KineFilamentContext* ctx, int x, int y, int width, int height)
{
    if (!ctx || !ctx->view) return;

    if (width <= 0 || height <= 0) {
        x = 0;
        y = 0;
        width = ctx->width;
        height = ctx->height;
    }

    int clampedX = std::clamp(x, 0, std::max(0, ctx->width - 1));
    int clampedY = std::clamp(y, 0, std::max(0, ctx->height - 1));
    int clampedWidth = std::clamp(width, 1, std::max(1, ctx->width - clampedX));
    int clampedHeight = std::clamp(height, 1, std::max(1, ctx->height - clampedY));

    // Kinemium UI coordinates are top-left origin. Filament's viewport is
    // bottom-left origin when rendering directly into the Vulkan swapchain.
    int filamentY = ctx->height - clampedY - clampedHeight;
    filamentY = std::clamp(filamentY, 0, std::max(0, ctx->height - 1));

    ctx->viewportX = clampedX;
    ctx->viewportY = clampedY;
    ctx->viewportWidth = clampedWidth;
    ctx->viewportHeight = clampedHeight;
    ctx->view->setViewport({
        (int32_t)clampedX,
        (int32_t)filamentY,
        (uint32_t)clampedWidth,
        (uint32_t)clampedHeight
    });

    ctx->camera->setProjection(
        60.0,
        double(clampedWidth) / double(clampedHeight),
        1.0,
        500.0);
}

KINE_API void* Kine_Filament_GetEngine(KineFilamentContext* ctx) { return ctx ? (void*)ctx->engine : nullptr; }
KINE_API void* Kine_Filament_GetScene(KineFilamentContext* ctx)  { return ctx ? (void*)ctx->scene  : nullptr; }
KINE_API void* Kine_Filament_GetView(KineFilamentContext* ctx)   { return ctx ? (void*)ctx->view   : nullptr; }
KINE_API void* Kine_Filament_GetCamera(KineFilamentContext* ctx) { return ctx ? (void*)ctx->camera : nullptr; }

KINE_API void Kine_Filament_SetCameraLookAt(
    KineFilamentContext* ctx,
    float eyeX, float eyeY, float eyeZ,
    float targetX, float targetY, float targetZ,
    float upX, float upY, float upZ)
{
    if (!ctx || !ctx->camera) return;
    ctx->cameraEye = {eyeX, eyeY, eyeZ};
    ctx->cameraTarget = {targetX, targetY, targetZ};
    ctx->cameraUp = {upX, upY, upZ};
    ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

KINE_API bool Kine_Filament_BlitToScreen(KineFilamentContext* ctx, int dstX, int dstY, int dstWidth, int dstHeight)
{
#if KINE_FILAMENT_USE_VULKAN
    (void)ctx; (void)dstX; (void)dstY; (void)dstWidth; (void)dstHeight;
    return false;
#else
    if (!ctx || !ctx->engine || ctx->colorTextureId == 0) return false;
    if (!kine_glBindFramebuffer || !kine_glGenFramebuffers ||
        !kine_glFramebufferTexture2D || !kine_glBlitFramebuffer) return false;

    if (ctx->readFboId == 0) {
        GLuint fbo = 0;
        kine_glGenFramebuffers(1, &fbo);
        kine_glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        kine_glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                     GL_TEXTURE_2D, (GLuint)ctx->colorTextureId, 0);
        ctx->readFboId = (unsigned int)fbo;
        kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }

    kine_glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)ctx->readFboId);
    kine_glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0); // SDL's default framebuffer, must already be bound/current
    kine_glBlitFramebuffer(0, 0, ctx->width, ctx->height,
                            dstX, dstY, dstX + dstWidth, dstY + dstHeight,
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
    kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
    return true;
#endif
}

KINE_API void Kine_Filament_SetCameraPosition(KineFilamentContext* ctx, float x, float y, float z)
{
    if (!ctx || !ctx->camera) return;
    ctx->cameraEye = {x, y, z};
    ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

KINE_API void Kine_Filament_SetCameraDirection(KineFilamentContext* ctx, float dx, float dy, float dz)
{
    if (!ctx || !ctx->camera) return;
    ctx->cameraTarget = ctx->cameraEye + math::double3{dx, dy, dz};
    ctx->camera->lookAt(ctx->cameraEye, ctx->cameraTarget, ctx->cameraUp);
}

// light functions

KINE_API int Kine_Filament_CreateLight(
    KineFilamentContext* ctx,
    float px, float py, float pz,
    float cr, float cg, float cb,
    float intensity,
    float falloff
) {
    if (!ctx || !ctx->engine || !ctx->scene)
        return -1;

    utils::Entity entity = utils::EntityManager::get().create();

    filament::LightManager::Builder(
        filament::LightManager::Type::POINT
    )
        .color({cr, cg, cb})
        .intensity(intensity)
        .position({px, py, pz})
        .falloff(falloff)
        .build(*ctx->engine, entity);

    ctx->scene->addEntity(entity);

    return static_cast<int>(entity.getId());
}

// decals

KINE_API int Kine_Filament_CreateDecal(
    KineFilamentContext* ctx,
    float width,
    float height,
    KineFilamentTex* texture,
    float offsetStudsU,
    float offsetStudsV,
    float studsPerTileU,
    float studsPerTileV,
    bool culling,
    bool castShadows,
    bool receiveShadows
)
{
    auto* texHandle = (KineTexHandle*)texture;
    if (!ctx || !ctx->engine || !ctx->scene || !texHandle || !texHandle->tex ||
        width <= 0.0f || height <= 0.0f)
        return -1;

    Entity entity = EntityManager::get().create();

    MaterialInstance* material = ctx->decalMaterial->createInstance();

    if (!material) {
        EntityManager::get().destroy(entity);
        return -1;
    }

    TextureSampler sampler(
        TextureSampler::MinFilter::LINEAR,
        TextureSampler::MagFilter::LINEAR,
        TextureSampler::WrapMode::REPEAT
    );

    math::float2 uvScale{
        studsPerTileU > 0.0f ? width  / studsPerTileU : 1.0f,
        studsPerTileV > 0.0f ? height / studsPerTileV : 1.0f
    };
    math::float2 uvOffset{
        studsPerTileU > 0.0f ? offsetStudsU / studsPerTileU : 0.0f,
        studsPerTileV > 0.0f ? offsetStudsV / studsPerTileV : 0.0f
    };

    material->setParameter("baseColor", RgbaType::LINEAR, math::float4{1.0f, 1.0f, 1.0f, 1.0f});
    material->setParameter("hasTexture", 1.0f);
    material->setParameter("baseColorMap", texHandle->tex, sampler);
    material->setParameter("uvScale", uvScale);
    material->setParameter("uvOffset", uvOffset);

    KineMesh* mesh = buildDecalQuad();
    uploadMesh(mesh, ctx->engine);

    RenderableManager::Builder(1)
        .boundingBox({
            {-width * 0.5f, -height * 0.5f, -0.01f},
            { width * 0.5f,  height * 0.5f,  0.01f}
        })
        .material(0, material)
        .geometry(
            0,
            RenderableManager::PrimitiveType::TRIANGLES,
            mesh->vb,
            mesh->ib,
            0,
            mesh->indexCount
        )
        .culling(culling)
        .castShadows(castShadows)
        .receiveShadows(receiveShadows)
        .build(*ctx->engine, entity);

    ctx->scene->addEntity(entity);
    ctx->decals.push_back({entity, material, mesh});

    return static_cast<int>(entity.getId());
}

static void kine_compute_decal_uv(
    float width, float height,
    float offsetStudsU, float offsetStudsV,
    float studsPerTileU, float studsPerTileV,
    math::float2& outScale, math::float2& outOffset)
{
    outScale = {
        studsPerTileU > 0.0f ? width  / studsPerTileU : 1.0f,
        studsPerTileV > 0.0f ? height / studsPerTileV : 1.0f
    };
    outOffset = {
        studsPerTileU > 0.0f ? offsetStudsU / studsPerTileU : 0.0f,
        studsPerTileV > 0.0f ? offsetStudsV / studsPerTileV : 0.0f
    };
}

KINE_API bool Kine_Filament_SetDecalTiling(
    KineFilamentContext* ctx, int decal,
    float width, float height,
    float offsetStudsU, float offsetStudsV,
    float studsPerTileU, float studsPerTileV)
{
    if (!ctx || !ctx->engine) return false;

    Entity entity = Entity::import(decal);
    if (entity.isNull()) return false;

    RenderableManager& rm = ctx->engine->getRenderableManager();
    auto instance = rm.getInstance(entity);
    if (!instance.isValid()) return false;

    MaterialInstance* mi = rm.getMaterialInstanceAt(instance, 0);
    if (!mi) return false;

    math::float2 uvScale, uvOffset;
    kine_compute_decal_uv(width, height, offsetStudsU, offsetStudsV,
                           studsPerTileU, studsPerTileV, uvScale, uvOffset);

    mi->setParameter("uvScale", uvScale);
    mi->setParameter("uvOffset", uvOffset);
    return true;
}

KINE_API bool Kine_Filament_SetDecalTransform(KineFilamentContext* ctx, int decal, float* mat4)
{
    if (!ctx || !ctx->engine || !mat4) return false;

    Entity entity = Entity::import(decal);
    if (entity.isNull()) return false;

    RenderableManager& rm = ctx->engine->getRenderableManager();
    if (!rm.hasComponent(entity)) return false;

    // Same column-major transform -> filament mat4f conversion used in
    // Kine_Filament_DrawMeshEx.
    math::mat4f transform(
        math::float4{mat4[0], mat4[4], mat4[8],  mat4[12]},
        math::float4{mat4[1], mat4[5], mat4[9],  mat4[13]},
        math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
        math::float4{mat4[3], mat4[7], mat4[11], mat4[15]}
    );

    TransformManager& tm = ctx->engine->getTransformManager();
    auto instance = tm.getInstance(entity);
    if (!instance.isValid()) {
        tm.create(entity);
        instance = tm.getInstance(entity);
    }
    if (!instance.isValid()) return false;

    tm.setTransform(instance, transform);
    return true;
}

KINE_API void Kine_Filament_RemoveDecal(KineFilamentContext* ctx, int decal)
{
    if (!ctx || !ctx->engine || !ctx->scene)
        return;

    Entity entity = Entity::import(decal);
    if (entity.isNull())
        return;

    auto it = std::find_if(ctx->decals.begin(), ctx->decals.end(),
        [entity](const KineDecalResource& decal) {
            return decal.entity == entity;
        });
    if (it != ctx->decals.end()) {
        kine_destroy_decal(ctx, *it);
        ctx->decals.erase(it);
        return;
    }

    if (ctx->engine->getRenderableManager().hasComponent(entity)) {
        ctx->scene->remove(entity);
        ctx->engine->destroy(entity);
    }
    EntityManager::get().destroy(entity);
}

KINE_API bool Kine_Filament_EditDecal(
    KineFilamentContext* ctx,
    int decal,
    float width,
    float height,
    bool culling,
    bool castShadows,
    bool receiveShadows
)
{
    if (!ctx || !ctx->engine || !ctx->scene ||
        width <= 0.0f || height <= 0.0f)
        return false;

    Entity entity = Entity::import(decal);
    if (entity.isNull())
        return false;

    RenderableManager& rm = ctx->engine->getRenderableManager();

    if (!rm.hasComponent(entity))
        return false;

    auto instance = rm.getInstance(entity);

    rm.setCastShadows(instance, castShadows);
    rm.setReceiveShadows(instance, receiveShadows);
    rm.setLayerMask(instance, 0x1, culling ? 0x1 : 0x0);

    rm.setAxisAlignedBoundingBox(
        instance,
        {
            {-width * 0.5f, -height * 0.5f, -0.01f},
            { width * 0.5f,  height * 0.5f,  0.01f}
        }
    );

    return true;
}

KINE_API void Kine_Filament_SetColorLight(KineFilamentContext* ctx, int light, float r, float g, float b) {
    if (!ctx || !ctx->engine) return;
    auto& lm = ctx->engine->getLightManager();
    auto instance = lm.getInstance(Entity::import(light));
    if (!instance.isValid()) return;
    lm.setColor(instance, {r, g, b});
}


KINE_API void Kine_Filament_SetIntensityLight(KineFilamentContext* ctx, int light, float intensity) {
    if (!ctx || !ctx->engine) return;
    auto& lm = ctx->engine->getLightManager();
    auto instance = lm.getInstance(Entity::import(light));
    if (!instance.isValid()) return;
    lm.setIntensity(instance, intensity);
}

KINE_API void Kine_Filament_SetFalloffLight(KineFilamentContext* ctx, int light, float falloff) {
    if (!ctx || !ctx->engine) return;
    auto& lm = ctx->engine->getLightManager();
    auto instance = lm.getInstance(Entity::import(light));
    if (!instance.isValid()) return;
    lm.setFalloff(instance, falloff);
}

KINE_API void Kine_Filament_SetPositionLight(KineFilamentContext* ctx, int light, float x, float y, float z) {
    if (!ctx || !ctx->engine) return;
    auto& lm = ctx->engine->getLightManager();
    auto instance = lm.getInstance(Entity::import(light));
    if (!instance.isValid()) return;
    lm.setPosition(instance, {x, y, z});
}

// camera functions

KINE_API void Kine_Filament_SetCameraPerspective(
    KineFilamentContext* ctx,
    double fovYDegrees, double aspect, double nearPlane, double farPlane)
{
    if (!ctx || !ctx->camera) return;
    ctx->camera->setProjection(fovYDegrees, aspect, nearPlane, farPlane);
}

// ---------------------------------------------------------------------------
// Mesh system
//   shape: 1 = cube, 2 = sphere, 3 = pyramid,
//          10 = move gizmo, 11 = rotate gizmo, 12 = scale gizmo
// ---------------------------------------------------------------------------

// kine_filament_shim.cpp
KineFilamentMesh* Kine_Filament_CreateCustomMesh(
    KineFilamentContext* ctx,
    const float* vertexData,
    int vertexCount,
    const uint16_t* indices,
    int indexCount)
{
    if (!ctx || !ctx->engine || !vertexData || vertexCount <= 0 || !indices || indexCount <= 0)
        return nullptr;
    if (vertexCount > 65535) {
        fprintf(stderr, "[Kine] CreateCustomMesh: %d verts exceeds uint16 index range\n", vertexCount);
        return nullptr;
    }
    auto* m = new KineMesh();
    m->vertices.resize(vertexCount);
    memcpy(m->vertices.data(), vertexData, vertexCount * sizeof(KineVertex));
    m->indices.assign(indices, indices + indexCount);
    m->indexCount = (uint32_t)indexCount;
    uploadMesh(m, ctx->engine); // computes tangents via SurfaceOrientation automatically
    return (KineFilamentMesh*)m;
}

bool Kine_Filament_UpdateCustomMesh(
    KineFilamentContext* ctx,
    KineFilamentMesh* mesh,
    const float* vertexData,
    int vertexCount)
{
    auto* m = (KineMesh*)mesh;
    if (!ctx || !ctx->engine || !m || !m->vb || !vertexData || vertexCount <= 0 ||
        (size_t)vertexCount != m->vertices.size()) {
        return false;
    }

    memcpy(m->vertices.data(), vertexData, m->vertices.size() * sizeof(KineVertex));

    math::float3 boundsMin{
        std::numeric_limits<float>::max(),
        std::numeric_limits<float>::max(),
        std::numeric_limits<float>::max()
    };
    math::float3 boundsMax{
        std::numeric_limits<float>::lowest(),
        std::numeric_limits<float>::lowest(),
        std::numeric_limits<float>::lowest()
    };
    std::vector<math::float3> normals(m->vertices.size());
    for (size_t i = 0; i < m->vertices.size(); ++i) {
        const KineVertex& vertex = m->vertices[i];
        boundsMin.x = std::min(boundsMin.x, vertex.px);
        boundsMin.y = std::min(boundsMin.y, vertex.py);
        boundsMin.z = std::min(boundsMin.z, vertex.pz);
        boundsMax.x = std::max(boundsMax.x, vertex.px);
        boundsMax.y = std::max(boundsMax.y, vertex.py);
        boundsMax.z = std::max(boundsMax.z, vertex.pz);
        normals[i] = {vertex.nx, vertex.ny, vertex.nz};
    }
    m->localBounds.set(boundsMin, boundsMax);

    std::vector<math::short4> quats(m->vertices.size());
    auto orientation = SurfaceOrientation::Builder()
        .vertexCount((uint32_t)m->vertices.size())
        .normals(normals.data())
        .build();
    orientation->getQuats(quats.data(), (uint32_t)m->vertices.size());
    delete orientation;

    const size_t vertexBytes = m->vertices.size() * sizeof(KineVertex);
    void* vertexCopy = malloc(vertexBytes);
    memcpy(vertexCopy, m->vertices.data(), vertexBytes);
    m->vb->setBufferAt(*ctx->engine, 0,
        VertexBuffer::BufferDescriptor(vertexCopy, vertexBytes,
            [](void* buffer, size_t, void*) { free(buffer); }, nullptr));

    const size_t tangentBytes = quats.size() * sizeof(math::short4);
    void* tangentCopy = malloc(tangentBytes);
    memcpy(tangentCopy, quats.data(), tangentBytes);
    m->vb->setBufferAt(*ctx->engine, 1,
        VertexBuffer::BufferDescriptor(tangentCopy, tangentBytes,
            [](void* buffer, size_t, void*) { free(buffer); }, nullptr));

    return true;
}

KINE_API KineFilamentGizmo* Kine_Filament_CreateGizmo(KineFilamentContext* ctx, int gizmoType)
{
    if (!ctx || !ctx->engine) return nullptr;

    auto* gizmo = new KineFilamentGizmo();
    gizmo->type = gizmoType;

    switch (gizmoType) {
        case KINE_GIZMO_ROTATE: gizmo->axes = buildRotateGizmoAxes(); break;
        case KINE_GIZMO_SCALE:  gizmo->axes = buildScaleGizmoAxes(); break;
        default:                gizmo->axes = buildMoveGizmoAxes(); break;
    }

    KineMesh* meshes[4] = {gizmo->axes.x, gizmo->axes.y, gizmo->axes.z, gizmo->axes.center};
    for (KineMesh* mesh : meshes) {
        if (mesh) uploadMesh(mesh, ctx->engine);
    }

    return gizmo;
}

KINE_API void Kine_Filament_DestroyGizmo(KineFilamentContext* ctx, KineFilamentGizmo* gizmo)
{
    if (!ctx || !ctx->engine || !gizmo) return;

    KineMesh* meshes[4] = {gizmo->axes.x, gizmo->axes.y, gizmo->axes.z, gizmo->axes.center};
    for (KineMesh* mesh : meshes) {
        if (!mesh) continue;
        kine_invalidate_batches(ctx, mesh, nullptr);
        if (mesh->vb) ctx->engine->destroy(mesh->vb);
        if (mesh->ib) ctx->engine->destroy(mesh->ib);
        delete mesh;
    }

    delete gizmo;
}

KINE_API KineFilamentMesh* Kine_Filament_CreateMesh(KineFilamentContext* ctx, int shape)
{
    if (!ctx || !ctx->engine) return nullptr;

    KineMesh* m = nullptr;
    switch (shape) {
        case 10: m = buildMoveGizmo(); break;
        case 11: m = buildRotateGizmo(); break;
        case 12: m = buildScaleGizmo(); break;
        case 2:  m = buildSphere(); break;
        case 3:  m = buildPyramid(); break;
        default: m = buildCube();   break; // 1 = cube (default)
    }
    uploadMesh(m, ctx->engine);
    return (KineFilamentMesh*)m;
}

KINE_API KineFilamentMesh* Kine_Filament_CreateMeshFromPath(KineFilamentContext* ctx, const char* path)
{
    if (!ctx || !ctx->engine || !path || path[0] == '\0') return nullptr;

#if KINE_WITH_ASSIMP
    KineMesh* m = loadMeshWithAssimp(path);
    if (!m) return nullptr;
    uploadMesh(m, ctx->engine);
    return (KineFilamentMesh*)m;
#else
    fprintf(stderr, "[Kine] CreateMeshFromPath requires KINE_WITH_ASSIMP=ON and assimp::assimp at build time\n");
    return nullptr;
#endif
}

KINE_API KineFilamentTex* Kine_Filament_CreateTexFromPixels(
    KineFilamentContext* ctx,
    int width, int height,
    int rowBytes,
    const void* pixelsRGBA8)
{
    auto* th = new KineTexHandle();
    th->tex = ctx ? kine_create_uploaded_rgba_texture(ctx->engine, width, height, rowBytes, pixelsRGBA8) : nullptr;
    if (!th->tex) {
        delete th;
        return nullptr;
    }

    return (KineFilamentTex*)th;
}

KINE_API KineFilamentTex* Kine_Filament_CreatePbrTexFromPixels(
    KineFilamentContext* ctx,
    int width, int height,
    int albedoRowBytes,
    const void* albedoRGBA8,
    int normalWidth, int normalHeight,
    int normalRowBytes,
    const void* normalRGBA8,
    int ormWidth, int ormHeight,
    int ormRowBytes,
    const void* ormRGBA8)
{
    if (!ctx || !ctx->engine) return nullptr;

    auto* th = new KineTexHandle();
    th->tex = kine_create_uploaded_rgba_texture(ctx->engine, width, height, albedoRowBytes, albedoRGBA8);
    if (!th->tex) {
        delete th;
        return nullptr;
    }

    th->normalTex = kine_create_uploaded_rgba_texture(
        ctx->engine, normalWidth, normalHeight, normalRowBytes, normalRGBA8);
    th->ormTex = kine_create_uploaded_rgba_texture(
        ctx->engine, ormWidth, ormHeight, ormRowBytes, ormRGBA8);

    return (KineFilamentTex*)th;
}

KINE_API void Kine_Filament_DestroyMesh(KineFilamentContext* ctx, KineFilamentMesh* mesh)
{
    if (!ctx || !mesh) return;
    auto* m = (KineMesh*)mesh;
    kine_invalidate_batches(ctx, m, nullptr);
    if (m->vb) ctx->engine->destroy(m->vb);
    if (m->ib) ctx->engine->destroy(m->ib);
    delete m;
}

// ---------------------------------------------------------------------------
// Texture system -- wraps an existing OpenGL texture handle.
// Input layout: { uint id, int w, int h, int mipmaps, int format }
// ---------------------------------------------------------------------------

KINE_API KineFilamentTex* Kine_Filament_CreateTex(KineFilamentContext* ctx, const KineGLTextureInfo* texture)
{
    if (!ctx || !texture) return nullptr;

    if (texture->id == 0) return nullptr;

    auto* th = new KineTexHandle();

    th->tex = Texture::Builder()
        .width((uint32_t)texture->width)
        .height((uint32_t)texture->height)
        .levels(1)
        .usage(Texture::Usage::SAMPLEABLE)
        .format(Texture::InternalFormat::RGBA8)
        .import(texture->id)
        .build(*ctx->engine);

    if (!th->tex) {
        delete th;
        return nullptr;
    }

    return (KineFilamentTex*)th;
}

KINE_API void Kine_Filament_DestroyTex(KineFilamentContext* ctx, KineFilamentTex* tex)
{
    if (!ctx || !tex) return;
    auto* th = (KineTexHandle*)tex;
    kine_invalidate_batches(ctx, nullptr, th);
    if (th->tex) ctx->engine->destroy(th->tex);
    if (th->normalTex) ctx->engine->destroy(th->normalTex);
    if (th->ormTex) ctx->engine->destroy(th->ormTex);
    delete th;
}

// ---------------------------------------------------------------------------
// DrawMesh -- queues a mesh instance to be drawn this frame.
//
//   ctx          : context handle
//   mesh         : mesh from Kine_Filament_CreateMesh
//   r,g,b        : base color [0..1]
//   tex          : optional texture handle (may be NULL)
//   transparency : [0..1], 0 = fully opaque, 1 = fully transparent
//   mat4         : column-major float[16] world transform
//
// Calls that share the same mesh, materialKind, color/params, and
// shadow/culling flags are automatically batched together and issued as a
// single GPU-instanced draw call from Kine_Filament_RenderFrame -- see the
// "Automatic instanced batching" comment near the top of this file.
// ---------------------------------------------------------------------------

static void kine_queue_mesh(
    KineFilamentContext* ctx,
    KineFilamentMesh* mesh,
    int materialKind,
    float r, float g, float b,
    float param1,
    float param2,
    float param3,
    float transmission,
    const float* mat4,
    bool castShadow,
    bool receiveShadow,
    bool culling,
    KineFilamentTex* tex,
    uint64_t streamId = 0,
    KineBatchKey* outKey = nullptr)
{
    if (!ctx || !mesh || !mat4) return;

    KineBatchKey key;
    key.mesh          = (KineMesh*)mesh;
    key.streamId      = streamId;
    key.materialKind  = materialKind;
    key.r = r; key.g = g; key.b = b;
    key.param1 = param1; key.param2 = param2; key.param3 = param3;
    key.transmission  = transmission;
    key.castShadow    = castShadow;
    key.receiveShadow = receiveShadow;
    key.culling       = culling;
    key.texture       = (KineTexHandle*)tex;
    if (outKey) {
        *outKey = key;
    }

    KinePendingBatch& pending = ctx->pendingBatches[key];
    if (pending.lastQueuedFrame != ctx->batchFrame) {
        pending.transforms.clear();
        pending.lastQueuedFrame = ctx->batchFrame;
    }
    pending.transforms.emplace_back(
        math::float4{mat4[0], mat4[4], mat4[8],  mat4[12]},
        math::float4{mat4[1], mat4[5], mat4[9],  mat4[13]},
        math::float4{mat4[2], mat4[6], mat4[10], mat4[14]},
        math::float4{mat4[3], mat4[7], mat4[11], mat4[15]}
    );
}

KINE_API void Kine_Filament_DrawMeshEx(
    KineFilamentContext* ctx,
    KineFilamentMesh*    mesh,
    int                  materialKind,
    float                r, float g, float b,
    float                param1, // roughness (glass) / intensity (neon)
    float                param2, // ior (glass) / unused (neon)
    float                param3, // thickness (glass) / unused (neon)
    float                transmission, // glass only
    float*               mat4,
    bool                 castshadow,
    bool                 receiveShadow,
    bool                 culling,
    KineFilamentTex*     tex)
{
    kine_queue_mesh(
        ctx, mesh, materialKind,
        r, g, b,
        param1, param2, param3, transmission,
        mat4,
        castshadow, receiveShadow, culling,
        tex);
}

KINE_API void Kine_Filament_DrawMeshList(
    KineFilamentContext* ctx,
    const KineFilamentDrawItem* items,
    uint32_t itemCount)
{
    static_assert(sizeof(KineFilamentDrawItem) == 120,
        "KineFilamentDrawItem ABI must match filament/structs.luau");
    static_assert(offsetof(KineFilamentDrawItem, transform) == 16 &&
                  offsetof(KineFilamentDrawItem, materialKind) == 108 &&
                  offsetof(KineFilamentDrawItem, flags) == 112,
        "KineFilamentDrawItem field offsets must match filament/structs.luau");

    if (!ctx || !items || itemCount == 0) return;

    for (uint32_t i = 0; i < itemCount; ++i) {
        const KineFilamentDrawItem& item = items[i];
        kine_queue_mesh(
            ctx, item.mesh, item.materialKind,
            item.r, item.g, item.b,
            item.param1, item.param2, item.param3, item.transmission,
            item.transform,
            (item.flags & KINE_FILAMENT_DRAW_CAST_SHADOWS) != 0,
            (item.flags & KINE_FILAMENT_DRAW_RECEIVE_SHADOWS) != 0,
            (item.flags & KINE_FILAMENT_DRAW_CULLING) != 0,
            item.tex);
    }

}

KINE_API void Kine_Filament_DrawMeshListVersioned(
    KineFilamentContext* ctx,
    const KineFilamentDrawItem* items,
    uint32_t itemCount,
    uint64_t streamId,
    uint64_t version)
{
    if (!ctx || streamId == 0) return;

    KineRetainedListState& state = ctx->retainedLists[streamId];
    if (state.initialized && state.version == version) {
        for (const KineBatchKey& key : state.keys) {
            auto built = ctx->builtBatches.find(key);
            if (built != ctx->builtBatches.end()) {
                built->second.lastUsedFrame = ctx->batchFrame;
            }
        }
        return;
    }

    state.initialized = true;
    state.version = version;
    state.keys.clear();
    if (!items || itemCount == 0) return;

    std::unordered_set<KineBatchKey, KineBatchKeyHash> uniqueKeys;
    for (uint32_t i = 0; i < itemCount; ++i) {
        const KineFilamentDrawItem& item = items[i];
        KineBatchKey key;
        kine_queue_mesh(
            ctx, item.mesh, item.materialKind,
            item.r, item.g, item.b,
            item.param1, item.param2, item.param3, item.transmission,
            item.transform,
            (item.flags & KINE_FILAMENT_DRAW_CAST_SHADOWS) != 0,
            (item.flags & KINE_FILAMENT_DRAW_RECEIVE_SHADOWS) != 0,
            (item.flags & KINE_FILAMENT_DRAW_CULLING) != 0,
            item.tex,
            streamId,
            &key);
        if (uniqueKeys.insert(key).second) {
            state.keys.push_back(key);
        }
    }
}

KINE_API void Kine_Filament_DrawMeshOutline(
    KineFilamentContext* ctx,
    KineFilamentMesh*    mesh,
    float                r, float g, float b,
    float                thickness,
    float*               mat4)
{
    if (!ctx || !mesh || !mat4 || thickness <= 0.0f) return;

    Kine_Filament_DrawMeshEx(
        ctx, mesh, KINE_MAT_OUTLINE,
        r, g, b,
        thickness, 0.0f, 0.0f,
        0.0f,
        mat4,
        false, false, false,
        nullptr);
}

static void kine_gizmo_axis_color(int axis, float& r, float& g, float& b)
{
    switch (axis) {
        case KINE_GIZMO_AXIS_X:      r = 0.90f; g = 0.15f; b = 0.15f; break;
        case KINE_GIZMO_AXIS_Y:      r = 0.20f; g = 0.85f; b = 0.20f; break;
        case KINE_GIZMO_AXIS_Z:      r = 0.20f; g = 0.45f; b = 0.95f; break;
        case KINE_GIZMO_AXIS_CENTER: r = 0.85f; g = 0.85f; b = 0.85f; break;
        default:                     r = 1.00f; g = 1.00f; b = 1.00f; break;
    }
}

KINE_API void Kine_Filament_DrawGizmo(
    KineFilamentContext* ctx,
    KineFilamentGizmo*   gizmo,
    float*               mat4,
    int                  hoveredAxis,
    int                  selectedAxis)
{
    if (!ctx || !gizmo || !mat4) return;

    struct AxisEntry { int id; KineMesh* mesh; };
    AxisEntry entries[4] = {
        {KINE_GIZMO_AXIS_X,      gizmo->axes.x},
        {KINE_GIZMO_AXIS_Y,      gizmo->axes.y},
        {KINE_GIZMO_AXIS_Z,      gizmo->axes.z},
        {KINE_GIZMO_AXIS_CENTER, gizmo->axes.center},
    };

    for (const AxisEntry& entry : entries) {
        if (!entry.mesh) continue;

        float r = 1.0f, g = 1.0f, b = 1.0f;
        kine_gizmo_axis_color(entry.id, r, g, b);

        const bool isActive = (entry.id == hoveredAxis || entry.id == selectedAxis);
        const bool somethingActive = (hoveredAxis != KINE_GIZMO_AXIS_NONE ||
                                      selectedAxis != KINE_GIZMO_AXIS_NONE);
        if (somethingActive && !isActive) {
            r *= 0.55f;
            g *= 0.55f;
            b *= 0.55f;
        }

        Kine_Filament_DrawMeshEx(
            ctx, (KineFilamentMesh*)entry.mesh, KINE_MAT_DEFAULT,
            r, g, b,
            1.0f, 0.0f, 1.0f,
            0.0f,
            mat4,
            false, false, false,
            nullptr);

        const bool isSelected = (entry.id == selectedAxis);
        const bool isHovered = (entry.id == hoveredAxis);
        if (isSelected || isHovered) {
            const float thickness = isSelected ? 0.03f : 0.018f;
            Kine_Filament_DrawMeshOutline(
                ctx, (KineFilamentMesh*)entry.mesh,
                1.0f, 0.85f, 0.15f,
                thickness,
                mat4);
        }
    }
}

} // extern "C"

extern "C" {

// ---------------------------------------------------------------------------
// Pixel readback -- reads Filament's rendered frame into a CPU buffer.
// Call after Kine_Filament_RenderFrame. outPixels must be width*height*4 bytes.
// ---------------------------------------------------------------------------
KINE_API void Kine_Filament_ReadPixels(KineFilamentContext* ctx, void* outPixels)
{
#if KINE_FILAMENT_USE_VULKAN
#if KINE_FILAMENT_ENABLE_VULKAN_READBACK
    if (!ctx || !outPixels || ctx->readbackPixels.empty()) return;
    size_t bytes = (size_t)ctx->width * (size_t)ctx->height * 4;
    if (ctx->readbackPixels.size() < bytes) return;
    memcpy(outPixels, ctx->readbackPixels.data(), bytes);
#else
    (void)ctx;
    (void)outPixels;
    static bool warned = false;
    if (!warned) {
        fprintf(stderr, "[Kine] Filament Vulkan readback is disabled. Build with KINE_FILAMENT_VULKAN_READBACK=ON for debugging only.\n");
        warned = true;
    }
#endif
#else
    if (!ctx || !outPixels || ctx->readFboId == 0) return;
    if (!kine_glBindFramebuffer) return;

    kine_glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)ctx->readFboId);
    glReadPixels(0, 0, (GLsizei)ctx->width, (GLsizei)ctx->height,
                 GL_RGBA, GL_UNSIGNED_BYTE, outPixels);
    kine_glBindFramebuffer(GL_FRAMEBUFFER, 0);
#endif
}

KINE_API int Kine_Filament_GetWidth(KineFilamentContext* ctx)
{
    return ctx ? ctx->width : 0;
}

KINE_API int Kine_Filament_GetHeight(KineFilamentContext* ctx)
{
    return ctx ? ctx->height : 0;
}

} // extern "C" (ReadPixels block)
