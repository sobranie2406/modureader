#pragma once

#include <dlfcn.h>
#include <wpe/webkit.h>

// Resolve this optional API at runtime so the same source supports WPE 2.48
// and newer releases. FALSE is the documented "no meta theme color" outcome;
// this does not change Modu's own reader colors, layout, or JavaScript bridge.
static inline gboolean modu_webkit_web_view_get_theme_color(
    WebKitWebView* view, WebKitColor* color) {
  using GetThemeColor = gboolean (*)(WebKitWebView*, WebKitColor*);
  static auto get_theme_color = reinterpret_cast<GetThemeColor>(
      dlsym(RTLD_DEFAULT, "webkit_web_view_get_theme_color"));
  return get_theme_color ? get_theme_color(view, color) : FALSE;
}

#define webkit_web_view_get_theme_color modu_webkit_web_view_get_theme_color
