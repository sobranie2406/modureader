# flutter_onnxruntime 1.8.4 treats all 64-bit Windows as x64. Supply the
# correct official runtime before loading that plugin, including its DLL.
include(FetchContent)
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" OR
   CMAKE_GENERATOR_PLATFORM MATCHES "[Aa][Rr][Mm]64")
  set(MODU_ORT_ARCH arm64)
else()
  set(MODU_ORT_ARCH x64)
endif()
set(MODU_ORT_VERSION 1.22.0)
FetchContent_Declare(modu_ort
  URL "https://github.com/microsoft/onnxruntime/releases/download/v${MODU_ORT_VERSION}/onnxruntime-win-${MODU_ORT_ARCH}-${MODU_ORT_VERSION}.zip")
FetchContent_MakeAvailable(modu_ort)
set(ONNXRUNTIME_ROOT_DIR "${modu_ort_SOURCE_DIR}" CACHE PATH "Modu ONNX runtime" FORCE)
set(ONNXRUNTIME_LIBRARY "${modu_ort_SOURCE_DIR}/lib/onnxruntime.lib" CACHE FILEPATH "Modu ONNX library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${modu_ort_SOURCE_DIR}/include" CACHE PATH "Modu ONNX headers" FORCE)
set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use architecture-matched runtime" FORCE)
set(MODU_ONNXRUNTIME_DLL "${modu_ort_SOURCE_DIR}/lib/onnxruntime.dll")
if(NOT EXISTS "${MODU_ONNXRUNTIME_DLL}")
  message(FATAL_ERROR "Missing architecture-matched ONNX runtime")
endif()
