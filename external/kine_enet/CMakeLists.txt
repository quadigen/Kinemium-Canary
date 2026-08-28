cmake_minimum_required(VERSION 3.15)
project(kine_enet LANGUAGES C)

add_library(kine_enet STATIC
    src/kine_enet.c
)

target_include_directories(kine_enet
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    PRIVATE
        ${enet_SOURCE_DIR}/include
)

target_link_libraries(kine_enet PRIVATE enet)
if(WIN32)
    target_link_libraries(kine_enet PUBLIC winmm ws2_32)
endif()
set_target_properties(kine_enet PROPERTIES POSITION_INDEPENDENT_CODE ON)
