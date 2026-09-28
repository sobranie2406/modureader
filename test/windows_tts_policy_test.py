"""Compile/run the shared C++ fallback policy, without Windows/Flutter mocks.

This tests actual production policy helpers, not native SAPI playback.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

PROGRAM = r'''
#include "speech_policy.h"
#include <cassert>
#include <string>
int main(int argc, char** argv) {
  assert(argc == 2);
  using namespace modu_tts;
  const std::string mode = argv[1];
  if (mode == "retry") {
    for (bool sapi : {false, true})
      for (bool started : {false, true})
        for (bool speaking : {false, true})
          assert(CanRetryWithSapi(sapi, started, speaking) == (!sapi && !started && speaking));
  } else if (mode == "rate") {
    assert(SapiRate(0) == -10);
    assert(SapiRate(0.5) == 0);
    assert(SapiRate(1) == 10);
    long previous = -10;
    for (int i = 0; i <= 100; i++) {
      const auto value = SapiRate(i / 100.0);
      assert(value >= previous && value >= -10 && value <= 10);
      previous = value;
    }
  } else if (mode == "pitch") {
    assert(SapiXml(L"正文", 0) == L"<pitch absmiddle=\"-10\">正文</pitch>");
    assert(SapiXml(L"正文", 1) == L"<pitch absmiddle=\"0\">正文</pitch>");
    assert(SapiXml(L"正文", 2) == L"<pitch absmiddle=\"10\">正文</pitch>");
  } else if (mode == "xml") {
    assert(SapiXml(L"<rate speed='10'>A&B</rate>", 1) ==
      L"<pitch absmiddle=\"0\">&lt;rate speed='10'&gt;A&amp;B&lt;/rate&gt;</pitch>");
  } else if (mode == "unicode") {
    assert(SapiXml(L"中文、English，😀\n下一行\t\r", 1) ==
      L"<pitch absmiddle=\"0\">中文、English，😀\n下一行\t\r</pitch>");
  } else if (mode == "controls") {
    assert(SapiXml(std::wstring_view(L"A\0B\x01 C", 7), 1) ==
      L"<pitch absmiddle=\"0\">AB C</pitch>");
  } else { return 2; }
}
'''


class WindowsTtsPolicyTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('clang++') or shutil.which('g++')
        if not compiler:
            raise unittest.SkipTest('C++ compiler unavailable')
        cls.temp = tempfile.TemporaryDirectory(prefix='modu-tts-policy-')
        cls.addClassCleanup(cls.temp.cleanup)
        source = Path(cls.temp.name) / 'policy_test.cpp'
        source.write_text(PROGRAM)
        cls.binary = Path(cls.temp.name) / 'policy_test'
        subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                        '-I', str(ROOT / 'third_party/flutter_tts_windows'),
                        str(source), '-o', str(cls.binary)], check=True,
                       capture_output=True, text=True)

    def check_case(self, name):
        subprocess.run([str(self.binary), name], check=True, capture_output=True)

    def test_retry_gate(self): self.check_case('retry')
    def test_rate_range_and_neutral(self): self.check_case('rate')
    def test_pitch_range_and_neutral(self): self.check_case('pitch')
    def test_book_markup_is_not_executed(self): self.check_case('xml')
    def test_chinese_english_and_emoji_preserved(self): self.check_case('unicode')
    def test_illegal_xml_controls_filtered(self): self.check_case('controls')


if __name__ == '__main__':
    unittest.main()
