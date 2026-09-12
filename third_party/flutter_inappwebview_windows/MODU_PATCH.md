# Windows JavaScript callback null-result fix

Upstream: https://github.com/pichillilorenzo/flutter_inappwebview
Package: flutter_inappwebview_windows 0.7.0-beta.3, Apache-2.0.
Original package SHA-256: 902edd6f6326952af822e21aa928f7426d723d45c94c15e6ce3c2d5640d28ad7.
Original LICENSE is retained. Only the Windows package is overridden.

Modu's isolated native EPUB test reproduced an access violation. Matching DLL/PDB
symbolization identified `InAppWebView::onWebMessageReceived`'s JS reply callback
(upstream in_app_webview.cpp line 4091), calling `EncodableValue::IsNull()` on a
null pointer from Flutter `MethodResult::Success()`.

`optional<const EncodableValue*>` can be engaged while containing nullptr.
Normalize null method-channel replies to nullopt and use a defensive JSON result
helper for missing, null and unexpected result types. Valid JSON string replies
retain their original behavior. No Dart API or other platform is changed.

Regression: test/native/WindowsJsHandlerResponseTest.cpp and the Windows native
EPUB/TXT/PDF integration test. The test includes the patched production helper.
