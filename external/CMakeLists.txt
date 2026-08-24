
cmake_minimum_required(VERSION 3.25)

project(Kinemium
    VERSION 0.1.0
    DESCRIPTION "KinemiumEngineLibs"
    LANGUAGES C CXX
)

if(APPLE)
    enable_language(OBJC)
    enable_language(OBJCXX)
endif()

include(FetchContent)

# Build external projects as static inputs, then whole-archive them into one
# shared library at the end of this file.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "" FORCE)
if(WIN32)
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON CACHE BOOL "" FORCE)
endif()
if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL" CACHE STRING "" FORCE)
endif()

set(KINE_WITH_FILAMENT ON CACHE BOOL "" FORCE)
set(KINE_BUILD_SHARED OFF CACHE BOOL "" FORCE)
add_subdirectory(kine_render_shim)
add_subdirectory(kine_skia)

# Manifold
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
set(MANIFOLD_DEBUG OFF CACHE BOOL "" FORCE)
set(MANIFOLD_ASSERT OFF CACHE BOOL "" FORCE)
set(MANIFOLD_TIMING OFF CACHE BOOL "" FORCE)
set(MANIFOLD_STRICT OFF CACHE BOOL "" FORCE)
set(MANIFOLD_NO_IOSTREAM OFF CACHE BOOL "" FORCE)
set(MANIFOLD_DOWNLOADS ON CACHE BOOL "" FORCE)
set(MANIFOLD_PAR ON CACHE BOOL "" FORCE)
set(MANIFOLD_OPTIMIZED ON CACHE BOOL "" FORCE)
set(MANIFOLD_TEST OFF CACHE BOOL "" FORCE)
set(MANIFOLD_PYBIND OFF CACHE BOOL "" FORCE)
set(MANIFOLD_CBIND ON CACHE BOOL "" FORCE)
set(MANIFOLD_USE_BUILTIN_TBB ON CACHE BOOL "" FORCE)
set(MANIFOLD_USE_BUILTIN_NANOBIND OFF CACHE BOOL "" FORCE)
set(TRACY_ENABLE OFF CACHE BOOL "" FORCE)
set(TRACY_MEMORY_USAGE OFF CACHE BOOL "" FORCE)
set(MANIFOLD_FUZZ OFF CACHE BOOL "" FORCE)
set(ASSIMP_ENABLE OFF CACHE BOOL "" FORCE)
add_subdirectory(manifold)

# Box2D
add_subdirectory(box2d)

# NFD
add_subdirectory(nativefiledialog)

# sdl_image
set(SDLIMAGE_DEPS_SHARED OFF CACHE BOOL "" FORCE)
set(SDLIMAGE_AVIF OFF CACHE BOOL "Support loading AVIF images" FORCE)
add_subdirectory(SDL_image)

# Jolt Wrapper
add_subdirectory(kine_jolt)

foreach(_kine_export_target IN ITEMS kine_render_shim kine_filament_shim)
    if(TARGET ${_kine_export_target})
        target_compile_definitions(${_kine_export_target} PRIVATE KINE_BUILD_SHARED KINE_BUILD_EXPORTS)
    endif()
endforeach()

if(TARGET box2d)
    target_compile_definitions(box2d PRIVATE box2d_EXPORTS)
endif()

if(TARGET nfd)
    target_compile_definitions(nfd PRIVATE NFD_EXPORT)
endif()

if(TARGET SDL3-static)
    target_compile_definitions(SDL3-static PRIVATE DLL_EXPORT)
endif()

if(TARGET SDL3_image-static)
    target_compile_definitions(SDL3_image-static PRIVATE DLL_EXPORT)
endif()

# One runtime library for the engine's native dependency surface.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c" "void kinemium_libs_anchor(void) {}\n")

add_library(KinemiumLibs SHARED
    "${CMAKE_CURRENT_BINARY_DIR}/kinemium_libs.c"
)

if(WIN32)
    set(KINE_MANIFOLD_C_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/manifold/bindings/c/include/manifold/manifoldc.h")
    set(KINE_KINEMIUM_LIBS_DEF "${CMAKE_CURRENT_BINARY_DIR}/KinemiumLibs.def")

    file(READ "${KINE_MANIFOLD_C_HEADER}" KINE_MANIFOLD_C_HEADER_CONTENTS)
    string(REGEX MATCHALL "[A-Za-z_][A-Za-z0-9_]*[ \t\r\n*]+manifold_[A-Za-z0-9_]+[ \t\r\n]*\\("
        KINE_MANIFOLD_C_DECLARATIONS
        "${KINE_MANIFOLD_C_HEADER_CONTENTS}"
    )

    set(KINE_MANIFOLD_C_EXPORTS)
    foreach(KINE_MANIFOLD_C_DECLARATION IN LISTS KINE_MANIFOLD_C_DECLARATIONS)
        string(REGEX MATCH "manifold_[A-Za-z0-9_]+" KINE_MANIFOLD_C_SYMBOL "${KINE_MANIFOLD_C_DECLARATION}")
        list(APPEND KINE_MANIFOLD_C_EXPORTS "${KINE_MANIFOLD_C_SYMBOL}")
    endforeach()
    list(REMOVE_DUPLICATES KINE_MANIFOLD_C_EXPORTS)
    list(SORT KINE_MANIFOLD_C_EXPORTS)

    file(WRITE "${KINE_KINEMIUM_LIBS_DEF}" "EXPORTS\n")
    foreach(KINE_MANIFOLD_C_SYMBOL IN LISTS KINE_MANIFOLD_C_EXPORTS)
        file(APPEND "${KINE_KINEMIUM_LIBS_DEF}" "    ${KINE_MANIFOLD_C_SYMBOL}\n")
    endforeach()

    target_sources(KinemiumLibs PRIVATE "${KINE_KINEMIUM_LIBS_DEF}")
endif()

set_target_properties(KinemiumLibs PROPERTIES
    OUTPUT_NAME "KinemiumLibs"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

if(WIN32)
    set_target_properties(KinemiumLibs PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

function(kine_link_whole_archive target dependency)
    if(TARGET ${dependency})
        target_link_libraries(${target} PRIVATE "$<LINK_LIBRARY:WHOLE_ARCHIVE,${dependency}>")
    endif()
endfunction()

kine_link_whole_archive(KinemiumLibs kine_render_shim)
kine_link_whole_archive(KinemiumLibs kine_filament_shim)
kine_link_whole_archive(KinemiumLibs kine_skia)
kine_link_whole_archive(KinemiumLibs JoltWrapper)
kine_link_whole_archive(KinemiumLibs box2d)
kine_link_whole_archive(KinemiumLibs nfd)
kine_link_whole_archive(KinemiumLibs manifold)
kine_link_whole_archive(KinemiumLibs manifoldc)
kine_link_whole_archive(KinemiumLibs SDL3-static)
kine_link_whole_archive(KinemiumLibs SDL3_image-static)

target_link_libraries(KinemiumLibs
    PRIVATE
        $<$<TARGET_EXISTS:SDL3::SDL3-static>:SDL3::SDL3-static>
        $<$<TARGET_EXISTS:SDL3_image::SDL3_image-static>:SDL3_image::SDL3_image-static>
)

if(WIN32)
    target_link_libraries(KinemiumLibs PRIVATE
        user32 gdi32 ole32 shell32 opengl32 advapi32 imm32 setupapi version winmm
    )
elseif(APPLE)
    target_link_libraries(KinemiumLibs PRIVATE
        "-framework AppKit"
        "-framework Cocoa"
        "-framework CoreFoundation"
        "-framework CoreGraphics"
        "-framework CoreServices"
        "-framework CoreText"
        "-framework CoreVideo"
        "-framework IOKit"
        "-framework Metal"
        "-framework MetalKit"
        "-framework OpenGL"
        "-framework QuartzCore"
        "-framework UniformTypeIdentifiers"
    )
else()
    find_library(KINE_LIBCXX NAMES c++ libc++.so.1)
    find_library(KINE_LIBCXXABI NAMES c++abi libc++abi.so.1)

    target_link_options(KinemiumLibs PRIVATE -Wl,-z,noexecstack)
    target_link_libraries(KinemiumLibs PRIVATE GL X11 dl pthread m)

    if(KINE_LIBCXX)
        target_link_libraries(KinemiumLibs PRIVATE "${KINE_LIBCXX}")
    endif()

    if(KINE_LIBCXXABI)
        target_link_libraries(KinemiumLibs PRIVATE "${KINE_LIBCXXABI}")
    endif()
endif()
