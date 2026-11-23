set(UT3_IOS_GUEST_BASE "0x7000000000ull" CACHE STRING "Guest-window base validated by the physical-device VM probe")
set(UT3_IOS_DEVELOPMENT_TEAM "" CACHE STRING "Apple development signing team")
set(UT3_IOS_BUNDLE_ID "org.ut3.port.ios" CACHE STRING "iOS application identifier")
target_compile_definitions(ut3_build_options INTERFACE UT3_IOS VOID_GUEST_BASE=${UT3_IOS_GUEST_BASE})
find_library(UIKIT_FRAMEWORK UIKit REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
find_library(GAMECONTROLLER_FRAMEWORK GameController REQUIRED)
find_library(AVFAUDIO_FRAMEWORK AVFAudio REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(COREHAPTICS_FRAMEWORK CoreHaptics REQUIRED)
add_executable(ut3-ios MACOSX_BUNDLE platform/apple/ios/Application.m platform/apple/ios/GameView.m
    platform/apple/ControllerHaptics.m platform/apple/DataPaths.m)
target_link_libraries(ut3-ios PRIVATE ut3_build_options ut3_runtime_entry ut3_host ut3_host_threads ut3_lift
    ${UIKIT_FRAMEWORK} ${FOUNDATION_FRAMEWORK} ${GAMECONTROLLER_FRAMEWORK} ${AVFAUDIO_FRAMEWORK} ${QUARTZCORE_FRAMEWORK} ${COREHAPTICS_FRAMEWORK})
target_compile_options(ut3-ios PRIVATE -fobjc-arc -Wall -Wextra -Wno-unused-parameter)
set(sha1_fixture "${CMAKE_CURRENT_BINARY_DIR}/sha1_rotate_bodies.inc")
add_custom_command(OUTPUT "${sha1_fixture}"
    COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/apple_rotates.py"
        "${UT3_GENERATED}/ut3/functions_0261.c" "${sha1_fixture}"
    DEPENDS tools/apple_rotates.py "${UT3_GENERATED}/ut3/functions_0261.c" VERBATIM)
target_sources(ut3-ios PRIVATE tests/test_apple_sha1_rotate.c "${sha1_fixture}")
target_include_directories(ut3-ios PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
set_source_files_properties(tests/test_apple_sha1_rotate.c PROPERTIES
    COMPILE_OPTIONS "-O1;-UNDEBUG;-Wno-deprecated-declarations;-mllvm;-basic-aa-separate-storage;-include;${CMAKE_CURRENT_SOURCE_DIR}/engine/runtime/guest_state_prefix.h"
    COMPILE_DEFINITIONS RECOMP_GUEST_STATE_SEPARATE)
set_target_properties(ut3-ios PROPERTIES
    OUTPUT_NAME "Unreal Tournament 3"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${UT3_IOS_BUNDLE_ID}"
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/platform/apple/ios/Info.plist.in"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${UT3_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${UT3_IOS_DEVELOPMENT_TEAM}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")

# Keep asset generation in the native build, before development packaging/signing.
set(ios_icon "${CMAKE_CURRENT_SOURCE_DIR}/icons/AppIcon1024.png")
set(ios_icon_tool "${CMAKE_CURRENT_SOURCE_DIR}/tools/build_ios_icon.py")
set_property(TARGET ut3-ios APPEND PROPERTY LINK_DEPENDS "${ios_icon}" "${ios_icon_tool}")
add_custom_command(TARGET ut3-ios POST_BUILD
    COMMAND "${Python3_EXECUTABLE}" -B "${ios_icon_tool}" --png "${ios_icon}"
        --app "$<TARGET_BUNDLE_DIR:ut3-ios>" --work "${CMAKE_CURRENT_BINARY_DIR}/ios-icon"
    VERBATIM)

set(UT3_IOS_MOLTENVK "" CACHE FILEPATH "Pinned MoltenVK static library built for physical iOS ARM64")
set(UT3_IOS_VULKAN_INCLUDE "" CACHE PATH "Matching Vulkan headers")
if(UT3_IOS_MOLTENVK)
    find_library(METAL_FRAMEWORK Metal REQUIRED)
    find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
    find_library(IOSURFACE_FRAMEWORK IOSurface REQUIRED)
    target_sources(ut3-ios PRIVATE tests/test_vulkan_wsi.mm)
    target_compile_definitions(ut3-ios PRIVATE UT3_VULKAN_PROBE_LIBRARY)
    target_include_directories(ut3-ios PRIVATE "${UT3_IOS_VULKAN_INCLUDE}")
    set_target_properties(ut3-ios PROPERTIES CXX_STANDARD 17 OBJCXX_STANDARD 17)
    target_link_libraries(ut3-ios PRIVATE "${UT3_IOS_MOLTENVK}" "${METAL_FRAMEWORK}"
        "${QUARTZCORE_FRAMEWORK}" "${IOSURFACE_FRAMEWORK}" "-framework CoreGraphics")
endif()

set(UT3_IOS_OPENAL "" CACHE FILEPATH "Pinned OpenAL Soft iPhoneOS ARM64 dylib")
set(UT3_IOS_OPENAL_INCLUDE "" CACHE PATH "Matching OpenAL Soft include directory")
if(UT3_IOS_OPENAL)
    if(NOT EXISTS "${UT3_IOS_OPENAL}" OR NOT EXISTS "${UT3_IOS_OPENAL_INCLUDE}/AL/efx.h")
        message(FATAL_ERROR "iOS audio requires the actual device library and matching OpenAL headers")
    endif()
    set(openal_bundle_lib "${CMAKE_CURRENT_BINARY_DIR}/libopenal.1.dylib")
    add_custom_command(OUTPUT "${openal_bundle_lib}"
        COMMAND "${CMAKE_COMMAND}" -E copy "${UT3_IOS_OPENAL}" "${openal_bundle_lib}"
        DEPENDS "${UT3_IOS_OPENAL}" VERBATIM)
    set_source_files_properties("${openal_bundle_lib}" PROPERTIES MACOSX_PACKAGE_LOCATION Frameworks)
    target_sources(ut3-ios PRIVATE "${openal_bundle_lib}" engine/host/openal.c)
    target_include_directories(ut3-ios PRIVATE "${UT3_IOS_OPENAL_INCLUDE}")
    target_compile_definitions(ut3-ios PRIVATE UT3_APPLE_OPENAL)
endif()

set(UT3_IOS_DXVK "" CACHE FILEPATH "Pinned DXVK D3D9 dylib cross-compiled for iOS ARM64")
if(UT3_IOS_DXVK)
    if(NOT UT3_IOS_MOLTENVK)
        message(FATAL_ERROR "The iOS DXVK probe requires the linked MoltenVK library")
    endif()
    set(bridge_dir "${CMAKE_CURRENT_BINARY_DIR}/dxvk-bridge")
    set(bridge_generated guest_methods.inc bridge_metadata.inc bridge_dispatch.inc bridge_special_names.inc)
    list(TRANSFORM bridge_generated PREPEND "${bridge_dir}/")
    add_custom_command(OUTPUT ${bridge_generated}
        COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/tools/generate_dxvk_bridge.py" --output "${bridge_dir}"
        DEPENDS tools/generate_dxvk_bridge.py reference/dxvk/include/native/directx/d3d9.h VERBATIM)
    set(dxvk_bundle_lib "${CMAKE_CURRENT_BINARY_DIR}/libdxvk_d3d9.dylib")
    add_custom_command(OUTPUT "${dxvk_bundle_lib}"
        COMMAND "${CMAKE_COMMAND}" -E copy "${UT3_IOS_DXVK}" "${dxvk_bundle_lib}"
        DEPENDS "${UT3_IOS_DXVK}" VERBATIM)
    set_source_files_properties("${dxvk_bundle_lib}" PROPERTIES MACOSX_PACKAGE_LOCATION Frameworks)
    target_sources(ut3-ios PRIVATE ${bridge_generated} "${dxvk_bundle_lib}"
        engine/dxvk/bridge.cpp engine/dxvk/shader_warmup.cpp engine/host/d3d9_dxvk.c engine/host/postfx.c
        engine/host/network.c engine/host/dsound.c platform/apple/MetalPresentation.mm
        platform/apple/d3d9_shims.c platform/apple/d3d9_probe.c)
    target_include_directories(ut3-ios PRIVATE platform/apple "${bridge_dir}"
        reference/dxvk/include/native/windows reference/dxvk/include/native/directx)
    target_compile_definitions(ut3-ios PRIVATE UT3_APPLE_DXVK)
endif()
