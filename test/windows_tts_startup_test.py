"""Windows build/lifecycle source guards, not a substitute for native execution."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'third_party/flutter_tts_windows/flutter_tts_plugin.cpp'


class WindowsTtsStartupTest(unittest.TestCase):
    def setUp(self):
        self.source = SOURCE.read_text()

    def test_speech_stream_content_type_has_full_winrt_projection(self):
        # SpeechSynthesisStream inherits IContentTypeProvider. Its auto-return
        # method needs the Streams projection definition, not just declarations.
        self.assertIn('#include <winrt/Windows.Storage.Streams.h>', self.source)
        self.assertIn('stream.ContentType()', self.source)

    def test_build_uses_local_windows_adapter_after_plugin_target_exists(self):
        cmake = (ROOT / 'windows/CMakeLists.txt').read_text()
        self.assertLess(cmake.index('include(flutter/generated_plugins.cmake)'),
                        cmake.index('include(cmake/modu_system_tts.cmake)'))
        patch = (ROOT / 'windows/cmake/modu_system_tts.cmake').read_text()
        self.assertIn('PROPERTY SOURCES', patch)
        self.assertIn('third_party/flutter_tts_windows/flutter_tts_plugin.cpp', patch)
        self.assertIn('_HAS_EXCEPTIONS=1', patch)
        self.assertIn('/utf-8', patch)
        self.assertIn('PRIVATE sapi ole32 oleaut32', patch)
        # Other platforms keep exactly the pinned upstream dependency.
        self.assertIn('ref: ad4a10bb4977031a1e60fd8027fb62b932d635ce',
                      (ROOT / 'pubspec.yaml').read_text())

    def test_registration_does_not_activate_speech_or_media(self):
        self.assertIn('SpeechSynthesizer synth{nullptr}', self.source)
        self.assertIn('MediaPlayer player{nullptr}', self.source)
        constructor = self.source.split('explicit SpeechState(', 1)[1].split('Channel channel;', 1)[0]
        registration = self.source.split('class FlutterTtsPlugin :', 1)[1]
        for code in [constructor, registration]:
            self.assertNotIn('EnsureSynth()', code)
            self.assertNotIn('SpeechSynthesizer()', code)
            self.assertNotIn('MediaPlayer()', code)
            self.assertNotIn('sapi.Ensure(', code)
            self.assertNotIn('SwitchToSapi()', code)

    def test_options_and_stop_do_not_activate_engine(self):
        stop = self.source.split('void Stop(', 1)[1].split('void Fail(', 1)[0]
        self.assertNotIn('EnsureSynth()', stop)
        self.assertNotIn('MediaPlayer()', stop)
        options = self.source.split('const double max_value', 1)[1].split('if (method == "getVoices"', 1)[0]
        self.assertNotIn('EnsureSynth()', options)

    def test_all_method_calls_have_native_exception_boundary(self):
        self.assertIn('try { state->Handle(call, result); }', self.source)
        self.assertIn('catch (const winrt::hresult_error& e)', self.source)
        self.assertIn('catch (const std::exception&)', self.source)
        self.assertIn('result->Error(kUnavailable', self.source)

    def test_async_results_marshalled_and_stale_callbacks_ignored(self):
        callbacks = self.source.split('ended = player.MediaEnded', 1)[1].split('void Shutdown()', 1)[0]
        self.assertNotIn('[this', callbacks)
        self.assertIn('state->Post(', callbacks)
        self.assertIn('token == s->generation', callbacks)
        self.assertIn('op.GetResults()', callbacks)
        self.assertIn('if (!s->paused)', callbacks)
        self.assertIn('catch (const winrt::hresult_error& e)', callbacks)
        self.assertLess(callbacks.index('pending = std::move(result)'),
                        callbacks.index('operation.Completed('))

    def test_shutdown_cancels_revokes_and_never_calls_dead_messenger(self):
        close = self.source.split('void Shutdown()', 1)[1].split('void Handle(', 1)[0]
        self.assertIn('closed = true', close)
        self.assertIn('tasks.clear()', close)
        self.assertIn('CancelOperation()', close)
        self.assertIn('ReleasePlayer()', close)
        self.assertIn('pending.reset()', close)
        self.assertNotIn('Notify(', close)
        self.assertNotIn('result->', close)
        destructor = self.source.split('~FlutterTtsPlugin()', 1)[1]
        self.assertNotIn('SetMethodCallHandler', destructor)
        self.assertIn('player.MediaEnded(ended)', self.source)
        self.assertIn('player.MediaFailed(failed)', self.source)

    def test_sapi_only_retries_before_audio_and_keeps_await_reply(self):
        retry = self.source.split('void SynthesisFailed(', 1)[1].split('void Stop(', 1)[0]
        self.assertIn('CanRetryWithSapi(use_sapi, audio_started, speaking)', retry)
        self.assertIn('StartSapi(accepted)', retry)
        self.assertNotIn('pending.reset', retry)
        self.assertNotIn('std::move(pending)', retry)
        switch = self.source.split('void SwitchToSapi()', 1)[1].split('void StartSapi', 1)[0]
        for token in ['++generation', 'CancelOperation()', 'ReleasePlayer()', 'use_sapi = true']:
            self.assertIn(token, switch)

    def test_sapi_completion_is_stream_matched_on_platform_thread(self):
        sapi = (SOURCE.parent / 'sapi_speech.h').read_text()
        self.assertIn('WM_TIMER', self.source)
        self.assertIn('state->sapi.Finished()', self.source)
        self.assertIn('SPEI_END_INPUT_STREAM && event.ulStreamNum == stream_', sapi)
        self.assertIn('if (!voice_ || paused_) return false', sapi)
        self.assertIn('winrt::check_hresult(status.hrLastResult)', sapi)
        self.assertNotIn('RegisterWaitForSingleObject', sapi)
        self.assertNotIn('InvokeMethod', sapi)

    def test_sapi_pause_is_preserved_during_fallback(self):
        start = self.source.split('void StartSapi(', 1)[1].split('void SynthesisFailed', 1)[0]
        self.assertLess(start.index('if (paused) sapi.Pause()'), start.index('sapi.Speak('))
        self.assertIn('if (!paused) Notify', start)
        self.assertIn('sapi.Resume(); paused = false', self.source)

    def test_sapi_stop_and_shutdown_remove_timer_and_purge_audio(self):
        sapi = (SOURCE.parent / 'sapi_speech.h').read_text()
        self.assertIn('SPF_ASYNC | SPF_PURGEBEFORESPEAK', sapi)
        stop = sapi.split('void Stop()', 1)[1].split('void Close()', 1)[0]
        self.assertLess(stop.index('SPF_PURGEBEFORESPEAK'), stop.index('voice_->Resume()'))
        close = self.source.split('void Shutdown()', 1)[1].split('void Handle(', 1)[0]
        self.assertIn('KillTimer(window, kSapiTimer)', close)
        self.assertIn('sapi.Close()', close)

    def test_sapi_voice_selection_and_options_are_wired(self):
        sapi = (SOURCE.parent / 'sapi_speech.h').read_text()
        for token in ['CLSID_SpVoice', 'CLSID_SpObjectTokenCategory', 'SPCAT_VOICES',
                      'LCIDToLocaleName', 'SetVoice(item.token.Get())', 'SapiXml',
                      'SetVolume', 'SetRate', 'SPF_IS_XML | SPF_PARSE_SAPI']:
            self.assertIn(token, sapi)
        self.assertIn('SapiSpeech::Voices()', self.source)
        self.assertIn('sapi.Select(locale, name, true)', self.source)

    def test_method_fallback_does_not_repeat_speak_stop_or_pause(self):
        retry = self.source.split('void Handle(', 1)[1].split('void HandleBackend(', 1)[0]
        self.assertIn('if (use_sapi || !setup || speaking || !result) throw', retry)
        for method in ['speak', 'stop', 'pause']:
            self.assertNotIn('method == "' + method + '"', retry)


if __name__ == '__main__':
    unittest.main()
