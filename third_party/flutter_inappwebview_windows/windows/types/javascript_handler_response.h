// Modu patch to flutter_inappwebview_windows 0.7.0-beta.3 (Apache-2.0).
#ifndef FLUTTER_INAPPWEBVIEW_JAVASCRIPT_HANDLER_RESPONSE_H_
#define FLUTTER_INAPPWEBVIEW_JAVASCRIPT_HANDLER_RESPONSE_H_

#include <flutter/encodable_value.h>
#include <optional>
#include <string>

namespace flutter_inappwebview_plugin {
inline std::optional<const flutter::EncodableValue*> decodeJavaScriptHandlerResponse(
    const flutter::EncodableValue* value) {
  // Flutter's Success() passes nullptr for a null method-channel result.
  // optional<T*> constructed from nullptr still has_value() == true.
  if (!value || value->IsNull()) return std::nullopt;
  return value;
}

inline std::string javaScriptHandlerResponseJson(
    std::optional<const flutter::EncodableValue*> response) {
  const auto* value = response.value_or(nullptr);
  if (!value) return "null";
  const auto* json = std::get_if<std::string>(value);
  // A missing JS handler has no JSON string result. Unexpected result types
  // must not escape the platform callback as a bad_variant_access either.
  return json ? *json : "null";
}
}  // namespace flutter_inappwebview_plugin
#endif
