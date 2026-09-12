#include <cassert>
#include "../../third_party/flutter_inappwebview_windows/windows/types/javascript_handler_response.h"
#include "../../third_party/flutter_inappwebview_windows/windows/types/base_callback_result.h"

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

  // Exercise the same Flutter Success() -> BaseCallbackResult -> JS reply
  // chain as the symbolized crash, not just the conversion helper.
  BaseCallbackResult<const flutter::EncodableValue*> callback;
  callback.decodeResult = decodeJavaScriptHandlerResponse;
  std::string reply;
  callback.defaultBehaviour = [&](auto result) {
    reply = javaScriptHandlerResponseJson(result);
  };
  callback.Success();
  assert(reply == "null");
  callback.Success(null_value);
  assert(reply == "null");
  callback.Success(text);
  assert(reply == "{\"value\":42}");
  callback.Success(unexpected);
  assert(reply == "null");
  return 0;
}
