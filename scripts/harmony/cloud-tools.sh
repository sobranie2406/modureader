#!/usr/bin/env bash
# CI only: no global PATH changes, no local SDK install, no license auto-accept.
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Run only on GitHub Actions.' >&2; exit 1; }
[[ "${RUNNER_OS:-}" == Linux && "${RUNNER_ARCH:-}" == X64 ]] || exit 1
[[ "${HARMONY_TOOLS_LICENSE_ACCEPTED:-}" == true ]] || {
  echo 'A repository owner must first review/accept the Huawei tools license.' >&2; exit 1;
}
[[ "${HARMONY_TOOLS_SHA256:-}" =~ ^[0-9a-fA-F]{64}$ ]] || {
  echo 'Configure HARMONY_LINUX_TOOLS_SHA256 from the official download page.' >&2; exit 1;
}
[[ "${HARMONY_TOOLS_URL:-}" == https://* ]] || {
  echo 'Configure HARMONY_LINUX_TOOLS_URL with the authorized official Linux x64 ZIP URL.' >&2; exit 1;
}
: "${RUNNER_TEMP:?}" "${GITHUB_PATH:?}" "${GITHUB_ENV:?}"
tools_dir=$(mktemp -d "$RUNNER_TEMP/harmony-tools.XXXXXX")
# URL may contain an expiring download token. Do not echo it or enable xtrace.
if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
  --connect-timeout 30 --max-time 1800 --retry 2 \
  "$HARMONY_TOOLS_URL" -o "$tools_dir/tools.zip.part"; then
  echo 'Huawei tools download failed. Renew an expired authorized URL; no SDK was installed.' >&2
  exit 1
fi
python3 "$(dirname "$0")/verify_tools.py" "$tools_dir/tools.zip.part" "$HARMONY_TOOLS_SHA256"
mv "$tools_dir/tools.zip.part" "$tools_dir/tools.zip"
unzip -q "$tools_dir/tools.zip" -d "$tools_dir/extracted"
mapfile -t tool_roots < <(find "$tools_dir/extracted" -type d -path '*/sdk/default/openharmony')
[[ ${#tool_roots[@]} == 1 ]] || {
  echo 'Expected one SDK in the official Command Line Tools ZIP; check archive/version.' >&2; exit 1;
}
ohos_sdk=${tool_roots[0]}
tool_root=${ohos_sdk%/sdk/default/openharmony}
# Current official packages expose wrappers in bin/. Older packages may expose
# the component directories instead. Never fall through to host-installed tools.
if [[ -x "$tool_root/bin/ohpm" && -x "$tool_root/bin/hvigorw" ]]; then
  tool_bins=("$tool_root/bin")
elif [[ -x "$tool_root/ohpm/bin/ohpm" && -x "$tool_root/hvigor/bin/hvigorw" ]]; then
  tool_bins=("$tool_root/ohpm/bin" "$tool_root/hvigor/bin")
else
  echo 'Missing bundled OHPM/Hvigor wrappers; review the official archive layout.' >&2
  exit 1
fi
if [[ -x "$tool_root/tool/node/bin/node" ]]; then
  node_home="$tool_root/tool/node"
elif [[ -x "$tool_root/node/bin/node" ]]; then
  node_home="$tool_root/node"
else
  echo 'Missing bundled Node.' >&2
  exit 1
fi
[[ -x "$ohos_sdk/toolchains/hdc" ]] || { echo 'Missing HDC.' >&2; exit 1; }
printf '%s\n' "$node_home/bin" "${tool_bins[@]}" "$ohos_sdk/toolchains" >> "$GITHUB_PATH"
printf 'DEVECO_NODE_HOME=%s\n' "$node_home" >> "$GITHUB_ENV"
printf 'NODE_HOME=%s\n' "$node_home" >> "$GITHUB_ENV"
printf 'DEVECO_SDK_HOME=%s\nHOS_SDK_HOME=%s\nOHOS_SDK_HOME=%s\nMODU_HARMONY_SDK=%s\n' \
  "$tool_root/sdk" "$tool_root/sdk" "$ohos_sdk" "$ohos_sdk" >> "$GITHUB_ENV"
if [[ -x "$tool_root/jbr/bin/java" ]]; then
  printf 'JAVA_HOME=%s\n' "$tool_root/jbr" >> "$GITHUB_ENV"
  printf '%s\n' "$tool_root/jbr/bin" >> "$GITHUB_PATH"
fi
