// Windows desktop fallback. All methods run on the Flutter platform thread.
#pragma once
#include <sapi.h>
#include <wrl/client.h>
#include <winrt/base.h>
#include <cmath>
#include <cstdlib>
#include <string>
#include <vector>
#include "speech_policy.h"

class SapiSpeech {
 public:
  struct Voice {
    std::string name, locale, identifier, gender;
    Microsoft::WRL::ComPtr<ISpObjectToken> token;
  };

  bool ready() const { return voice_ != nullptr; }

  void Ensure(double volume, double rate) {
    if (voice_) return;
    Microsoft::WRL::ComPtr<ISpVoice> candidate;
    winrt::check_hresult(CoCreateInstance(CLSID_SpVoice, nullptr, CLSCTX_INPROC_SERVER,
                                         IID_PPV_ARGS(candidate.GetAddressOf())));
    // Queue end events; polling on our window avoids worker callbacks retaining
    // a destroyed plugin or invoking Flutter from a foreign thread.
    winrt::check_hresult(candidate->SetInterest(SPFEI(SPEI_END_INPUT_STREAM),
                                                SPFEI(SPEI_END_INPUT_STREAM)));
    winrt::check_hresult(candidate->SetVolume(static_cast<USHORT>(std::lround(volume * 100))));
    winrt::check_hresult(candidate->SetRate(static_cast<LONG>(modu_tts::SapiRate(rate))));
    voice_ = std::move(candidate);
  }

  void SetVolume(double value) { winrt::check_hresult(voice_->SetVolume(static_cast<USHORT>(std::lround(value * 100)))); }
  void SetRate(double value) { winrt::check_hresult(voice_->SetRate(static_cast<LONG>(modu_tts::SapiRate(value)))); }
  void Pause() { if (!paused_) { winrt::check_hresult(voice_->Pause()); paused_ = true; } }
  void Resume() { if (paused_) { winrt::check_hresult(voice_->Resume()); paused_ = false; } }

  void Speak(const std::string& text, double pitch) {
    Drain();
    // SAPI pitch uses XML. Escape the book text so markup is never interpreted
    // as commands (and ampersands/angle brackets remain readable).
    const auto wide = winrt::to_hstring(text);
    const auto xml = modu_tts::SapiXml(std::wstring_view(wide.c_str(), wide.size()), pitch);
    winrt::check_hresult(voice_->Speak(xml.c_str(), SPF_ASYNC | SPF_IS_XML | SPF_PARSE_SAPI, &stream_));
  }

  bool Finished() {
    if (!voice_ || paused_) return false;
    bool finished = false;
    SPEVENT event{};
    ULONG count = 0;
    while (true) {
      winrt::check_hresult(voice_->GetEvents(1, &event, &count));
      if (!count) break;
      if (event.eEventId == SPEI_END_INPUT_STREAM && event.ulStreamNum == stream_) finished = true;
      Clear(event);
    }
    if (finished) {
      SPVOICESTATUS status{};
      winrt::check_hresult(voice_->GetStatus(&status, nullptr));
      winrt::check_hresult(status.hrLastResult);
    }
    return finished;
  }

  void Stop() noexcept {
    if (!voice_) return;
    // Purge before resuming so paused, cancelled text is never briefly played.
    voice_->Speak(nullptr, SPF_ASYNC | SPF_PURGEBEFORESPEAK, nullptr);
    if (paused_) voice_->Resume();
    paused_ = false;
    stream_ = 0;
    Drain();
  }

  void Close() noexcept { Stop(); voice_.Reset(); }

  static std::vector<Voice> Voices() {
    Microsoft::WRL::ComPtr<ISpObjectTokenCategory> category;
    winrt::check_hresult(CoCreateInstance(CLSID_SpObjectTokenCategory, nullptr,
        CLSCTX_INPROC_SERVER, IID_PPV_ARGS(category.GetAddressOf())));
    winrt::check_hresult(category->SetId(SPCAT_VOICES, FALSE));
    Microsoft::WRL::ComPtr<IEnumSpObjectTokens> tokens;
    winrt::check_hresult(category->EnumTokens(nullptr, nullptr, tokens.GetAddressOf()));
    std::vector<Voice> output;
    while (true) {
      Voice item;
      ULONG count = 0;
      winrt::check_hresult(tokens->Next(1, item.token.GetAddressOf(), &count));
      if (!count) break;
      Microsoft::WRL::ComPtr<ISpDataKey> attributes;
      if (FAILED(item.token->OpenKey(L"Attributes", attributes.GetAddressOf()))) continue;
      item.name = Read(attributes.Get(), L"Name");
      item.gender = Read(attributes.Get(), L"Gender");
      const auto language = Read(attributes.Get(), L"Language");
      wchar_t locale[LOCALE_NAME_MAX_LENGTH]{};
      const auto lcid = static_cast<LCID>(std::strtoul(language.c_str(), nullptr, 16));
      if (!lcid || !LCIDToLocaleName(lcid, locale, LOCALE_NAME_MAX_LENGTH, 0)) continue;
      item.locale = winrt::to_string(locale);
      wchar_t* id = nullptr;
      if (SUCCEEDED(item.token->GetId(&id)) && id) {
        item.identifier = winrt::to_string(id);
        CoTaskMemFree(id);
      }
      output.push_back(std::move(item));
    }
    return output;
  }

  bool Select(const std::string& locale, const std::string& name, bool allow_locale_fallback) {
    auto voices = Voices();
    for (const auto& item : voices) {
      if ((locale.empty() || item.locale == locale) && (name.empty() || item.name == name)) {
        winrt::check_hresult(voice_->SetVoice(item.token.Get())); return true;
      }
    }
    // WinRT and SAPI display names differ; preserve the requested language when
    // migrating an existing selection instead of requiring the old voice name.
    if (allow_locale_fallback && !locale.empty() && !name.empty()) return Select(locale, "", false);
    return false;
  }

 private:
  Microsoft::WRL::ComPtr<ISpVoice> voice_;
  ULONG stream_ = 0;
  bool paused_ = false;

  static std::string Read(ISpDataKey* key, const wchar_t* name) {
    wchar_t* value = nullptr;
    if (FAILED(key->GetStringValue(name, &value)) || !value) return {};
    const auto result = winrt::to_string(value);
    CoTaskMemFree(value);
    return result;
  }
  static void Clear(const SPEVENT& event) noexcept {
    if (event.elParamType == SPET_LPARAM_IS_TOKEN || event.elParamType == SPET_LPARAM_IS_OBJECT) {
      if (event.lParam) reinterpret_cast<IUnknown*>(event.lParam)->Release();
    } else if (event.elParamType == SPET_LPARAM_IS_POINTER || event.elParamType == SPET_LPARAM_IS_STRING) {
      CoTaskMemFree(reinterpret_cast<void*>(event.lParam));
    }
  }
  void Drain() noexcept {
    if (!voice_) return;
    SPEVENT event{};
    ULONG count = 0;
    while (SUCCEEDED(voice_->GetEvents(1, &event, &count)) && count) Clear(event);
  }
};
