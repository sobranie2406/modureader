# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "modu")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.modu.reader")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Define the application target. To change its name, change BINARY_NAME above,
# not the value here, or `flutter run` will no longer work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include("${CMAKE_CURRENT_SOURCE_DIR}/../cmake/modu_onnxruntime_package.cmake")
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|amd64)$")
  set(MODU_ORT_ARCH "x64")
  set(MODU_ORT_LIBRARY_SHA256 "3da6146e14e7b8aaec625dde11d6114c7457c87a5f93d744897da8781e35c673")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64)$")
  set(MODU_ORT_ARCH "arm64")
  set(MODU_ORT_LIBRARY_SHA256 "0afd69a0ae38c5099fd0e8604dda398ac43dee67cd9c6394b5142b19e82528de")
else()
  message(FATAL_ERROR "Unsupported ONNX Runtime architecture: ${CMAKE_SYSTEM_PROCESSOR}")
endif()
set(MODU_ORT_NATIVE_LIBRARY "${modu_ort_SOURCE_DIR}/runtimes/linux-${MODU_ORT_ARCH}/native/libonnxruntime.so")
file(SHA256 "${MODU_ORT_NATIVE_LIBRARY}" MODU_ORT_ACTUAL_SHA256)
if(NOT MODU_ORT_ACTUAL_SHA256 STREQUAL MODU_ORT_LIBRARY_SHA256)
  message(FATAL_ERROR "ONNX Runtime Linux library checksum mismatch")
endif()
set(MODU_ORT_LINK_DIR "${CMAKE_CURRENT_BINARY_DIR}/modu-onnxruntime")
file(MAKE_DIRECTORY "${MODU_ORT_LINK_DIR}")
file(CREATE_LINK "${MODU_ORT_NATIVE_LIBRARY}" "${MODU_ORT_LINK_DIR}/libonnxruntime.so.1" SYMBOLIC)
target_link_options(${BINARY_NAME} PRIVATE "LINKER:-rpath-link,${MODU_ORT_LINK_DIR}")
# The plugin's unchecked GitHub download no longer exists; use the verified package.
set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use verified ONNX Runtime" FORCE)
set(ONNXRUNTIME_LIBRARY "${MODU_ORT_LINK_DIR}/libonnxruntime.so.1" CACHE FILEPATH "ONNX Runtime library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${modu_ort_SOURCE_DIR}/build/native/include" CACHE PATH "ONNX Runtime headers" FORCE)
include(flutter/generated_plugins.cmake)
if(TARGET flutter_inappwebview_linux_plugin)
  # The plugin references a newer optional API absent in Debian's WPE 2.48.
  target_compile_options(flutter_inappwebview_linux_plugin PRIVATE
    "-include" "${CMAKE_CURRENT_SOURCE_DIR}/wpe_compat.h")
  target_link_libraries(flutter_inappwebview_linux_plugin PRIVATE ${CMAKE_DL_LIBS})
endif()


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

install(FILES "${MODU_ORT_NATIVE_LIBRARY}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" RENAME "libonnxruntime.so.${MODU_ORT_VERSION}"
  COMPONENT Runtime)
install(CODE "
  file(CREATE_LINK \"libonnxruntime.so.${MODU_ORT_VERSION}\" \"${INSTALL_BUNDLE_LIB_DIR}/libonnxruntime.so.1\" SYMBOLIC)
  file(CREATE_LINK \"libonnxruntime.so.1\" \"${INSTALL_BUNDLE_LIB_DIR}/libonnxruntime.so\" SYMBOLIC)
" COMPONENT Runtime)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/LINUX-RUNTIME.txt"
  "ONNX Runtime ${MODU_ORT_VERSION}: ${MODU_ORT_NUGET_URL}\n"
  "Package SHA-256: ${MODU_ORT_NUGET_SHA256}\n"
  "Library SHA-256: ${MODU_ORT_LIBRARY_SHA256}\n"
  "MIT license and ThirdPartyNotices: LICENSES/ONNXRuntime-1.22.0-*.txt\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/LINUX-RUNTIME.txt"
  DESTINATION "${CMAKE_INSTALL_PREFIX}" COMPONENT Runtime)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
