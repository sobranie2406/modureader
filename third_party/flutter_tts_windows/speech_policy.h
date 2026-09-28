#pragma once
#include <cmath>
#include <string>
#include <string_view>

namespace modu_tts {
inline bool CanRetryWithSapi(bool using_sapi, bool audio_started, bool speaking) {
  return !using_sapi && !audio_started && speaking;
}
inline long SapiRate(double rate) {
  return static_cast<long>(std::lround((rate - 0.5) * 20));
}
inline std::wstring SapiXml(std::wstring_view text, double pitch) {
  std::wstring escaped;
  for (const auto ch : text) {
    if (ch == L'&') escaped += L"&amp;";
    else if (ch == L'<') escaped += L"&lt;";
    else if (ch == L'>') escaped += L"&gt;";
    // XML 1.0 forbids most control characters; ignore them instead of causing
    // a whole book paragraph to fail synthesis.
    else if (ch >= 0x20 || ch == L'\t' || ch == L'\n' || ch == L'\r') escaped += ch;
  }
  const auto amount = static_cast<int>(std::lround((pitch - 1.0) * 10));
  return L"<pitch absmiddle=\"" + std::to_wstring(amount) + L"\">" + escaped + L"</pitch>";
}
}  // namespace modu_tts
