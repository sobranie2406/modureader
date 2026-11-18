# flutter_onnxruntime 1.8.4 treats all 64-bit Windows as x64. Supply the
# correct official runtime before loading that plugin, including its DLL.
if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64" OR
   CMAKE_GENERATOR_PLATFORM MATCHES "[Aa][Rr][Mm]64")
  set(MODU_ORT_ARCH arm64)
else()
  set(MODU_ORT_ARCH x64)
endif()
include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/modu_onnxruntime_package.cmake")
set(MODU_ORT_NATIVE "${modu_ort_SOURCE_DIR}/runtimes/win-${MODU_ORT_ARCH}/native")
set(ONNXRUNTIME_ROOT_DIR "${modu_ort_SOURCE_DIR}" CACHE PATH "Modu ONNX runtime" FORCE)
set(ONNXRUNTIME_LIBRARY "${MODU_ORT_NATIVE}/onnxruntime.lib" CACHE FILEPATH "Modu ONNX library" FORCE)
set(ONNXRUNTIME_INCLUDE_DIR "${modu_ort_SOURCE_DIR}/build/native/include" CACHE PATH "Modu ONNX headers" FORCE)
set(USE_SYSTEM_ONNXRUNTIME ON CACHE BOOL "Use architecture-matched runtime" FORCE)
set(MODU_ONNXRUNTIME_DLL "${MODU_ORT_NATIVE}/onnxruntime.dll")
if(NOT EXISTS "${MODU_ONNXRUNTIME_DLL}" OR NOT EXISTS "${ONNXRUNTIME_LIBRARY}" OR
   NOT EXISTS "${ONNXRUNTIME_INCLUDE_DIR}/onnxruntime_cxx_api.h")
  message(FATAL_ERROR "Missing architecture-matched ONNX runtime")
endif()
