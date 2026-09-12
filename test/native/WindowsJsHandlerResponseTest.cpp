#include <cassert>
#include "../../third_party/flutter_inappwebview_windows/windows/types/javascript_handler_response.h"

using namespace flutter_inappwebview_plugin;

int main() {
  // The exact native-crash case: engaged optional holding a null pointer.
  std::optional<const flutter::EncodableValue*> empty_pointer = nullptr;
  assert(empty_pointer.has_value());
  assert(javaScriptHandlerResponseJson(empty_pointer) == "null");
  assert(javaScriptHandlerResponseJson(std::nullopt) == "null");
  assert(!decodeJavaScriptHandlerResponse(nullptr).has_value());
  const flutter::EncodableValue null_value;
  assert(!decodeJavaScriptHandlerResponse(&null_value).has_value());
  assert(javaScriptHandlerResponseJson(&null_value) == "null");
  const flutter::EncodableValue text(std::string("{\"value\":42}"));
  assert(javaScriptHandlerResponseJson(decodeJavaScriptHandlerResponse(&text)) == "{\"value\":42}");
  const flutter::EncodableValue unexpected(42);
  assert(javaScriptHandlerResponseJson(&unexpected) == "null");
  return 0;
}
