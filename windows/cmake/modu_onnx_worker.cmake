# Keep upstream managers/ABI, replace only the synchronous Windows dispatcher.
get_target_property(MODU_ORT_SOURCES flutter_onnxruntime_plugin SOURCES)
list(FILTER MODU_ORT_SOURCES EXCLUDE REGEX "(^|/)flutter_onnxruntime_plugin\\.cpp$")
set_property(TARGET flutter_onnxruntime_plugin PROPERTY SOURCES "${MODU_ORT_SOURCES}")
target_sources(flutter_onnxruntime_plugin PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/onnx/flutter_onnxruntime_plugin.cpp")
# Source files are UTF-8; without this MSVC decodes them in the active code page
# (936 on zh-CN systems) and C4819 fires, which /WX turns into an error. Keep this
# target-scoped rather than in APPLY_STANDARD_SETTINGS: it changes how every
# literal in a target is decoded, and the app's own sources are pure ASCII.
target_compile_options(flutter_onnxruntime_plugin PRIVATE "$<$<CXX_COMPILER_ID:MSVC>:/utf-8>")
# This plugin already catches C++ exceptions, and the worker converts failures
# to replies. Do not compile its STL with exceptions disabled by app defaults.
get_target_property(MODU_ORT_DEFINITIONS flutter_onnxruntime_plugin COMPILE_DEFINITIONS)
list(REMOVE_ITEM MODU_ORT_DEFINITIONS "_HAS_EXCEPTIONS=0")
set_property(TARGET flutter_onnxruntime_plugin PROPERTY COMPILE_DEFINITIONS "${MODU_ORT_DEFINITIONS}")
