#include "kine_vulkan_compositor.h"

#include "kine_skia.h"

#include <SDL3/SDL_vulkan.h>

#include <vulkan/vulkan.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

struct KineVulkanCompositor {
    PFN_vkGetInstanceProcAddr getInstanceProcAddr = nullptr;
    PFN_vkGetDeviceProcAddr getDeviceProcAddr = nullptr;

    VkInstance instance = VK_NULL_HANDLE;
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphicsQueue = VK_NULL_HANDLE;
    uint32_t graphicsQueueFamilyIndex = UINT32_MAX;
    uint32_t graphicsQueueCount = 0;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat swapchainFormat = VK_FORMAT_UNDEFINED;
    VkImageUsageFlags swapchainUsage = 0;
    VkExtent2D swapchainExtent = {};
    std::vector<VkImage> swapchainImages;
    std::vector<VkImageView> swapchainImageViews;
    std::vector<VkImageLayout> swapchainImageLayouts;
    VkImage depthImage = VK_NULL_HANDLE;
    VkDeviceMemory depthImageMemory = VK_NULL_HANDLE;
    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    VkFence acquireFence = VK_NULL_HANDLE;
    VkSemaphore filamentImageReadySemaphore = VK_NULL_HANDLE;
    uint32_t currentImageIndex = UINT32_MAX;
    KineSkiaSurface* currentSkiaSurface = nullptr;
    bool frameActive = false;
    bool filamentPrepared = false;
    bool filamentPresented = false;
    VkSemaphore filamentFinishedSemaphore = VK_NULL_HANDLE;
    std::mutex filamentMutex;
    std::condition_variable filamentCondition;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t apiVersion = VK_API_VERSION_1_0;

    KineSkiaVulkanContext* skiaContext = nullptr;
    std::string lastError;
    bool ownsInstance = true;
    bool ownsDevice = true;
};

static bool kine_vk_has_extension(
    const std::vector<const char*>& extensions,
    const char* name)
{
    return name && std::any_of(
        extensions.begin(),
        extensions.end(),
        [name](const char* extension) {
            return extension && std::strcmp(extension, name) == 0;
        });
}

static bool kine_vk_instance_extension_available(
    PFN_vkGetInstanceProcAddr getInstanceProcAddr,
    const char* name)
{
    if (!getInstanceProcAddr || !name) {
        return false;
    }
    auto enumerate = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(
        getInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
    if (!enumerate) {
        return false;
    }

    uint32_t count = 0;
    if (enumerate(nullptr, &count, nullptr) != VK_SUCCESS || count == 0) {
        return false;
    }
    std::vector<VkExtensionProperties> properties(count);
    if (enumerate(nullptr, &count, properties.data()) != VK_SUCCESS) {
        return false;
    }
    return std::any_of(properties.begin(), properties.end(), [name](const auto& property) {
        return std::strcmp(property.extensionName, name) == 0;
    });
}

static void kine_vk_set_error(KineVulkanCompositor* compositor, const char* message)
{
    if (compositor) {
        compositor->lastError = message ? message : "";
    }
}

template<typename T>
static T kine_vk_instance_proc(KineVulkanCompositor* compositor, const char* name)
{
    if (!compositor || !compositor->getInstanceProcAddr || !name) {
        return nullptr;
    }
    return reinterpret_cast<T>(compositor->getInstanceProcAddr(compositor->instance, name));
}

template<typename T>
static T kine_vk_device_proc(KineVulkanCompositor* compositor, const char* name)
{
    if (!compositor || !name) {
        return nullptr;
    }

    if (compositor->getDeviceProcAddr && compositor->device) {
        if (auto proc = compositor->getDeviceProcAddr(compositor->device, name)) {
            return reinterpret_cast<T>(proc);
        }
    }

    if (compositor->getInstanceProcAddr && compositor->instance) {
        auto proc = compositor->getInstanceProcAddr(compositor->instance, name);
        return reinterpret_cast<T>(proc);
    }

    return nullptr;
}

static bool kine_vk_create_instance(KineVulkanCompositor* compositor)
{
    compositor->getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
        SDL_Vulkan_GetVkGetInstanceProcAddr());
    if (!compositor->getInstanceProcAddr) {
        kine_vk_set_error(compositor, "SDL_Vulkan_GetVkGetInstanceProcAddr failed");
        return false;
    }

    auto vkCreateInstance = reinterpret_cast<PFN_vkCreateInstance>(
        compositor->getInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance"));
    if (!vkCreateInstance) {
        kine_vk_set_error(compositor, "vkCreateInstance unavailable");
        return false;
    }

    uint32_t extensionCount = 0;
    char const* const* sdlExtensions = SDL_Vulkan_GetInstanceExtensions(&extensionCount);
    if (!sdlExtensions || extensionCount == 0) {
        kine_vk_set_error(compositor, "SDL_Vulkan_GetInstanceExtensions failed");
        return false;
    }

    uint32_t loaderVersion = VK_API_VERSION_1_0;
    auto enumerateVersion = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(
        compositor->getInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceVersion"));
    if (enumerateVersion) {
        enumerateVersion(&loaderVersion);
    }
    compositor->apiVersion = std::min(loaderVersion, VK_API_VERSION_1_1);

    std::vector<const char*> extensions(sdlExtensions, sdlExtensions + extensionCount);
    constexpr const char* portabilityEnumeration = "VK_KHR_portability_enumeration";
    const bool hasPortabilityEnumeration = kine_vk_instance_extension_available(
        compositor->getInstanceProcAddr,
        portabilityEnumeration);
    if (hasPortabilityEnumeration &&
        !kine_vk_has_extension(extensions, portabilityEnumeration)) {
        extensions.push_back(portabilityEnumeration);
    }

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Kinemium";
    appInfo.applicationVersion = VK_MAKE_VERSION(0, 1, 0);
    appInfo.pEngineName = "Kinemium";
    appInfo.engineVersion = VK_MAKE_VERSION(0, 1, 0);
    appInfo.apiVersion = compositor->apiVersion;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();
#if defined(VK_KHR_portability_enumeration)
    if (hasPortabilityEnumeration) {
        createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }
#endif

    VkResult result = vkCreateInstance(&createInfo, nullptr, &compositor->instance);
    if (result != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateInstance failed");
        return false;
    }

    return true;
}

static bool kine_vk_create_surface(KineVulkanCompositor* compositor, void* sdlWindow)
{
    if (!SDL_Vulkan_CreateSurface(
            reinterpret_cast<SDL_Window*>(sdlWindow),
            compositor->instance,
            nullptr,
            &compositor->surface)) {
        kine_vk_set_error(compositor, "SDL_Vulkan_CreateSurface failed");
        return false;
    }
    return true;
}

static bool kine_vk_pick_device(KineVulkanCompositor* compositor)
{
    auto vkEnumeratePhysicalDevices = kine_vk_instance_proc<PFN_vkEnumeratePhysicalDevices>(
        compositor, "vkEnumeratePhysicalDevices");
    auto vkGetPhysicalDeviceQueueFamilyProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(
            compositor, "vkGetPhysicalDeviceQueueFamilyProperties");
    auto vkGetPhysicalDeviceSurfaceSupportKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceSupportKHR");
    if (!vkEnumeratePhysicalDevices || !vkGetPhysicalDeviceQueueFamilyProperties ||
        !vkGetPhysicalDeviceSurfaceSupportKHR) {
        kine_vk_set_error(compositor, "required physical-device Vulkan procs unavailable");
        return false;
    }

    uint32_t deviceCount = 0;
    if (vkEnumeratePhysicalDevices(compositor->instance, &deviceCount, nullptr) != VK_SUCCESS ||
        deviceCount == 0) {
        kine_vk_set_error(compositor, "no Vulkan physical devices found");
        return false;
    }

    std::vector<VkPhysicalDevice> devices(deviceCount);
    if (vkEnumeratePhysicalDevices(compositor->instance, &deviceCount, devices.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumeratePhysicalDevices failed");
        return false;
    }

    for (VkPhysicalDevice device : devices) {
        uint32_t queueFamilyCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, nullptr);
        if (queueFamilyCount == 0) {
            continue;
        }

        std::vector<VkQueueFamilyProperties> families(queueFamilyCount);
        vkGetPhysicalDeviceQueueFamilyProperties(device, &queueFamilyCount, families.data());

        for (uint32_t i = 0; i < queueFamilyCount; ++i) {
            VkBool32 presentSupported = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(device, i, compositor->surface, &presentSupported);
            if ((families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && presentSupported) {
                compositor->physicalDevice = device;
                compositor->graphicsQueueFamilyIndex = i;
                compositor->graphicsQueueCount = families[i].queueCount;
                return true;
            }
        }
    }

    kine_vk_set_error(compositor, "no graphics+present Vulkan queue found");
    return false;
}

static bool kine_vk_validate_present_queue(KineVulkanCompositor* compositor)
{
    auto vkGetPhysicalDeviceSurfaceSupportKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceSupportKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceSupportKHR");
    if (!vkGetPhysicalDeviceSurfaceSupportKHR) {
        kine_vk_set_error(compositor, "vkGetPhysicalDeviceSurfaceSupportKHR unavailable");
        return false;
    }

    VkBool32 presentSupported = VK_FALSE;
    if (vkGetPhysicalDeviceSurfaceSupportKHR(
            compositor->physicalDevice,
            compositor->graphicsQueueFamilyIndex,
            compositor->surface,
            &presentSupported) != VK_SUCCESS || !presentSupported) {
        kine_vk_set_error(compositor, "external Vulkan graphics queue cannot present to this SDL surface");
        return false;
    }
    return true;
}

static bool kine_vk_create_device(KineVulkanCompositor* compositor)
{
    auto vkCreateDevice = kine_vk_instance_proc<PFN_vkCreateDevice>(compositor, "vkCreateDevice");
    auto vkEnumerateDeviceExtensionProperties =
        kine_vk_instance_proc<PFN_vkEnumerateDeviceExtensionProperties>(
            compositor, "vkEnumerateDeviceExtensionProperties");
    if (!vkCreateDevice || !vkEnumerateDeviceExtensionProperties) {
        kine_vk_set_error(compositor, "required device-creation Vulkan procs unavailable");
        return false;
    }

    float priorities[] = { 1.0f, 1.0f };
    VkDeviceQueueCreateInfo queueInfo{};
    queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueInfo.queueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    queueInfo.queueCount = std::min<uint32_t>(compositor->graphicsQueueCount, 2);
    if (queueInfo.queueCount == 0) {
        queueInfo.queueCount = 1;
    }
    queueInfo.pQueuePriorities = priorities;

    uint32_t availableExtensionCount = 0;
    if (vkEnumerateDeviceExtensionProperties(
            compositor->physicalDevice,
            nullptr,
            &availableExtensionCount,
            nullptr) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumerateDeviceExtensionProperties failed");
        return false;
    }
    std::vector<VkExtensionProperties> availableExtensions(availableExtensionCount);
    if (availableExtensionCount > 0 && vkEnumerateDeviceExtensionProperties(
            compositor->physicalDevice,
            nullptr,
            &availableExtensionCount,
            availableExtensions.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEnumerateDeviceExtensionProperties list failed");
        return false;
    }
    auto deviceExtensionAvailable = [&availableExtensions](const char* name) {
        return std::any_of(
            availableExtensions.begin(),
            availableExtensions.end(),
            [name](const auto& extension) {
                return std::strcmp(extension.extensionName, name) == 0;
            });
    };
    if (!deviceExtensionAvailable(VK_KHR_SWAPCHAIN_EXTENSION_NAME)) {
        kine_vk_set_error(compositor, "VK_KHR_swapchain is unavailable on the selected device");
        return false;
    }

    std::vector<const char*> extensions{VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    constexpr const char* portabilitySubset = "VK_KHR_portability_subset";
    if (deviceExtensionAvailable(portabilitySubset)) {
        extensions.push_back(portabilitySubset);
    }

    VkDeviceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pQueueCreateInfos = &queueInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(extensions.size());
    createInfo.ppEnabledExtensionNames = extensions.data();

    VkResult result = vkCreateDevice(compositor->physicalDevice, &createInfo, nullptr, &compositor->device);
    if (result != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateDevice failed");
        return false;
    }

    compositor->getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        compositor->getInstanceProcAddr(compositor->instance, "vkGetDeviceProcAddr"));
    if (!compositor->getDeviceProcAddr) {
        kine_vk_set_error(compositor, "vkGetDeviceProcAddr unavailable");
        return false;
    }

    auto vkGetDeviceQueue = kine_vk_device_proc<PFN_vkGetDeviceQueue>(compositor, "vkGetDeviceQueue");
    if (!vkGetDeviceQueue) {
        kine_vk_set_error(compositor, "vkGetDeviceQueue unavailable");
        return false;
    }

    vkGetDeviceQueue(compositor->device, compositor->graphicsQueueFamilyIndex, 0, &compositor->graphicsQueue);
    if (!compositor->graphicsQueue) {
        kine_vk_set_error(compositor, "vkGetDeviceQueue returned null");
        return false;
    }

    return true;
}

static bool kine_vk_create_frame_resources(KineVulkanCompositor* compositor)
{
    auto vkCreateCommandPool = kine_vk_device_proc<PFN_vkCreateCommandPool>(
        compositor, "vkCreateCommandPool");
    auto vkAllocateCommandBuffers = kine_vk_device_proc<PFN_vkAllocateCommandBuffers>(
        compositor, "vkAllocateCommandBuffers");
    auto vkCreateFence = kine_vk_device_proc<PFN_vkCreateFence>(
        compositor, "vkCreateFence");
    auto vkCreateSemaphore = kine_vk_device_proc<PFN_vkCreateSemaphore>(
        compositor, "vkCreateSemaphore");
    if (!vkCreateCommandPool || !vkAllocateCommandBuffers || !vkCreateFence || !vkCreateSemaphore) {
        kine_vk_set_error(compositor, "required frame-resource Vulkan procs unavailable");
        return false;
    }

    VkCommandPoolCreateInfo poolInfo{};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    if (vkCreateCommandPool(compositor->device, &poolInfo, nullptr, &compositor->commandPool) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateCommandPool failed");
        return false;
    }

    VkCommandBufferAllocateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    bufferInfo.commandPool = compositor->commandPool;
    bufferInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    bufferInfo.commandBufferCount = 1;
    if (vkAllocateCommandBuffers(compositor->device, &bufferInfo, &compositor->commandBuffer) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkAllocateCommandBuffers failed");
        return false;
    }

    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    if (vkCreateFence(compositor->device, &fenceInfo, nullptr, &compositor->acquireFence) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateFence failed");
        return false;
    }

    VkSemaphoreCreateInfo semaphoreInfo{};
    semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
    if (vkCreateSemaphore(
            compositor->device,
            &semaphoreInfo,
            nullptr,
            &compositor->filamentImageReadySemaphore) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateSemaphore failed");
        return false;
    }

    return true;
}

static uint32_t kine_vk_find_memory_type(
    KineVulkanCompositor* compositor,
    uint32_t typeFilter,
    VkMemoryPropertyFlags properties)
{
    auto vkGetPhysicalDeviceMemoryProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceMemoryProperties>(
            compositor, "vkGetPhysicalDeviceMemoryProperties");
    if (!vkGetPhysicalDeviceMemoryProperties) {
        return UINT32_MAX;
    }

    VkPhysicalDeviceMemoryProperties memoryProperties{};
    vkGetPhysicalDeviceMemoryProperties(compositor->physicalDevice, &memoryProperties);
    for (uint32_t i = 0; i < memoryProperties.memoryTypeCount; ++i) {
        if ((typeFilter & (1u << i)) &&
            (memoryProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return UINT32_MAX;
}

static bool kine_vk_choose_depth_format(KineVulkanCompositor* compositor, VkFormat* outFormat)
{
    auto vkGetPhysicalDeviceFormatProperties =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceFormatProperties>(
            compositor, "vkGetPhysicalDeviceFormatProperties");
    if (!vkGetPhysicalDeviceFormatProperties || !outFormat) {
        return false;
    }

    const VkFormat candidates[] = {
        VK_FORMAT_D32_SFLOAT,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D16_UNORM,
    };
    for (VkFormat format : candidates) {
        VkFormatProperties properties{};
        vkGetPhysicalDeviceFormatProperties(compositor->physicalDevice, format, &properties);
        if (properties.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT) {
            *outFormat = format;
            return true;
        }
    }
    return false;
}

static bool kine_vk_create_depth_attachment(KineVulkanCompositor* compositor)
{
    auto vkCreateImage = kine_vk_device_proc<PFN_vkCreateImage>(
        compositor, "vkCreateImage");
    auto vkGetImageMemoryRequirements = kine_vk_device_proc<PFN_vkGetImageMemoryRequirements>(
        compositor, "vkGetImageMemoryRequirements");
    auto vkAllocateMemory = kine_vk_device_proc<PFN_vkAllocateMemory>(
        compositor, "vkAllocateMemory");
    auto vkBindImageMemory = kine_vk_device_proc<PFN_vkBindImageMemory>(
        compositor, "vkBindImageMemory");
    if (!vkCreateImage || !vkGetImageMemoryRequirements || !vkAllocateMemory || !vkBindImageMemory) {
        kine_vk_set_error(compositor, "required depth-attachment Vulkan procs unavailable");
        return false;
    }

    VkFormat depthFormat = VK_FORMAT_UNDEFINED;
    if (!kine_vk_choose_depth_format(compositor, &depthFormat)) {
        kine_vk_set_error(compositor, "no supported Vulkan depth format found");
        return false;
    }

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.extent.width = compositor->width;
    imageInfo.extent.height = compositor->height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.format = depthFormat;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imageInfo.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateImage(compositor->device, &imageInfo, nullptr, &compositor->depthImage) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateImage depth failed");
        return false;
    }

    VkMemoryRequirements requirements{};
    vkGetImageMemoryRequirements(compositor->device, compositor->depthImage, &requirements);
    uint32_t memoryTypeIndex = kine_vk_find_memory_type(
        compositor,
        requirements.memoryTypeBits,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (memoryTypeIndex == UINT32_MAX) {
        kine_vk_set_error(compositor, "no device-local memory type for depth image");
        return false;
    }

    VkMemoryAllocateInfo allocateInfo{};
    allocateInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocateInfo.allocationSize = requirements.size;
    allocateInfo.memoryTypeIndex = memoryTypeIndex;
    if (vkAllocateMemory(
            compositor->device,
            &allocateInfo,
            nullptr,
            &compositor->depthImageMemory) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkAllocateMemory depth failed");
        return false;
    }

    if (vkBindImageMemory(
            compositor->device,
            compositor->depthImage,
            compositor->depthImageMemory,
            0) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkBindImageMemory depth failed");
        return false;
    }

    compositor->depthFormat = depthFormat;
    return true;
}

static bool kine_vk_create_skia_context(KineVulkanCompositor* compositor)
{
    KineSkiaVulkanBackend backend{};
    backend.instance = compositor->instance;
    backend.physicalDevice = compositor->physicalDevice;
    backend.device = compositor->device;
    backend.queue = compositor->graphicsQueue;
    backend.graphicsQueueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    backend.maxApiVersion = compositor->apiVersion;
    backend.getInstanceProcAddr = reinterpret_cast<void*>(compositor->getInstanceProcAddr);
    backend.getDeviceProcAddr = reinterpret_cast<void*>(compositor->getDeviceProcAddr);

    compositor->skiaContext = Kine_Skia_Vulkan_CreateContext(&backend);
    if (!compositor->skiaContext) {
        kine_vk_set_error(compositor, "Kine_Skia_Vulkan_CreateContext failed");
        return false;
    }

    return true;
}

static bool kine_vk_create_swapchain(KineVulkanCompositor* compositor)
{
    auto vkGetPhysicalDeviceSurfaceCapabilitiesKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceCapabilitiesKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    auto vkGetPhysicalDeviceSurfaceFormatsKHR =
        kine_vk_instance_proc<PFN_vkGetPhysicalDeviceSurfaceFormatsKHR>(
            compositor, "vkGetPhysicalDeviceSurfaceFormatsKHR");
    auto vkCreateSwapchainKHR = kine_vk_device_proc<PFN_vkCreateSwapchainKHR>(
        compositor, "vkCreateSwapchainKHR");
    auto vkGetSwapchainImagesKHR = kine_vk_device_proc<PFN_vkGetSwapchainImagesKHR>(
        compositor, "vkGetSwapchainImagesKHR");
    auto vkCreateImageView = kine_vk_device_proc<PFN_vkCreateImageView>(
        compositor, "vkCreateImageView");
    if (!vkGetPhysicalDeviceSurfaceCapabilitiesKHR || !vkGetPhysicalDeviceSurfaceFormatsKHR ||
        !vkCreateSwapchainKHR || !vkGetSwapchainImagesKHR || !vkCreateImageView) {
        kine_vk_set_error(compositor, "required swapchain Vulkan procs unavailable");
        return false;
    }

    VkSurfaceCapabilitiesKHR capabilities{};
    if (vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            compositor->physicalDevice, compositor->surface, &capabilities) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed");
        return false;
    }

    uint32_t formatCount = 0;
    if (vkGetPhysicalDeviceSurfaceFormatsKHR(
            compositor->physicalDevice, compositor->surface, &formatCount, nullptr) != VK_SUCCESS ||
        formatCount == 0) {
        kine_vk_set_error(compositor, "no Vulkan surface formats found");
        return false;
    }

    std::vector<VkSurfaceFormatKHR> formats(formatCount);
    if (vkGetPhysicalDeviceSurfaceFormatsKHR(
            compositor->physicalDevice, compositor->surface, &formatCount, formats.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkGetPhysicalDeviceSurfaceFormatsKHR failed");
        return false;
    }

    VkSurfaceFormatKHR chosenFormat = formats[0];
    for (const VkSurfaceFormatKHR& format : formats) {
        if ((format.format == VK_FORMAT_R8G8B8A8_UNORM ||
             format.format == VK_FORMAT_B8G8R8A8_UNORM ||
             format.format == VK_FORMAT_R8G8B8A8_SRGB ||
             format.format == VK_FORMAT_B8G8R8A8_SRGB) &&
            format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosenFormat = format;
            break;
        }
    }

    VkExtent2D extent = capabilities.currentExtent;
    if (extent.width == UINT32_MAX) {
        extent.width = std::clamp(
            compositor->width,
            capabilities.minImageExtent.width,
            capabilities.maxImageExtent.width);
        extent.height = std::clamp(
            compositor->height,
            capabilities.minImageExtent.height,
            capabilities.maxImageExtent.height);
    }

    uint32_t imageCount = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0) {
        imageCount = std::min(imageCount, capabilities.maxImageCount);
    }

    VkImageUsageFlags swapchainUsage =
        VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
        VK_IMAGE_USAGE_TRANSFER_DST_BIT |
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    swapchainUsage &= capabilities.supportedUsageFlags;
    if ((swapchainUsage & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) == 0) {
        kine_vk_set_error(compositor, "surface does not support color-attachment swapchain images");
        return false;
    }

    const VkCompositeAlphaFlagBitsKHR compositeAlphaCandidates[] = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
    VkCompositeAlphaFlagBitsKHR compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    for (VkCompositeAlphaFlagBitsKHR candidate : compositeAlphaCandidates) {
        if (capabilities.supportedCompositeAlpha & candidate) {
            compositeAlpha = candidate;
            break;
        }
    }

    VkSwapchainCreateInfoKHR createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    createInfo.surface = compositor->surface;
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = chosenFormat.format;
    createInfo.imageColorSpace = chosenFormat.colorSpace;
    createInfo.imageExtent = extent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = swapchainUsage;
    createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    createInfo.preTransform = capabilities.currentTransform;
    createInfo.compositeAlpha = compositeAlpha;
    createInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    createInfo.clipped = VK_TRUE;
    createInfo.oldSwapchain = VK_NULL_HANDLE;

    VkResult result = vkCreateSwapchainKHR(compositor->device, &createInfo, nullptr, &compositor->swapchain);
    if (result != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkCreateSwapchainKHR failed");
        return false;
    }

    uint32_t swapchainImageCount = 0;
    if (vkGetSwapchainImagesKHR(
            compositor->device, compositor->swapchain, &swapchainImageCount, nullptr) != VK_SUCCESS ||
        swapchainImageCount == 0) {
        kine_vk_set_error(compositor, "vkGetSwapchainImagesKHR failed");
        return false;
    }

    compositor->swapchainImages.resize(swapchainImageCount);
    if (vkGetSwapchainImagesKHR(
            compositor->device,
            compositor->swapchain,
            &swapchainImageCount,
            compositor->swapchainImages.data()) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkGetSwapchainImagesKHR images failed");
        return false;
    }

    compositor->swapchainFormat = chosenFormat.format;
    compositor->swapchainUsage = swapchainUsage;
    compositor->swapchainExtent = extent;
    compositor->width = extent.width;
    compositor->height = extent.height;
    compositor->swapchainImageLayouts.assign(
        compositor->swapchainImages.size(),
        VK_IMAGE_LAYOUT_UNDEFINED);

    compositor->swapchainImageViews.reserve(compositor->swapchainImages.size());
    for (VkImage image : compositor->swapchainImages) {
        VkImageViewCreateInfo viewInfo{};
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = image;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = compositor->swapchainFormat;
        viewInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        viewInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        viewInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        viewInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
        viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;

        VkImageView imageView = VK_NULL_HANDLE;
        if (vkCreateImageView(compositor->device, &viewInfo, nullptr, &imageView) != VK_SUCCESS) {
            kine_vk_set_error(compositor, "vkCreateImageView failed");
            return false;
        }
        compositor->swapchainImageViews.push_back(imageView);
    }

    return true;
}

static void kine_vk_destroy_swapchain_attachments(KineVulkanCompositor* compositor)
{
    if (!compositor || !compositor->device) {
        return;
    }

    if (auto vkDestroyImageView = kine_vk_device_proc<PFN_vkDestroyImageView>(
            compositor, "vkDestroyImageView")) {
        for (VkImageView imageView : compositor->swapchainImageViews) {
            if (imageView) {
                vkDestroyImageView(compositor->device, imageView, nullptr);
            }
        }
    }
    compositor->swapchainImageViews.clear();
    compositor->swapchainImages.clear();
    compositor->swapchainImageLayouts.clear();

    if (compositor->depthImage) {
        if (auto vkDestroyImage = kine_vk_device_proc<PFN_vkDestroyImage>(
                compositor, "vkDestroyImage")) {
            vkDestroyImage(compositor->device, compositor->depthImage, nullptr);
        }
        compositor->depthImage = VK_NULL_HANDLE;
    }
    if (compositor->depthImageMemory) {
        if (auto vkFreeMemory = kine_vk_device_proc<PFN_vkFreeMemory>(
                compositor, "vkFreeMemory")) {
            vkFreeMemory(compositor->device, compositor->depthImageMemory, nullptr);
        }
        compositor->depthImageMemory = VK_NULL_HANDLE;
    }
    compositor->depthFormat = VK_FORMAT_UNDEFINED;

    if (compositor->swapchain) {
        if (auto vkDestroySwapchainKHR = kine_vk_device_proc<PFN_vkDestroySwapchainKHR>(
                compositor, "vkDestroySwapchainKHR")) {
            vkDestroySwapchainKHR(compositor->device, compositor->swapchain, nullptr);
        }
        compositor->swapchain = VK_NULL_HANDLE;
    }
    compositor->swapchainFormat = VK_FORMAT_UNDEFINED;
    compositor->swapchainUsage = 0;
    compositor->swapchainExtent = {};
}

static bool kine_vk_transition_current_image(
    KineVulkanCompositor* compositor,
    VkImageLayout oldLayout,
    VkImageLayout newLayout,
    VkSemaphore waitSemaphore = VK_NULL_HANDLE)
{
    if (oldLayout == newLayout) {
        return true;
    }

    auto vkResetCommandBuffer = kine_vk_device_proc<PFN_vkResetCommandBuffer>(
        compositor, "vkResetCommandBuffer");
    auto vkBeginCommandBuffer = kine_vk_device_proc<PFN_vkBeginCommandBuffer>(
        compositor, "vkBeginCommandBuffer");
    auto vkCmdPipelineBarrier = kine_vk_device_proc<PFN_vkCmdPipelineBarrier>(
        compositor, "vkCmdPipelineBarrier");
    auto vkEndCommandBuffer = kine_vk_device_proc<PFN_vkEndCommandBuffer>(
        compositor, "vkEndCommandBuffer");
    auto vkQueueSubmit = kine_vk_device_proc<PFN_vkQueueSubmit>(
        compositor, "vkQueueSubmit");
    auto vkQueueWaitIdle = kine_vk_device_proc<PFN_vkQueueWaitIdle>(
        compositor, "vkQueueWaitIdle");
    if (!vkResetCommandBuffer || !vkBeginCommandBuffer || !vkCmdPipelineBarrier ||
        !vkEndCommandBuffer || !vkQueueSubmit || !vkQueueWaitIdle ||
        !compositor->commandBuffer || compositor->currentImageIndex >= compositor->swapchainImages.size()) {
        kine_vk_set_error(compositor, "required image-transition Vulkan procs unavailable");
        return false;
    }

    vkResetCommandBuffer(compositor->commandBuffer, 0);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(compositor->commandBuffer, &beginInfo) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkBeginCommandBuffer failed");
        return false;
    }

    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = oldLayout;
    barrier.newLayout = newLayout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = compositor->swapchainImages[compositor->currentImageIndex];
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    VkPipelineStageFlags srcStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkPipelineStageFlags dstStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;

    if (oldLayout == VK_IMAGE_LAYOUT_UNDEFINED) {
        barrier.srcAccessMask = 0;
        srcStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        srcStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else if (oldLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
        barrier.srcAccessMask = 0;
        srcStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    }

    if (newLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
        barrier.dstAccessMask = 0;
        dstStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    } else if (newLayout == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        dstStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    }

    vkCmdPipelineBarrier(
        compositor->commandBuffer,
        srcStage,
        dstStage,
        0,
        0,
        nullptr,
        0,
        nullptr,
        1,
        &barrier);

    if (vkEndCommandBuffer(compositor->commandBuffer) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkEndCommandBuffer failed");
        return false;
    }

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    if (waitSemaphore) {
        submitInfo.waitSemaphoreCount = 1;
        submitInfo.pWaitSemaphores = &waitSemaphore;
        submitInfo.pWaitDstStageMask = &waitStage;
    }
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &compositor->commandBuffer;
    if (vkQueueSubmit(compositor->graphicsQueue, 1, &submitInfo, VK_NULL_HANDLE) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkQueueSubmit failed");
        return false;
    }

    vkQueueWaitIdle(compositor->graphicsQueue);
    compositor->swapchainImageLayouts[compositor->currentImageIndex] = newLayout;
    return true;
}

static KineSkiaSurface* kine_vk_create_current_skia_surface(KineVulkanCompositor* compositor)
{
    if (!compositor || !compositor->skiaContext ||
        compositor->currentImageIndex >= compositor->swapchainImages.size()) {
        return nullptr;
    }

    KineSkiaVulkanImageInfo imageInfo{};
    imageInfo.image = compositor->swapchainImages[compositor->currentImageIndex];
    imageInfo.format = compositor->swapchainFormat;
    imageInfo.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    imageInfo.imageTiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.imageUsageFlags = compositor->swapchainUsage;
    imageInfo.sampleCount = 1;
    imageInfo.levelCount = 1;
    imageInfo.currentQueueFamily = VK_QUEUE_FAMILY_IGNORED;

    return Kine_Skia_Surface_CreateVulkanRenderTarget(
        compositor->skiaContext,
        static_cast<int>(compositor->width),
        static_cast<int>(compositor->height),
        &imageInfo);
}

extern "C" {

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindow(void* sdlWindow, int width, int height)
{
    if (!sdlWindow || width <= 0 || height <= 0) {
        return nullptr;
    }

    auto* compositor = new KineVulkanCompositor();
    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    compositor->ownsInstance = true;
    compositor->ownsDevice = true;

    if (!kine_vk_create_instance(compositor) ||
        !kine_vk_create_surface(compositor, sdlWindow) ||
        !kine_vk_pick_device(compositor) ||
        !kine_vk_create_device(compositor) ||
        !kine_vk_create_frame_resources(compositor) ||
        !kine_vk_create_swapchain(compositor)) {
        return compositor;
    }

    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr, "kine_vulkan_compositor: depth attachment unavailable, continuing without swapchain depth: %s\n",
            compositor->lastError.c_str());
        compositor->depthImage = VK_NULL_HANDLE;
        compositor->depthImageMemory = VK_NULL_HANDLE;
        compositor->depthFormat = VK_FORMAT_UNDEFINED;
        compositor->lastError.clear();
    }

    if (!kine_vk_create_skia_context(compositor)) {
        return compositor;
    }

    compositor->lastError.clear();
    return compositor;
}

KINE_VULKAN_COMPOSITOR_API KineVulkanCompositor*
Kine_VulkanCompositor_CreateForSDLWindowWithBackend(
    void* sdlWindow,
    int width,
    int height,
    const KineVulkanCompositorBackend* backend)
{
    if (!sdlWindow || width <= 0 || height <= 0 || !backend ||
        !backend->instance || !backend->physicalDevice || !backend->device ||
        !backend->queue || !backend->getInstanceProcAddr) {
        return nullptr;
    }

    auto* compositor = new KineVulkanCompositor();
    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    compositor->ownsInstance = false;
    compositor->ownsDevice = false;
    compositor->getInstanceProcAddr =
        reinterpret_cast<PFN_vkGetInstanceProcAddr>(backend->getInstanceProcAddr);
    compositor->getDeviceProcAddr =
        reinterpret_cast<PFN_vkGetDeviceProcAddr>(backend->getDeviceProcAddr);
    compositor->instance = reinterpret_cast<VkInstance>(backend->instance);
    compositor->physicalDevice = reinterpret_cast<VkPhysicalDevice>(backend->physicalDevice);
    compositor->device = reinterpret_cast<VkDevice>(backend->device);
    compositor->graphicsQueue = reinterpret_cast<VkQueue>(backend->queue);
    compositor->graphicsQueueFamilyIndex = backend->graphicsQueueFamilyIndex;
    compositor->graphicsQueueCount = 1;
    compositor->apiVersion = backend->maxApiVersion != 0
        ? backend->maxApiVersion
        : VK_API_VERSION_1_0;

    if (!compositor->getDeviceProcAddr) {
        compositor->getDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
            compositor->getInstanceProcAddr(compositor->instance, "vkGetDeviceProcAddr"));
    }
    if (!compositor->getDeviceProcAddr) {
        kine_vk_set_error(compositor, "vkGetDeviceProcAddr unavailable for external Vulkan device");
        return compositor;
    }

    if (!kine_vk_create_surface(compositor, sdlWindow) ||
        !kine_vk_validate_present_queue(compositor) ||
        !kine_vk_create_frame_resources(compositor) ||
        !kine_vk_create_swapchain(compositor)) {
        return compositor;
    }

    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr, "kine_vulkan_compositor: depth attachment unavailable, continuing without swapchain depth: %s\n",
            compositor->lastError.c_str());
        compositor->depthImage = VK_NULL_HANDLE;
        compositor->depthImageMemory = VK_NULL_HANDLE;
        compositor->depthFormat = VK_FORMAT_UNDEFINED;
        compositor->lastError.clear();
    }

    if (!kine_vk_create_skia_context(compositor)) {
        return compositor;
    }

    compositor->lastError.clear();
    return compositor;
}

KINE_VULKAN_COMPOSITOR_API void
Kine_VulkanCompositor_Destroy(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return;
    }

    if (compositor->currentSkiaSurface) {
        Kine_Skia_Surface_Destroy(compositor->currentSkiaSurface);
        compositor->currentSkiaSurface = nullptr;
    }
    if (compositor->skiaContext) {
        Kine_Skia_Vulkan_DestroyContext(compositor->skiaContext);
        compositor->skiaContext = nullptr;
    }

    if (compositor->device) {
        if (auto vkDeviceWaitIdle = kine_vk_device_proc<PFN_vkDeviceWaitIdle>(compositor, "vkDeviceWaitIdle")) {
            vkDeviceWaitIdle(compositor->device);
        }
        if (compositor->acquireFence) {
            if (auto vkDestroyFence = kine_vk_device_proc<PFN_vkDestroyFence>(
                    compositor, "vkDestroyFence")) {
                vkDestroyFence(compositor->device, compositor->acquireFence, nullptr);
            }
            compositor->acquireFence = VK_NULL_HANDLE;
        }
        if (compositor->filamentImageReadySemaphore) {
            if (auto vkDestroySemaphore = kine_vk_device_proc<PFN_vkDestroySemaphore>(
                    compositor, "vkDestroySemaphore")) {
                vkDestroySemaphore(compositor->device, compositor->filamentImageReadySemaphore, nullptr);
            }
            compositor->filamentImageReadySemaphore = VK_NULL_HANDLE;
        }
        kine_vk_destroy_swapchain_attachments(compositor);
        if (compositor->commandPool) {
            if (auto vkDestroyCommandPool = kine_vk_device_proc<PFN_vkDestroyCommandPool>(
                    compositor, "vkDestroyCommandPool")) {
                vkDestroyCommandPool(compositor->device, compositor->commandPool, nullptr);
            }
            compositor->commandPool = VK_NULL_HANDLE;
            compositor->commandBuffer = VK_NULL_HANDLE;
        }
        if (compositor->ownsDevice) {
            if (auto vkDestroyDevice = kine_vk_device_proc<PFN_vkDestroyDevice>(compositor, "vkDestroyDevice")) {
                vkDestroyDevice(compositor->device, nullptr);
            }
        }
        compositor->device = VK_NULL_HANDLE;
    }

    if (compositor->surface && compositor->instance) {
        if (auto vkDestroySurfaceKHR = kine_vk_instance_proc<PFN_vkDestroySurfaceKHR>(
                compositor, "vkDestroySurfaceKHR")) {
            vkDestroySurfaceKHR(compositor->instance, compositor->surface, nullptr);
        }
        compositor->surface = VK_NULL_HANDLE;
    }

    if (compositor->instance && compositor->ownsInstance) {
        if (auto vkDestroyInstance = kine_vk_instance_proc<PFN_vkDestroyInstance>(
                compositor, "vkDestroyInstance")) {
            vkDestroyInstance(compositor->instance, nullptr);
        }
    }
    compositor->instance = VK_NULL_HANDLE;

    delete compositor;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_Resize(
    KineVulkanCompositor* compositor,
    int width,
    int height)
{
    if (!compositor || !compositor->device || width <= 0 || height <= 0) {
        return 0;
    }
    if (compositor->width == static_cast<uint32_t>(width) &&
        compositor->height == static_cast<uint32_t>(height) &&
        compositor->swapchain) {
        return 1;
    }

    auto vkDeviceWaitIdle = kine_vk_device_proc<PFN_vkDeviceWaitIdle>(
        compositor, "vkDeviceWaitIdle");
    if (!vkDeviceWaitIdle || vkDeviceWaitIdle(compositor->device) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkDeviceWaitIdle failed during compositor resize");
        return 0;
    }

    if (compositor->currentSkiaSurface) {
        Kine_Skia_Surface_Destroy(compositor->currentSkiaSurface);
        compositor->currentSkiaSurface = nullptr;
    }
    compositor->frameActive = false;
    compositor->currentImageIndex = UINT32_MAX;
    kine_vk_destroy_swapchain_attachments(compositor);

    compositor->width = static_cast<uint32_t>(width);
    compositor->height = static_cast<uint32_t>(height);
    if (!kine_vk_create_swapchain(compositor)) {
        return 0;
    }
    if (!kine_vk_create_depth_attachment(compositor)) {
        fprintf(stderr,
            "kine_vulkan_compositor: depth attachment unavailable after resize: %s\n",
            compositor->lastError.c_str());
        compositor->depthImage = VK_NULL_HANDLE;
        compositor->depthImageMemory = VK_NULL_HANDLE;
        compositor->depthFormat = VK_FORMAT_UNDEFINED;
    }

    compositor->lastError.clear();
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_IsReady(const KineVulkanCompositor* compositor)
{
    return compositor && compositor->instance && compositor->surface &&
        compositor->physicalDevice && compositor->device &&
        compositor->graphicsQueue && compositor->swapchain &&
        !compositor->swapchainImages.empty() && compositor->commandPool &&
        compositor->commandBuffer && compositor->acquireFence &&
        compositor->filamentImageReadySemaphore && compositor->skiaContext &&
        compositor->lastError.empty();
}

KINE_VULKAN_COMPOSITOR_API const char*
Kine_VulkanCompositor_GetLastError(const KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return "null compositor";
    }
    return compositor->lastError.c_str();
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_GetInfo(
    const KineVulkanCompositor* compositor,
    KineVulkanCompositorInfo* outInfo)
{
    if (!compositor || !outInfo) {
        return 0;
    }

    std::memset(outInfo, 0, sizeof(*outInfo));
    outInfo->instance = compositor->instance;
    outInfo->surface = compositor->surface;
    outInfo->physicalDevice = compositor->physicalDevice;
    outInfo->device = compositor->device;
    outInfo->graphicsQueue = compositor->graphicsQueue;
    outInfo->swapchain = compositor->swapchain;
    outInfo->swapchainFormat = static_cast<uint32_t>(compositor->swapchainFormat);
    outInfo->swapchainImageCount = static_cast<uint32_t>(compositor->swapchainImages.size());
    outInfo->graphicsQueueFamilyIndex = compositor->graphicsQueueFamilyIndex;
    outInfo->graphicsQueueCount = compositor->graphicsQueueCount;
    outInfo->width = compositor->width;
    outInfo->height = compositor->height;
    return 1;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetSkiaContext(KineVulkanCompositor* compositor)
{
    return compositor ? compositor->skiaContext : nullptr;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_GetCurrentSkiaSurface(KineVulkanCompositor* compositor)
{
    return compositor ? compositor->currentSkiaSurface : nullptr;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetSwapchainImages(
    KineVulkanCompositor* compositor,
    void** outImages,
    uint32_t maxImages)
{
    if (!compositor) {
        return 0;
    }

    uint32_t count = static_cast<uint32_t>(compositor->swapchainImages.size());
    if (outImages && maxImages > 0) {
        uint32_t n = std::min(count, maxImages);
        for (uint32_t i = 0; i < n; ++i) {
            outImages[i] = compositor->swapchainImages[i];
        }
    }
    return count;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_GetDepthAttachment(
    KineVulkanCompositor* compositor,
    void** outImage,
    uint32_t* outFormat)
{
    if (outImage) {
        *outImage = nullptr;
    }
    if (outFormat) {
        *outFormat = 0;
    }
    if (!compositor || !compositor->depthImage || compositor->depthFormat == VK_FORMAT_UNDEFINED) {
        return 0;
    }
    if (outImage) {
        *outImage = compositor->depthImage;
    }
    if (outFormat) {
        *outFormat = static_cast<uint32_t>(compositor->depthFormat);
    }
    return 1;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_PrepareFilament(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return 0;
    }
    {
        std::lock_guard<std::mutex> lock(compositor->filamentMutex);
        if (!compositor->frameActive ||
            compositor->currentImageIndex >= compositor->swapchainImages.size()) {
            kine_vk_set_error(compositor, "Filament preparation requires an active compositor frame");
            return 0;
        }
        if (compositor->filamentPrepared) {
            return 1;
        }
    }

    // Skia contexts are thread-affine. This function is called by the render
    // thread before Filament dispatches acquire() to its backend thread.
    if (compositor->currentSkiaSurface) {
        Kine_Skia_Surface_Flush(compositor->currentSkiaSurface);
        if (auto vkQueueWaitIdle = kine_vk_device_proc<PFN_vkQueueWaitIdle>(
                compositor, "vkQueueWaitIdle")) {
            if (vkQueueWaitIdle(compositor->graphicsQueue) != VK_SUCCESS) {
                kine_vk_set_error(compositor, "Skia queue wait failed before Filament");
                return 0;
            }
        } else {
            kine_vk_set_error(compositor, "vkQueueWaitIdle unavailable before Filament");
            return 0;
        }
        Kine_Skia_Surface_Destroy(compositor->currentSkiaSurface);
        compositor->currentSkiaSurface = nullptr;
    }

    // BeginFrame CPU-waits the WSI acquire fence, and the queue wait above
    // drains Skia. The image is therefore already available to Filament; a
    // second ready semaphore is redundant and has proven unstable in Intel's
    // Windows Vulkan driver.
    {
        std::lock_guard<std::mutex> lock(compositor->filamentMutex);
        compositor->filamentPrepared = true;
        compositor->filamentPresented = false;
        compositor->filamentFinishedSemaphore = VK_NULL_HANDLE;
    }
    compositor->lastError.clear();
    return 1;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentAcquire(
    KineVulkanCompositor* compositor,
    uint32_t* outImageIndex,
    void** outImageReadySemaphore)
{
    if (outImageReadySemaphore) {
        *outImageReadySemaphore = nullptr;
    }
    if (!compositor) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    std::lock_guard<std::mutex> lock(compositor->filamentMutex);
    if (!compositor->frameActive || !compositor->filamentPrepared ||
        compositor->currentImageIndex >= compositor->swapchainImages.size()) {
        kine_vk_set_error(compositor, "Filament acquire requires a prepared compositor frame");
        return VK_ERROR_OUT_OF_DATE_KHR;
    }

    if (outImageIndex) {
        *outImageIndex = compositor->currentImageIndex;
    }
    if (outImageReadySemaphore) {
        *outImageReadySemaphore = nullptr;
    }
    return VK_SUCCESS;
}

KINE_VULKAN_COMPOSITOR_API uint32_t
Kine_VulkanCompositor_FilamentPresent(
    KineVulkanCompositor* compositor,
    uint32_t imageIndex,
    void* finishedDrawingSemaphore)
{
    if (!compositor) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }

    std::lock_guard<std::mutex> lock(compositor->filamentMutex);
    if (!compositor->frameActive || !compositor->filamentPrepared ||
        imageIndex != compositor->currentImageIndex) {
        kine_vk_set_error(compositor, "Filament present received an invalid compositor image");
        return VK_ERROR_OUT_OF_DATE_KHR;
    }

    // Filament invokes this callback after enqueuing its rendering work. The
    // compositor consumes this semaphore in EndFrame's transition submission;
    // no Vulkan queue calls are made from Filament's backend thread.
    compositor->filamentFinishedSemaphore =
        reinterpret_cast<VkSemaphore>(finishedDrawingSemaphore);
    compositor->filamentPresented = true;
    compositor->filamentCondition.notify_one();
    return VK_SUCCESS;
}

KINE_VULKAN_COMPOSITOR_API void*
Kine_VulkanCompositor_BeginFrame(KineVulkanCompositor* compositor)
{
    if (!Kine_VulkanCompositor_IsReady(compositor)) {
        return nullptr;
    }
    if (compositor->frameActive) {
        return compositor->currentSkiaSurface;
    }

    auto vkAcquireNextImageKHR = kine_vk_device_proc<PFN_vkAcquireNextImageKHR>(
        compositor, "vkAcquireNextImageKHR");
    auto vkWaitForFences = kine_vk_device_proc<PFN_vkWaitForFences>(
        compositor, "vkWaitForFences");
    auto vkResetFences = kine_vk_device_proc<PFN_vkResetFences>(
        compositor, "vkResetFences");
    if (!vkAcquireNextImageKHR || !vkWaitForFences || !vkResetFences) {
        kine_vk_set_error(compositor, "required acquire Vulkan procs unavailable");
        return nullptr;
    }

    compositor->currentImageIndex = UINT32_MAX;
    VkResult acquired = vkAcquireNextImageKHR(
        compositor->device,
        compositor->swapchain,
        UINT64_MAX,
        VK_NULL_HANDLE,
        compositor->acquireFence,
        &compositor->currentImageIndex);
    if (acquired != VK_SUCCESS && acquired != VK_SUBOPTIMAL_KHR) {
        kine_vk_set_error(compositor, "vkAcquireNextImageKHR failed");
        return nullptr;
    }

    if (vkWaitForFences(
            compositor->device,
            1,
            &compositor->acquireFence,
            VK_TRUE,
            UINT64_MAX) != VK_SUCCESS) {
        kine_vk_set_error(compositor, "vkWaitForFences failed");
        return nullptr;
    }
    vkResetFences(compositor->device, 1, &compositor->acquireFence);

    if (compositor->currentImageIndex >= compositor->swapchainImages.size()) {
        kine_vk_set_error(compositor, "vkAcquireNextImageKHR returned an invalid image index");
        return nullptr;
    }

    VkImageLayout currentLayout = compositor->swapchainImageLayouts[compositor->currentImageIndex];
    if (!kine_vk_transition_current_image(
            compositor,
            currentLayout,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)) {
        return nullptr;
    }

    compositor->currentSkiaSurface = kine_vk_create_current_skia_surface(compositor);
    if (!compositor->currentSkiaSurface) {
        kine_vk_set_error(compositor, "Kine_Skia_Surface_CreateVulkanRenderTarget failed");
        return nullptr;
    }

    {
        std::lock_guard<std::mutex> lock(compositor->filamentMutex);
        compositor->frameActive = true;
        compositor->filamentPrepared = false;
        compositor->filamentPresented = false;
        compositor->filamentFinishedSemaphore = VK_NULL_HANDLE;
    }
    compositor->lastError.clear();
    return compositor->currentSkiaSurface;
}

KINE_VULKAN_COMPOSITOR_API int
Kine_VulkanCompositor_EndFrame(KineVulkanCompositor* compositor)
{
    if (!compositor) {
        return 0;
    }

    VkSemaphore filamentFinished = VK_NULL_HANDLE;
    {
        std::unique_lock<std::mutex> lock(compositor->filamentMutex);
        if (!compositor->frameActive) {
            return 0;
        }
        if (compositor->filamentPrepared) {
            constexpr auto kFilamentTimeout = std::chrono::seconds(5);
            if (!compositor->filamentCondition.wait_for(
                    lock,
                    kFilamentTimeout,
                    [compositor] { return compositor->filamentPresented; })) {
                kine_vk_set_error(compositor, "timed out waiting for Filament present callback");
                return 0;
            }
            filamentFinished = compositor->filamentFinishedSemaphore;
        }
    }

    auto vkQueuePresentKHR = kine_vk_device_proc<PFN_vkQueuePresentKHR>(
        compositor, "vkQueuePresentKHR");
    if (!vkQueuePresentKHR) {
        kine_vk_set_error(compositor, "vkQueuePresentKHR unavailable");
        return 0;
    }

    if (compositor->currentSkiaSurface) {
        Kine_Skia_Surface_Flush(compositor->currentSkiaSurface);
    }

    if (!kine_vk_transition_current_image(
            compositor,
            VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            filamentFinished)) {
        return 0;
    }

    VkPresentInfoKHR presentInfo{};
    presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = &compositor->swapchain;
    presentInfo.pImageIndices = &compositor->currentImageIndex;

    VkResult presented = vkQueuePresentKHR(compositor->graphicsQueue, &presentInfo);

    if (compositor->currentSkiaSurface) {
        Kine_Skia_Surface_Destroy(compositor->currentSkiaSurface);
        compositor->currentSkiaSurface = nullptr;
    }
    {
        std::lock_guard<std::mutex> lock(compositor->filamentMutex);
        compositor->currentImageIndex = UINT32_MAX;
        compositor->frameActive = false;
        compositor->filamentPrepared = false;
        compositor->filamentPresented = false;
        compositor->filamentFinishedSemaphore = VK_NULL_HANDLE;
    }

    if (presented != VK_SUCCESS && presented != VK_SUBOPTIMAL_KHR) {
        kine_vk_set_error(compositor, "vkQueuePresentKHR failed");
        return 0;
    }

    compositor->lastError.clear();
    return 1;
}

}
