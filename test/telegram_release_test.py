"""Regression coverage for release content, limits and safe delivery errors."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/release/notify_telegram.py"
spec = importlib.util.spec_from_file_location("notify_telegram", SCRIPT)
notify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notify)
REPO = "sobranie2406/modureader"


class TelegramReleaseTest(unittest.TestCase):
    def release(self, **changes):
        return {"tag_name": "v1.2.1", "body": "Fixed a bug.",
                "draft": False, "prerelease": False, **changes}

    def test_bilingual_body_keeps_languages_warnings_and_links(self):
        body = "## English\nEnglish notes\n\n## 简体中文\n### 提醒\n**先备份**\n- 修复同步\n[源码](https://example.com/source)\n## French\nFrench notes"
        text = notify.release_notes(body)
        self.assertEqual(text, "English\nEnglish notes\n\n简体中文\n提醒\n先备份\n• 修复同步\n源码：https://example.com/source\nFrench\nFrench notes")

    def test_fallback_retains_available_notes(self):
        self.assertIn("English notes", notify.release_notes("## English\nEnglish notes"))
        self.assertIn("English notes", notify.release_notes("## English\nEnglish notes\n## 简体中文\n"))
        self.assertIn("未填写更新说明", notify.release_notes(None))

    def test_long_notes_preserve_all_content_and_unicode(self):
        body = "修复😀同步与阅读。\n" * 1000
        parts = notify.split_text(body, 301)
        self.assertEqual("".join(parts), body)
        self.assertTrue(all(notify.units(p) <= 301 for p in parts))
        for p in parts:
            p.encode("utf-8")

    def test_complete_messages_fit_and_include_exact_release_link(self):
        output = notify.messages(self.release(body="😀阅读修复\n" * 2000), REPO)
        self.assertGreater(len(output), 1)
        for index, message in enumerate(output, 1):
            self.assertLessEqual(notify.units(message["text"]), 4096)
            self.assertIn(f"（{index}/{len(output)}）", message["text"])
            self.assertIn(f"https://github.com/{REPO}/releases/tag/v1.2.1", message["text"])
            self.assertNotIn("parse_mode", message)

    def test_draft_rejected_and_prerelease_labelled(self):
        with self.assertRaisesRegex(RuntimeError, "draft"):
            notify.messages(self.release(draft=True), REPO)
        self.assertIn("预发布版", notify.messages(self.release(prerelease=True), REPO)[0]["text"])

    def test_payload_contains_channel_and_button(self):
        response = io.BytesIO(b'{"ok":true,"result":{"message_id":42}}')
        message = notify.messages(self.release(), REPO)[0]
        with patch.object(notify, "urlopen", return_value=response) as call:
            self.assertEqual(notify.send_message("123:secret", "-1004343451406", message), 42)
        payload = json.loads(call.call_args.args[0].data)
        self.assertEqual(payload["chat_id"], "-1004343451406")
        self.assertEqual(payload["reply_markup"]["inline_keyboard"][0][0]["url"],
                         f"https://github.com/{REPO}/releases/tag/v1.2.1")

    def test_timeout_not_retried_and_credentials_not_logged(self):
        with patch.object(notify, "urlopen", side_effect=URLError("123:secret")) as call:
            with self.assertRaises(RuntimeError) as error:
                notify.send_message("123:secret", "-1004343451406", {"text": "test"})
        self.assertEqual(call.call_count, 1)
        self.assertNotIn("secret", str(error.exception))

    def test_rate_limit_retries_explicit_rejection(self):
        rejected = HTTPError("https://example.com", 429, "limited", {},
                             io.BytesIO(b'{"parameters":{"retry_after":3}}'))
        response = io.BytesIO(b'{"ok":true,"result":{"message_id":43}}')
        with patch.object(notify, "urlopen", side_effect=[rejected, response]) as call, \
                patch.object(notify.time, "sleep") as sleep:
            self.assertEqual(notify.send_message("123:secret", "-1004343451406", {"text": "test"}), 43)
        self.assertEqual(call.call_count, 2)
        sleep.assert_called_once_with(3)

    def test_permission_error_is_safe_and_not_retried(self):
        rejected = HTTPError("https://api.telegram.org/bot123:secret/sendMessage", 403, "secret", {}, None)
        with patch.object(notify, "urlopen", side_effect=rejected) as call:
            with self.assertRaisesRegex(RuntimeError, "HTTP 403") as error:
                notify.send_message("123:secret", "-1004343451406", {"text": "test"})
        self.assertEqual(call.call_count, 1)
        self.assertNotIn("secret", str(error.exception))

    def test_tag_is_url_encoded_and_does_not_execute_code(self):
        response = io.BytesIO(b'{"tag_name":"v1.2.1"}')
        with patch.object(notify, "urlopen", return_value=response) as call:
            notify.fetch_release(REPO, 'v1/$(touch file)', "read-token")
        self.assertTrue(call.call_args.args[0].full_url.endswith("tags/v1%2F%24%28touch%20file%29"))


if __name__ == "__main__":
    unittest.main()
