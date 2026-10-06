#!/usr/bin/env python3
"""Send a published Modu release to its Telegram channel using only stdlib."""

import json
import os
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

MAX_UNITS = 3800  # Leave headroom below Telegram's 4096-character limit.


def units(text):
    return len(text.encode("utf-16-le")) // 2


def release_notes(body):
    """Retain the complete bilingual body in its published order."""
    lines = (body or "").splitlines()
    text = "\n".join(lines).strip()
    text = re.sub(r"!\[([^\]]*)\]\((https?://[^\s)]+)\)", r"\1 (\2)", text)
    text = re.sub(r"\[([^\]]+)\]\((https?://[^\s)]+)\)", r"\1：\2", text)
    text = re.sub(r"(?m)^#{1,6}\s+", "", text)
    text = re.sub(r"(?m)^\s*[-*+]\s+", "• ", text)
    text = re.sub(r"\*\*([^\n]+?)\*\*", r"\1", text)
    text = re.sub(r"`([^`\n]+)`", r"\1", text)
    return text or "No release notes provided. / 此版本未填写更新说明，请查看 Release 页面。"


def split_text(text, limit):
    """Split without dropping characters, preferring complete paragraphs/lines."""
    result = []
    while units(text) > limit:
        count, end = 0, 0
        for end, character in enumerate(text):
            count += units(character)
            if count > limit:
                break
        boundary = text.rfind("\n", 0, end)
        cut = boundary + 1 if boundary >= end // 2 else end
        result.append(text[:cut])
        text = text[cut:]
    if text:
        result.append(text)
    return result


def messages(release, repository):
    if release.get("draft"):
        raise RuntimeError("Refusing to announce a draft release")
    tag = release["tag_name"]
    url = f"https://github.com/{repository}/releases/tag/{quote(tag, safe='')}"
    status = "Prerelease / 预发布版" if release.get("prerelease") else "Stable / 正式版"
    title = f"📚 ModuReader {tag} · {status}"
    footer = f"\n\nRelease / 下载：\n{url}"
    budget = MAX_UNITS - units(title + "（999/999）\n\n" + footer)
    if budget < 500:
        raise RuntimeError("Release tag is too long")
    parts = split_text(release_notes(release.get("body")), budget)
    return [{"text": title + (f"（{i}/{len(parts)}）" if len(parts) > 1 else "")
             + "\n\n" + part + footer,
             "link_preview_options": {"is_disabled": True},
             "reply_markup": {"inline_keyboard": [[{"text": "Release / Download · 下载", "url": url}]]}}
            for i, part in enumerate(parts, 1)]


def fetch_release(repository, tag, github_token):
    path = "latest" if tag == "latest" else "tags/" + quote(tag, safe="")
    request = Request(f"https://api.github.com/repos/{repository}/releases/{path}",
                      headers={"Accept": "application/vnd.github+json",
                               "Authorization": f"Bearer {github_token}",
                               "User-Agent": "ModuReader-release-notifier"})
    try:
        with urlopen(request, timeout=30) as response:
            return json.load(response)
    except HTTPError as error:
        raise RuntimeError(f"GitHub release lookup failed (HTTP {error.code})") from None
    except (URLError, TimeoutError, ValueError):
        raise RuntimeError("GitHub release lookup failed") from None


def send_message(token, chat_id, message):
    payload = {"chat_id": chat_id, **message}
    request = Request(f"https://api.telegram.org/bot{token}/sendMessage",
                      data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                      headers={"Content-Type": "application/json"}, method="POST")
    # Retry only explicit rate-limit rejection, never an ambiguous delivery timeout.
    for attempt in range(3):
        try:
            with urlopen(request, timeout=30) as response:
                result = json.load(response)
            if not result.get("ok"):
                raise RuntimeError("Telegram rejected the announcement")
            return result["result"]["message_id"]
        except HTTPError as error:
            if error.code == 429 and attempt < 2:
                try:
                    delay = int(json.load(error).get("parameters", {}).get("retry_after", 2))
                except (ValueError, TypeError):
                    delay = 2
                time.sleep(min(max(delay, 1), 60))
                continue
            raise RuntimeError(f"Telegram send failed (HTTP {error.code}); check the bot's channel posting permission") from None
        except (URLError, TimeoutError, ValueError):
            raise RuntimeError("Telegram send failed; check the channel before retrying to avoid duplicates") from None


def main():
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if repository != "sobranie2406/modureader":
        raise RuntimeError("This notifier is restricted to sobranie2406/modureader")
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    if not re.fullmatch(r"\d+:[A-Za-z0-9_-]+", token):
        raise RuntimeError("Configure the TELEGRAM_BOT_TOKEN repository Actions secret")
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "")
    if chat_id != "-1004343451406":
        raise RuntimeError("This notifier is restricted to the ModuReader channel")
    github_token = os.environ.get("GH_TOKEN", "")
    if not github_token:
        raise RuntimeError("Missing GitHub read token")
    release = fetch_release(repository, os.environ.get("RELEASE_TAG", "latest"), github_token)
    for index, message in enumerate(messages(release, repository), 1):
        if index > 1:
            time.sleep(1)
        message_id = send_message(token, chat_id, message)
        print(f"Sent release announcement part {index}; Telegram message ID {message_id}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, KeyError) as error:
        # Never print request objects, URLs containing tokens, or raw API errors.
        print(f"Release announcement failed: {error}", file=sys.stderr)
        sys.exit(1)
