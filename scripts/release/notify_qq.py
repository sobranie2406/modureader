"""Announce a published release through the existing Worker with GitHub OIDC."""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

ENDPOINT = "https://modureader-bot.2406.fun/qq/release"
USER_AGENT = "ModuReader-GitHub-Release/1.0"


def main():
    identity_url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL", "")
    request_token = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN", "")
    if not identity_url or not request_token:
        raise RuntimeError("GitHub OIDC is unavailable; the job needs id-token: write")
    parts = urllib.parse.urlsplit(identity_url)
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query = [(key, value) for key, value in query if key != "audience"]
    query.append(("audience", ENDPOINT))
    identity_url = urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(query)))
    request = urllib.request.Request(identity_url, headers={
        "Authorization": "Bearer " + request_token,
        "User-Agent": USER_AGENT,
    })
    with urllib.request.urlopen(request, timeout=30) as response:
        identity = json.load(response)["value"]
    # Neither the short-lived identity nor the request credential is printed or stored.
    body = json.dumps({
        "release_tag": os.environ.get("RELEASE_TAG", "latest"),
        "test_notice": os.environ.get("QQ_TEST_NOTICE", "false").lower() == "true",
    }).encode("utf-8")
    request = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
        "Authorization": "Bearer " + identity,
        "Content-Type": "application/json",
        "User-Agent": USER_AGENT,
    })
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            result = json.load(response)
    except urllib.error.HTTPError as error:
        # Only the Worker's fixed error strings and numeric platform code are displayed.
        try:
            result = json.loads(error.read(4096))
        except (ValueError, TypeError):
            result = {}
        allowed = {"Proactive QQ permission not verified", "QQ release notices not configured",
                   "Prior send is still pending or uncertain", "QQ release notice failed",
                   "Published release unavailable", "Unauthorized", "Release is not published"}
        reason = result.get("error")
        reason = reason if reason in allowed else "Notification request failed"
        code = result.get("code")
        suffix = " (QQ code " + str(code) + ")" if isinstance(code, int) else ""
        raise RuntimeError(reason + suffix + "; HTTP " + str(error.code)) from None
    if not result.get("ok"):
        raise RuntimeError("QQ did not confirm the announcement")
    print("QQ release notice " + ("already delivered" if result.get("duplicate") else "delivered")
          + "; parts=" + str(result.get("parts", 0)))


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("QQ release notification could not complete; credentials are not logged", file=sys.stderr)
        sys.exit(1)
