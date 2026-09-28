// Windows-only adapter for the pinned flutter_tts method-channel protocol.
// No WinRT speech/media objects may be activated during plugin registration.
#include <windows.h>
#include <flutter_tts/flutter_tts_plugin.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.SpeechSynthesis.h>
#include <winrt/Windows.Storage.Streams.h>
#include <cmath>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <set>
#include <sstream>
#include "sapi_speech.h"

namespace {
using Value = flutter::EncodableValue;
using Result = std::unique_ptr<flutter::MethodResult<Value>>;
using Channel = flutter::MethodChannel<Value>;
using namespace winrt::Windows::Media::SpeechSynthesis;
using winrt::Windows::Media::Playback::MediaPlayer;
using Operation = winrt::Windows::Foundation::IAsyncOperation<SpeechSynthesisStream>;
constexpr UINT kDispatch = WM_APP + 117;
constexpr UINT_PTR kSapiTimer = 118;
constexpr char kUnavailable[] = "windows_tts_unavailable";

std::string ErrorMessage(int32_t code) {
  std::ostringstream out;
  out << "Windows 系统朗读不可用，请检查或安装系统语音包，也可切换 Edge、MiMo 等在线朗读。"
      << " / Windows speech unavailable; install a system voice or use online TTS. HRESULT=0x"
      << std::hex << static_cast<uint32_t>(code);
  return out.str();
}

struct SpeechState : std::enable_shared_from_this<SpeechState> {
  explicit SpeechState(flutter::BinaryMessenger* messenger)
      : channel(messenger, "flutter_tts", &flutter::StandardMethodCodec::GetInstance()) {}

  Channel channel;
  SpeechSynthesizer synth{nullptr};
  MediaPlayer player{nullptr};
  Operation operation{nullptr};
  SapiSpeech sapi;
  bool use_sapi = false;
  bool audio_started = false;
  std::string current_text, selected_locale, selected_name;
  winrt::event_token ended{};
  winrt::event_token failed{};
  Result pending;
  bool await_completion = false;
  bool speaking = false;
  bool paused = false;
  uint64_t generation = 0;
  double volume = 1.0, pitch = 1.0, rate = 0.5;
  std::mutex mutex;
  HWND dispatcher = nullptr;
  bool closed = false;
  std::deque<std::function<void()>> tasks;

  static LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    auto* state = reinterpret_cast<SpeechState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
      state = static_cast<SpeechState*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
      SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
    }
    if (message == kDispatch && state) {
      // COM calls while draining can pump messages/re-enter shutdown.
      const auto keep_alive = state->shared_from_this();
      keep_alive->Drain();
      return 0;
    }
    if (message == WM_TIMER && wp == kSapiTimer && state) {
      const auto keep_alive = state->shared_from_this();
      try {
        if (!state->closed && state->use_sapi && state->speaking && state->sapi.Finished()) {
          state->Complete(state->generation);
        }
      } catch (const winrt::hresult_error& e) { state->Fail(e.code().value); }
      catch (...) { state->Fail(E_FAIL); }
      return 0;
    }
    return DefWindowProcW(hwnd, message, wp, lp);
  }

  void CreateDispatcher() {
    WNDCLASSW wc{};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"ModuSystemTtsDispatcher";
    if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return;
    dispatcher = CreateWindowExW(0, wc.lpszClassName, L"", 0, 0, 0, 0, 0,
                                HWND_MESSAGE, nullptr, wc.hInstance, this);
  }

  // Media callbacks run on worker threads. Flutter messages/results must only
  // be delivered by the platform thread; queued callbacks hold weak references.
  void Post(std::function<void()> task) {
    std::lock_guard<std::mutex> lock(mutex);
    if (closed || !dispatcher) return;
    tasks.push_back(std::move(task));
    if (!PostMessageW(dispatcher, kDispatch, 0, 0)) tasks.pop_back();
  }

  void Drain() {
    std::deque<std::function<void()>> ready;
    {
      std::lock_guard<std::mutex> lock(mutex);
      if (closed) return;
      ready.swap(tasks);
    }
    for (auto& task : ready) {
      try { task(); }
      catch (const winrt::hresult_error& e) { Fail(e.code().value); }
      catch (...) { Fail(E_FAIL); }
    }
  }

  void Notify(const char* event) { channel.InvokeMethod(event, nullptr); }

  void ReleasePlayer() noexcept {
    if (!player) return;
    try { if (ended.value) player.MediaEnded(ended); } catch (...) {}
    try { if (failed.value) player.MediaFailed(failed); } catch (...) {}
    try { player.Close(); } catch (...) {}
    ended = {}; failed = {}; player = nullptr;
  }

  void CancelOperation() noexcept {
    if (operation) {
      try { operation.Cancel(); } catch (...) {}
      operation = nullptr;
    }
  }

  void StopSapi() noexcept {
    if (dispatcher) KillTimer(dispatcher, kSapiTimer);
    sapi.Stop();
  }

  void SwitchToSapi() {
    ++generation; // Invalidate any already queued WinRT completion/failure.
    CancelOperation();
    ReleasePlayer();
    if (synth) { try { synth.Close(); } catch (...) {} synth = nullptr; }
    use_sapi = true; // Remain on the working backend for this session.
    sapi.Ensure(volume, rate);
    if (!selected_locale.empty() || !selected_name.empty()) {
      sapi.Select(selected_locale, selected_name, true);
    }
  }

  void StartSapi(Result& result) {
    sapi.Ensure(volume, rate);
    if (!dispatcher || !SetTimer(dispatcher, kSapiTimer, 50, nullptr)) winrt::throw_hresult(E_FAIL);
    if (paused) sapi.Pause();
    sapi.Speak(current_text, pitch);
    speaking = true;
    audio_started = !paused;
    if (await_completion && result) pending = std::move(result);
    if (!paused) Notify("speak.onStart");
    if (result) result->Success(Value(1));
  }

  void SynthesisFailed(int32_t code) {
    // Only retry before any audio was started. A failure mid-playback must not
    // replay an already heard paragraph. Pending await completion is retained.
    if (modu_tts::CanRetryWithSapi(use_sapi, audio_started, speaking)) {
      try {
        SwitchToSapi();
        Result accepted;
        StartSapi(accepted);
        return;
      } catch (const winrt::hresult_error& e) { code = e.code().value; }
      catch (...) { code = E_FAIL; }
    }
    Fail(code);
  }

  void Stop(bool notify) {
    const bool was_active = speaking || paused;
    ++generation;
    speaking = false; paused = false;
    CancelOperation();
    ReleasePlayer();
    StopSapi();
    audio_started = false;
    auto result = std::move(pending);
    if (result) result->Success(Value(0));
    if (notify && was_active) Notify("speak.onCancel");
  }

  void Fail(int32_t code) {
    ++generation;
    speaking = false; paused = false;
    CancelOperation();
    ReleasePlayer();
    StopSapi();
    audio_started = false;
    auto result = std::move(pending);
    if (result) result->Error(kUnavailable, ErrorMessage(code));
    channel.InvokeMethod("speak.onError", std::make_unique<Value>(ErrorMessage(code)));
  }

  void Complete(uint64_t token) {
    if (token != generation || !speaking) return;
    ++generation;
    speaking = false; paused = false;
    operation = nullptr;
    ReleasePlayer();
    StopSapi();
    audio_started = false;
    auto result = std::move(pending);
    if (result) result->Success(Value(1));
    Notify("speak.onComplete");
  }

  void EnsureSynth() {
    if (synth) return;
    // Publish only a fully initialized engine; failure leaves it retryable.
    SpeechSynthesizer candidate;
    candidate.Options().AudioVolume(volume);
    candidate.Options().AudioPitch(pitch);
    candidate.Options().SpeakingRate(rate + 0.5);
    synth = std::move(candidate);
  }

  void Speak(const std::string& text, Result& result) {
    if (paused && use_sapi && sapi.ready()) {
      sapi.Resume(); paused = false; audio_started = true;
      Notify("speak.onContinue"); result->Success(Value(1)); return;
    }
    if (paused && player) {
      // Audio may still be synthesizing. The arrival callback will play it.
      if (player.Source()) { player.Play(); audio_started = true; }
      paused = false;
      Notify("speak.onContinue"); result->Success(Value(1)); return;
    }
    if (speaking) { result->Success(Value(0)); return; }
    if (!dispatcher) winrt::throw_hresult(E_FAIL);
    current_text = text;
    audio_started = false;
    if (use_sapi) { StartSapi(result); return; }
    try { StartWinrt(text, result); }
    catch (const winrt::hresult_error&) {
      if (audio_started) throw;
      SwitchToSapi();
      StartSapi(result);
    }
  }

  void StartWinrt(const std::string& text, Result& result) {
    EnsureSynth();
    player = MediaPlayer();
    const auto token = ++generation;
    const auto weak = weak_from_this();
    ended = player.MediaEnded([weak, token](const auto&, const auto&) {
      if (auto state = weak.lock()) state->Post([weak, token] {
        if (auto s = weak.lock()) s->Complete(token);
      });
    });
    failed = player.MediaFailed([weak, token](const auto&, const auto& args) {
      const auto code = args.ExtendedErrorCode().value;
      if (auto state = weak.lock()) state->Post([weak, token, code] {
        if (auto s = weak.lock(); s && token == s->generation) s->SynthesisFailed(code);
      });
    });
    operation = synth.SynthesizeTextToStreamAsync(winrt::to_hstring(text));
    speaking = true;
    // Register before returning success, but transfer ownership first so even
    // synchronously completed operations have exactly one reply owner.
    if (await_completion) pending = std::move(result);
    operation.Completed([weak, token](const Operation& op, auto) {
      try {
        auto stream = op.GetResults();
        if (auto state = weak.lock()) state->Post([weak, token, stream] {
          if (auto s = weak.lock(); s && token == s->generation) {
            try {
              s->player.Source(winrt::Windows::Media::Core::MediaSource::CreateFromStream(
                  stream, stream.ContentType()));
              // A pause received during synthesis must survive audio arrival.
              if (!s->paused) {
                s->player.Play();
                s->audio_started = true;
                s->Notify("speak.onStart");
              }
            } catch (const winrt::hresult_error& e) { s->SynthesisFailed(e.code().value); }
          }
        });
      } catch (const winrt::hresult_error& e) {
        const auto code = e.code().value;
        if (auto state = weak.lock()) state->Post([weak, token, code] {
          if (auto s = weak.lock(); s && token == s->generation) s->SynthesisFailed(code);
        });
      } catch (...) {
        if (auto state = weak.lock()) state->Post([weak, token] {
          if (auto s = weak.lock(); s && token == s->generation) s->SynthesisFailed(E_FAIL);
        });
      }
    });
    if (result) result->Success(Value(1));
  }

  void Shutdown() noexcept {
    HWND window;
    {
      std::lock_guard<std::mutex> lock(mutex);
      closed = true;
      window = dispatcher; dispatcher = nullptr; tasks.clear();
    }
    ++generation;
    CancelOperation();
    ReleasePlayer();
    if (window) KillTimer(window, kSapiTimer);
    sapi.Close();
    // Engine teardown: drop pending replies; never invoke a dead messenger.
    pending.reset();
    if (synth) { try { synth.Close(); } catch (...) {} synth = nullptr; }
    if (window) DestroyWindow(window);
  }

  void Handle(const flutter::MethodCall<Value>& call, Result& result) {
    try { HandleBackend(call, result); }
    catch (const winrt::hresult_error&) {
      const auto& method = call.method_name();
      // Speak owns its retry/async reply. Never replay pause/stop or a method
      // that has already replied; only backend setup/configuration is retried.
      const bool setup = method == "getVoices" || method == "getLanguages" ||
          method == "setVoice" || method == "setLanguage" || method == "setVolume" ||
          method == "setPitch" || method == "setSpeechRate";
      if (use_sapi || !setup || speaking || !result) throw;
      SwitchToSapi();
      HandleBackend(call, result);
    }
  }

  void HandleBackend(const flutter::MethodCall<Value>& call, Result& result) {
    const auto& method = call.method_name();
    const Value empty;
    const auto& arg = call.arguments() ? *call.arguments() : empty;
    if (method == "getPlatformVersion") { result->Success(Value(use_sapi ? "Windows SAPI" : "Windows WinRT")); return; }
    if (method == "awaitSpeakCompletion") {
      await_completion = std::get<bool>(arg); result->Success(Value(1)); return;
    }
    if (method == "stop") { Stop(true); result->Success(Value(1)); return; }
    if (method == "pause") {
      if (speaking && !paused) {
        if (use_sapi) sapi.Pause(); else if (player) player.Pause();
        paused = true; Notify("speak.onPause");
      }
      result->Success(Value(1)); return;
    }
    if (method == "speak") { Speak(std::get<std::string>(arg), result); return; }
    if (method == "setVolume" || method == "setPitch" || method == "setSpeechRate") {
      const auto* real = std::get_if<double>(&arg);
      const auto* integer = std::get_if<int32_t>(&arg);
      const double value = real ? *real : integer ? *integer : -1;
      const double max_value = method == "setPitch" ? 2.0 : 1.0;
      if (!std::isfinite(value) || value < 0 || value > max_value) {
        result->Error("invalid_argument", "Invalid speech option"); return;
      }
      if (method == "setVolume") { if (synth) synth.Options().AudioVolume(value); volume = value; }
      if (method == "setPitch") { if (synth) synth.Options().AudioPitch(value); pitch = value; }
      if (method == "setSpeechRate") { if (synth) synth.Options().SpeakingRate(value + 0.5); rate = value; }
      if (use_sapi && sapi.ready()) {
        if (method == "setVolume") sapi.SetVolume(volume);
        if (method == "setSpeechRate") sapi.SetRate(rate);
        // Pitch is applied to the next utterance's escaped SAPI XML.
      }
      result->Success(Value(1)); return;
    }
    if (method == "getVoices" || method == "getLanguages") {
      flutter::EncodableList voices;
      std::set<std::string> languages;
      if (use_sapi) {
        for (const auto& voice : SapiSpeech::Voices()) {
          languages.insert(voice.locale);
          voices.emplace_back(flutter::EncodableMap{
            {Value("name"), Value(voice.name)}, {Value("locale"), Value(voice.locale)},
            {Value("identifier"), Value(voice.identifier)}, {Value("gender"), Value(voice.gender)}
          });
        }
      } else {
        EnsureSynth();
        for (const auto& voice : SpeechSynthesizer::AllVoices()) {
          const auto locale = winrt::to_string(voice.Language());
          languages.insert(locale);
          voices.emplace_back(flutter::EncodableMap{
            {Value("name"), Value(winrt::to_string(voice.DisplayName()))},
            {Value("locale"), Value(locale)},
            {Value("identifier"), Value(winrt::to_string(voice.Id()))},
            {Value("gender"), Value(voice.Gender() == VoiceGender::Male ? "male" : "female")}
          });
        }
        if (voices.empty()) winrt::throw_hresult(HRESULT_FROM_WIN32(ERROR_NOT_FOUND));
      }
      if (method == "getLanguages") {
        voices.clear(); for (const auto& locale : languages) voices.emplace_back(locale);
      }
      result->Success(Value(voices)); return;
    }
    if (method == "setVoice" || method == "setLanguage") {
      std::string locale, name;
      if (method == "setLanguage") locale = std::get<std::string>(arg);
      else {
        const auto& info = std::get<flutter::EncodableMap>(arg);
        if (const auto it = info.find(Value("locale")); it != info.end()) locale = std::get<std::string>(it->second);
        if (const auto it = info.find(Value("name")); it != info.end()) name = std::get<std::string>(it->second);
      }
      selected_locale = locale; selected_name = name;
      if (use_sapi) {
        sapi.Ensure(volume, rate);
        result->Success(Value(sapi.Select(locale, name, true) ? 1 : 0)); return;
      }
      EnsureSynth();
      for (const auto& voice : SpeechSynthesizer::AllVoices()) {
        if (winrt::to_string(voice.Language()) == locale &&
            (method == "setLanguage" || winrt::to_string(voice.DisplayName()) == name)) {
          synth.Voice(voice); result->Success(Value(1)); return;
        }
      }
      result->Success(Value(0)); return;
    }
    result->NotImplemented();
  }
};

class FlutterTtsPlugin : public flutter::Plugin {
 public:
  explicit FlutterTtsPlugin(flutter::PluginRegistrarWindows* registrar)
      : state_(std::make_shared<SpeechState>(registrar->messenger())) {
    state_->CreateDispatcher();
    const std::weak_ptr<SpeechState> weak = state_;
    state_->channel.SetMethodCallHandler([weak](const auto& call, Result result) {
      const auto state = weak.lock();
      if (!state) { result->Error(kUnavailable, "Speech service closed"); return; }
      try { state->Handle(call, result); }
      catch (const winrt::hresult_error& e) {
        state->Fail(e.code().value);
        if (result) result->Error(kUnavailable, ErrorMessage(e.code().value));
      }
      catch (const std::exception&) {
        state->Fail(E_FAIL);
        if (result) result->Error(kUnavailable, ErrorMessage(E_FAIL));
      }
      catch (...) {
        state->Fail(E_FAIL);
        if (result) result->Error(kUnavailable, ErrorMessage(E_FAIL));
      }
    });
  }
  ~FlutterTtsPlugin() override {
    // Flutter can destroy plugins after stopping the messenger. The registered
    // callback only owns a weak reference; do not unregister via a dead engine.
    state_->Shutdown();
  }
 private:
  std::shared_ptr<SpeechState> state_;
};
}  // namespace

void FlutterTtsPluginRegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows->AddPlugin(std::make_unique<FlutterTtsPlugin>(windows));
}
