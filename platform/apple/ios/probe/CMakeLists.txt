cmake_minimum_required(VERSION 3.22)
project(UT3DeviceProbe LANGUAGES C OBJC)
set(UT3_IOS_DEVELOPMENT_TEAM "" CACHE STRING "Apple development signing team")
add_executable(ut3-ios-probe MACOSX_BUNDLE main.m)
target_compile_options(ut3-ios-probe PRIVATE -fobjc-arc)
target_link_libraries(ut3-ios-probe PRIVATE "-framework UIKit")
set_target_properties(ut3-ios-probe PROPERTIES
  MACOSX_BUNDLE_GUI_IDENTIFIER org.ut3.port.ios.probe
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist"
  XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
  XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${UT3_IOS_DEVELOPMENT_TEAM}"
  XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
  XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER org.ut3.port.ios.probe)
