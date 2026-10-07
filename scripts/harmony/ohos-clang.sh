#!/usr/bin/env bash
# Rust linker / C compiler wrapper. Used on the Linux CI runner only.
set -euo pipefail
: "${OHOS_SDK_HOME:?Set the verified HarmonyOS SDK path}"
exec "$OHOS_SDK_HOME/native/llvm/bin/clang" \
  --target=aarch64-linux-ohos \
  --sysroot="$OHOS_SDK_HOME/native/sysroot" -D__MUSL__ "$@"
