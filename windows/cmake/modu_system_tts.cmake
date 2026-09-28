# Keep flutter_tts's pinned Dart/mobile implementations and WinRT build setup,
# but replace its eager, unguarded Windows implementation with our adapter.
if(NOT TARGET flutter_tts_plugin)
  message(FATAL_ERROR "Expected pinned flutter_tts_plugin target")
endif()
get_target_property(MODU_TTS_SOURCE_DIR flutter_tts_plugin SOURCE_DIR)
set_property(TARGET flutter_tts_plugin PROPERTY SOURCES
  "${CMAKE_CURRENT_LIST_DIR}/../../third_party/flutter_tts_windows/flutter_tts_plugin.cpp")
target_include_directories(flutter_tts_plugin PRIVATE "${MODU_TTS_SOURCE_DIR}/include")
get_target_property(MODU_TTS_DEFINITIONS flutter_tts_plugin COMPILE_DEFINITIONS)
list(FILTER MODU_TTS_DEFINITIONS EXCLUDE REGEX "^_HAS_EXCEPTIONS=")
set_property(TARGET flutter_tts_plugin PROPERTY COMPILE_DEFINITIONS ${MODU_TTS_DEFINITIONS})
target_compile_definitions(flutter_tts_plugin PRIVATE _HAS_EXCEPTIONS=1)
target_compile_options(flutter_tts_plugin PRIVATE /utf-8)
target_link_libraries(flutter_tts_plugin PRIVATE sapi ole32 oleaut32)
