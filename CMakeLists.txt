cmake_minimum_required(VERSION 3.22)
project(ut3_apple LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME MATCHES "^(Darwin|iOS)$" OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "Configure an Apple ARM64 target with -DCMAKE_OSX_ARCHITECTURES=arm64")
endif()
if(NOT CMAKE_C_COMPILER_ID STREQUAL "AppleClang")
    message(FATAL_ERROR "The headless runtime target uses Apple Clang")
endif()

find_package(Python3 3.12 REQUIRED COMPONENTS Interpreter)
find_package(ZLIB REQUIRED)
find_package(Threads REQUIRED)

set(UT3_GENERATED "${CMAKE_CURRENT_SOURCE_DIR}/generated" CACHE PATH "Complete pinned lift")
set(UT3_CALL_PROTOCOL "" CACHE FILEPATH "Optional validated masked call protocol summary")
set(UT3_X87_LOCALS "" CACHE FILEPATH "Optional x87 local-register plan for the call protocol")
set(UT3_LIFT_OPT_LEVEL "1" CACHE STRING "Clang optimization level for the lifted C bodies")
set(sha1_rotate_default OFF)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(sha1_rotate_default ON)
endif()
option(UT3_APPLE_SHA1_ROTATES "Simplify the pinned SHA-1 guest body's 32-bit rotates" ${sha1_rotate_default})

set(host_dir "${CMAKE_CURRENT_SOURCE_DIR}/engine/host")
set(host_names
    ai_native ai_perception_native ai_reach_native ai_trace_native argv bstr collision_native
    com compat core core_native crt_compat crt_native crypt32 d3dx_math dinput8 eh features files
    game_native hooks imm32 input kernel32 loading memory openspy particle_native pe pe_builtin
    pe_images pe_resources perf physx_native power profiles query_native render_bitarray_native render_draw_native
    render_hash_native render_light_native render_native render_occlusion_native render_sparse_native
    render_visibility_native rpc setupapi strings system system_parameters texture_cache touch_game
    touch_menu ui_camera ui_hud ui_list_scale user32 xinput zipmount
)
set(host_sources)
set(prep_args)
if(UT3_APPLE_SHA1_ROTATES)
    list(APPEND prep_args --sha1-rotates)
endif()
foreach(name IN LISTS host_names)
    list(APPEND host_sources "${host_dir}/${name}.c")
    list(APPEND prep_args --host-source "${host_dir}/${name}.c")
endforeach()
list(APPEND prep_args --host-source "${host_dir}/threads.c")
list(APPEND prep_args --host-source "${CMAKE_CURRENT_SOURCE_DIR}/platform/apple/ProductKey.c")
if(UT3_CALL_PROTOCOL)
    list(APPEND prep_args --protocol "${UT3_CALL_PROTOCOL}")
endif()
if(UT3_X87_LOCALS)
    list(APPEND prep_args --x87-locals "${UT3_X87_LOCALS}")
endif()

set(prepared "${CMAKE_CURRENT_BINARY_DIR}/prepared")
execute_process(
    COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/prepare_macos.py"
            --generated "${UT3_GENERATED}" --output "${prepared}" ${prep_args}
    COMMAND_ERROR_IS_FATAL ANY
)
include("${prepared}/lifted.cmake")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${UT3_LIFT_INPUTS} config/modules.json config/warm-functions.txt
    tools/lift_build.py tools/prepare_macos.py tools/apple_rotates.py tools/protocol_transform.py tools/x87_locals.py tools/x87_slots.py
    platform/apple/ProductKey.c
)
if(UT3_CALL_PROTOCOL)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${host_sources} engine/host/threads.c)
endif()

add_library(ut3_build_options INTERFACE)
target_include_directories(ut3_build_options INTERFACE
    "${host_dir}" engine/runtime "${UT3_GENERATED}"
)
target_compile_features(ut3_build_options INTERFACE c_std_11)
target_compile_options(ut3_build_options INTERFACE
    -fno-strict-aliasing -fwrapv -fvisibility=hidden -ffp-contract=off -fno-math-errno
)
target_compile_definitions(ut3_build_options INTERFACE RECOMP_X87_WINDOW UT3_MACOS_HEADLESS)
target_link_libraries(ut3_build_options INTERFACE ZLIB::ZLIB Threads::Threads)
foreach(symbol IN LISTS UT3_WRAPS)
    target_link_options(ut3_build_options INTERFACE "LINKER:-alias,___wrap_${symbol},_${symbol}")
endforeach()

add_library(ut3_lift OBJECT ${UT3_LIFTED_SOURCES})
target_link_libraries(ut3_lift PRIVATE ut3_build_options)
target_compile_options(ut3_lift PRIVATE "-O${UT3_LIFT_OPT_LEVEL}" -g0 -w)
set_source_files_properties("${UT3_GENERATED}/dispatch.c" PROPERTIES COMPILE_DEFINITIONS RECOMP_GENERATED_CODE)
set_source_files_properties(${UT3_LIFTED_SOURCES} PROPERTIES
    COMPILE_OPTIONS "-mllvm;-basic-aa-separate-storage;-include;${CMAKE_CURRENT_SOURCE_DIR}/engine/runtime/guest_state_prefix.h"
)
target_compile_definitions(ut3_lift PRIVATE RECOMP_GUEST_STATE_SEPARATE)
if(UT3_CALL_PROTOCOL)
    target_compile_definitions(ut3_lift PRIVATE RECOMP_LOCAL_REGS)
endif()

find_library(COREFOUNDATION_FRAMEWORK CoreFoundation REQUIRED)
add_library(ut3_host OBJECT ${host_sources} platform/apple/frame.c platform/apple/ProductKey.c)
target_link_libraries(ut3_host PRIVATE ut3_build_options PUBLIC ${COREFOUNDATION_FRAMEWORK})
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    find_library(IOKIT_FRAMEWORK IOKit REQUIRED)
    target_sources(ut3_host PRIVATE platform/apple/power.c)
    target_link_libraries(ut3_host PUBLIC ${IOKIT_FRAMEWORK})
endif()
set_source_files_properties("${host_dir}/pe_builtin.c" PROPERTIES
    OBJECT_DEPENDS "${UT3_GENERATED}/input/msvcr80.dll;${UT3_GENERATED}/input/msvcp80.dll"
)
add_library(ut3_host_threads OBJECT "${host_dir}/threads.c")
target_link_libraries(ut3_host_threads PRIVATE ut3_build_options)
add_library(ut3_runtime_entry OBJECT "${host_dir}/main.c")
target_link_libraries(ut3_runtime_entry PRIVATE ut3_build_options)
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    include(platform/apple/ios/CMakeLists.txt)
    return()
endif()
add_executable(ut3-runtime-selftest platform/apple/headless.c)
target_link_libraries(ut3-runtime-selftest PRIVATE ut3_build_options ut3_runtime_entry ut3_host ut3_host_threads ut3_lift)

find_library(APPKIT_FRAMEWORK AppKit REQUIRED)
find_library(GAMECONTROLLER_FRAMEWORK GameController REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(COREGRAPHICS_FRAMEWORK CoreGraphics REQUIRED)
add_executable(ut3-macos MACOSX_BUNDLE
    platform/apple/Application.m platform/apple/GameView.m platform/apple/ShellValidation.m platform/apple/DataPaths.m
)
set(ut3_icon "${CMAKE_CURRENT_BINARY_DIR}/UT3.icns")
add_custom_command(OUTPUT "${ut3_icon}"
    COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_macos_icon.py"
        "${CMAKE_CURRENT_SOURCE_DIR}/icons/AppIcon1024.png" "${ut3_icon}"
    DEPENDS icons/AppIcon1024.png tools/build_macos_icon.py
    VERBATIM
)
set_source_files_properties("${ut3_icon}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
target_sources(ut3-macos PRIVATE "${ut3_icon}")
set_target_properties(ut3-macos PROPERTIES
    OUTPUT_NAME "Unreal Tournament 3"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/platform/apple/Info.plist.in"
)
target_compile_options(ut3-macos PRIVATE "$<$<COMPILE_LANGUAGE:OBJC,OBJCXX>:-fobjc-arc>" -Wall -Wextra -Wno-unused-parameter)
target_link_libraries(ut3-macos PRIVATE ut3_build_options ut3_runtime_entry ut3_host ut3_host_threads ut3_lift
    ${APPKIT_FRAMEWORK} ${GAMECONTROLLER_FRAMEWORK} ${QUARTZCORE_FRAMEWORK} ${COREGRAPHICS_FRAMEWORK}
)
set(UT3_DXVK_LIBRARY "" CACHE FILEPATH "Pinned macOS native D3D9 dylib for graphics validation")
set(UT3_VULKAN_SDK "${CMAKE_CURRENT_SOURCE_DIR}/build/apple/phase3-inputs/VulkanSDK/macOS"
    CACHE PATH "Local macOS Vulkan SDK used when launching the app from Finder")
set(UT3_VULKAN_SDK_PLIST "${UT3_VULKAN_SDK}")
string(REPLACE "&" "&amp;" UT3_VULKAN_SDK_PLIST "${UT3_VULKAN_SDK_PLIST}")
string(REPLACE "<" "&lt;" UT3_VULKAN_SDK_PLIST "${UT3_VULKAN_SDK_PLIST}")
string(REPLACE ">" "&gt;" UT3_VULKAN_SDK_PLIST "${UT3_VULKAN_SDK_PLIST}")
set(UT3_OPENAL_LIBRARY "" CACHE FILEPATH "Pinned OpenAL Soft CoreAudio dylib")
set(UT3_OPENAL_INCLUDE "" CACHE PATH "OpenAL Soft include directory")
if(UT3_DXVK_LIBRARY)
    if(NOT EXISTS "${UT3_DXVK_LIBRARY}")
        message(FATAL_ERROR "UT3_DXVK_LIBRARY does not exist: ${UT3_DXVK_LIBRARY}")
    endif()
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(SECURITY_FRAMEWORK Security REQUIRED)
    set(bridge_dir "${CMAKE_CURRENT_BINARY_DIR}/dxvk-bridge")
    set(bridge_generated guest_methods.inc bridge_metadata.inc bridge_dispatch.inc bridge_special_names.inc)
    list(TRANSFORM bridge_generated PREPEND "${bridge_dir}/")
    add_custom_command(OUTPUT ${bridge_generated}
        COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/generate_dxvk_bridge.py"
                --output "${bridge_dir}"
        DEPENDS tools/generate_dxvk_bridge.py reference/dxvk/include/native/directx/d3d9.h
        VERBATIM
    )
    set(dxvk_bundle_lib "${CMAKE_CURRENT_BINARY_DIR}/libdxvk_d3d9.dylib")
    add_custom_command(OUTPUT "${dxvk_bundle_lib}"
        COMMAND "${CMAKE_COMMAND}" -E copy "${UT3_DXVK_LIBRARY}" "${dxvk_bundle_lib}"
        DEPENDS "${UT3_DXVK_LIBRARY}" VERBATIM
    )
    set_source_files_properties("${dxvk_bundle_lib}" PROPERTIES MACOSX_PACKAGE_LOCATION Frameworks)
    target_sources(ut3-macos PRIVATE
        ${bridge_generated} "${dxvk_bundle_lib}"
        engine/dxvk/bridge.cpp engine/dxvk/shader_warmup.cpp engine/host/d3d9_dxvk.c engine/host/postfx.c
        engine/host/network.c engine/host/dsound.c
        platform/apple/MetalPresentation.mm platform/apple/ProtectedData.m
        platform/apple/d3d9_shims.c platform/apple/d3d9_probe.c
    )
    target_compile_definitions(ut3-macos PRIVATE UT3_APPLE_DXVK)
    set_target_properties(ut3-macos PROPERTIES CXX_STANDARD 17 OBJCXX_STANDARD 17)
    target_include_directories(ut3-macos PRIVATE platform/apple "${bridge_dir}"
        reference/dxvk/include/native/windows reference/dxvk/include/native/directx)
    target_link_libraries(ut3-macos PRIVATE ${METAL_FRAMEWORK} ${SECURITY_FRAMEWORK})
    if(UT3_OPENAL_LIBRARY)
        if(NOT EXISTS "${UT3_OPENAL_LIBRARY}" OR NOT EXISTS "${UT3_OPENAL_INCLUDE}/AL/efx.h")
            message(FATAL_ERROR "The OpenAL Soft library and its matching headers are required")
        endif()
        set(openal_bundle_lib "${CMAKE_CURRENT_BINARY_DIR}/libopenal.1.dylib")
        add_custom_command(OUTPUT "${openal_bundle_lib}"
            COMMAND "${CMAKE_COMMAND}" -E copy "${UT3_OPENAL_LIBRARY}" "${openal_bundle_lib}"
            DEPENDS "${UT3_OPENAL_LIBRARY}" VERBATIM)
        set_source_files_properties("${openal_bundle_lib}" PROPERTIES MACOSX_PACKAGE_LOCATION Frameworks)
        target_sources(ut3-macos PRIVATE "${openal_bundle_lib}" engine/host/openal.c)
        target_include_directories(ut3-macos PRIVATE "${UT3_OPENAL_INCLUDE}")
        target_compile_definitions(ut3-macos PRIVATE UT3_APPLE_OPENAL)
    endif()
endif()

include(CTest)
if(BUILD_TESTING)
    add_executable(ut3-test-apple-data-paths tests/test_apple_data_paths.m platform/apple/DataPaths.m)
    target_compile_options(ut3-test-apple-data-paths PRIVATE -fobjc-arc -UNDEBUG)
    target_link_libraries(ut3-test-apple-data-paths PRIVATE "-framework Foundation")
    add_test(NAME apple-data-paths COMMAND ut3-test-apple-data-paths)
    add_executable(ut3-test-zipmount-io tests/test_zipmount_io.c engine/io/zipmount.c)
    target_compile_options(ut3-test-zipmount-io PRIVATE -UNDEBUG)
    add_test(NAME zipmount-io COMMAND "${Python3_EXECUTABLE}" -B
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/run_zipmount_io.py" $<TARGET_FILE:ut3-test-zipmount-io>)
    add_executable(ut3-test-shader-warmup-codec tests/test_shader_warmup_codec.cpp)
    target_compile_features(ut3-test-shader-warmup-codec PRIVATE cxx_std_17)
    target_compile_options(ut3-test-shader-warmup-codec PRIVATE -UNDEBUG)
    target_link_libraries(ut3-test-shader-warmup-codec PRIVATE ZLIB::ZLIB)
    add_test(NAME shader-warmup-codec COMMAND ut3-test-shader-warmup-codec)
    set(sha1_fixture "${CMAKE_CURRENT_BINARY_DIR}/sha1_rotate_bodies.inc")
    add_custom_command(OUTPUT "${sha1_fixture}"
        COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/apple_rotates.py"
            "${UT3_GENERATED}/ut3/functions_0261.c" "${sha1_fixture}"
        DEPENDS tools/apple_rotates.py "${UT3_GENERATED}/ut3/functions_0261.c" VERBATIM)
    add_executable(ut3-test-apple-sha1-rotate tests/test_apple_sha1_rotate.c "${sha1_fixture}")
    target_include_directories(ut3-test-apple-sha1-rotate PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
    target_compile_options(ut3-test-apple-sha1-rotate PRIVATE -O1 -fwrapv -fno-strict-aliasing -UNDEBUG -Wno-deprecated-declarations
        -mllvm -basic-aa-separate-storage -include "${CMAKE_CURRENT_SOURCE_DIR}/engine/runtime/guest_state_prefix.h")
    target_compile_definitions(ut3-test-apple-sha1-rotate PRIVATE RECOMP_GUEST_STATE_SEPARATE)
    add_test(NAME apple-sha1-rotate COMMAND ut3-test-apple-sha1-rotate)
    add_executable(ut3-test-ios-pointer tests/test_ios_pointer.c)
    target_compile_options(ut3-test-ios-pointer PRIVATE -UNDEBUG)
    add_test(NAME ios-pointer COMMAND ut3-test-ios-pointer)
    add_executable(ut3-test-apple-frame-gate tests/test_apple_frame_gate.c)
    target_include_directories(ut3-test-apple-frame-gate PRIVATE engine/host engine/runtime generated)
    target_compile_options(ut3-test-apple-frame-gate PRIVATE -UNDEBUG)
    add_test(NAME apple-frame-gate COMMAND ut3-test-apple-frame-gate)
    add_executable(ut3-test-apple-text tests/test_apple_text.c)
    target_include_directories(ut3-test-apple-text PRIVATE engine/host engine/runtime generated)
    target_compile_options(ut3-test-apple-text PRIVATE -UNDEBUG)
    add_test(NAME apple-text COMMAND ut3-test-apple-text)
    add_executable(ut3-test-keychain-interaction tests/test_keychain_interaction.m)
    target_compile_options(ut3-test-keychain-interaction PRIVATE -fobjc-arc -UNDEBUG)
    target_link_libraries(ut3-test-keychain-interaction PRIVATE "-framework Foundation" "-framework Security")
    add_test(NAME keychain-interaction COMMAND ut3-test-keychain-interaction)
    add_executable(ut3-test-product-key-file tests/test_product_key_file.c)
    target_include_directories(ut3-test-product-key-file PRIVATE engine/host)
    target_compile_features(ut3-test-product-key-file PRIVATE c_std_11)
    target_compile_options(ut3-test-product-key-file PRIVATE -UNDEBUG)
    add_test(NAME product-key-file COMMAND ut3-test-product-key-file)
    add_executable(ut3-test-virtual-alloc tests/test_virtual_alloc.c)
    target_compile_options(ut3-test-virtual-alloc PRIVATE -UNDEBUG)
    target_link_libraries(ut3-test-virtual-alloc PRIVATE ut3_build_options ut3_host ut3_host_threads ut3_lift)
    add_test(NAME virtual-alloc COMMAND ut3-test-virtual-alloc)

    add_executable(ut3-test-named-events tests/test_named_events.c)
    target_compile_options(ut3-test-named-events PRIVATE -UNDEBUG)
    target_link_libraries(ut3-test-named-events PRIVATE ut3_build_options ut3_host ut3_lift)
    add_test(NAME named-events COMMAND ut3-test-named-events)

    add_executable(ut3-test-critical-sections tests/test_critical_sections.c)
    target_compile_options(ut3-test-critical-sections PRIVATE -UNDEBUG)
    target_link_libraries(ut3-test-critical-sections PRIVATE ut3_build_options ut3_host ut3_lift)
    add_test(NAME critical-sections COMMAND ut3-test-critical-sections)

    foreach(fixture IN ITEMS wsa_events wsa_readiness dsound_capture dsound_devices)
        add_executable(ut3-test-${fixture} tests/test_${fixture}.c)
        target_compile_options(ut3-test-${fixture} PRIVATE -UNDEBUG)
        target_link_libraries(ut3-test-${fixture} PRIVATE ut3_build_options ut3_host ut3_host_threads ut3_lift)
        add_test(NAME ${fixture} COMMAND ut3-test-${fixture})
    endforeach()
endif()
