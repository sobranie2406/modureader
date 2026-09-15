# Keep upstream managers/ABI, replace only the synchronous Windows dispatcher.
get_target_property(MODU_ORT_SOURCES flutter_onnxruntime_plugin SOURCES)
list(FILTER MODU_ORT_SOURCES EXCLUDE REGEX "(^|/)flutter_onnxruntime_plugin\\.cpp$")
set_property(TARGET flutter_onnxruntime_plugin PROPERTY SOURCES "${MODU_ORT_SOURCES}")
target_sources(flutter_onnxruntime_plugin PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/onnx/flutter_onnxruntime_plugin.cpp")
# This plugin already catches C++ exceptions, and the worker converts failures
# to replies. Do not compile its STL with exceptions disabled by app defaults.
get_target_property(MODU_ORT_DEFINITIONS flutter_onnxruntime_plugin COMPILE_DEFINITIONS)
list(REMOVE_ITEM MODU_ORT_DEFINITIONS "_HAS_EXCEPTIONS=0")
set_property(TARGET flutter_onnxruntime_plugin PROPERTY COMPILE_DEFINITIONS "${MODU_ORT_DEFINITIONS}")
