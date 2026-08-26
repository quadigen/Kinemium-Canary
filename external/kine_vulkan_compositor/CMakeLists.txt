cmake_minimum_required(VERSION 3.25)

project(kine_vulkan_compositor VERSION 0.1.0 LANGUAGES CXX)

add_library(kine_vulkan_compositor STATIC
    src/kine_vulkan_compositor.cpp
)

target_compile_features(kine_vulkan_compositor PRIVATE cxx_std_20)

target_include_directories(kine_vulkan_compositor
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/../kine_skia/include
        ${CMAKE_BINARY_DIR}/kine_skia/skia-src/third_party/externals/vulkan-headers/include
)

target_compile_definitions(kine_vulkan_compositor
    PRIVATE
        KINE_VULKAN_COMPOSITOR_BUILD_EXPORTS
)

target_link_libraries(kine_vulkan_compositor
    PRIVATE
        kine_skia
        $<$<TARGET_EXISTS:SDL3::SDL3-static>:SDL3::SDL3-static>
        $<$<TARGET_EXISTS:SDL3-static>:SDL3-static>
)

if(WIN32)
    target_link_libraries(kine_vulkan_compositor PRIVATE user32 gdi32 shell32)
elseif(APPLE)
    target_link_libraries(kine_vulkan_compositor PRIVATE
        "-framework Cocoa"
        "-framework CoreVideo"
        "-framework QuartzCore"
    )
else()
    target_link_libraries(kine_vulkan_compositor PRIVATE dl pthread)
endif()
