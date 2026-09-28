#!/bin/bash
set -euo pipefail
probe_source="$(cd "$(dirname "$0")" && pwd)"
probe_sdk="${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}"
probe_tools="$probe_sdk/build-tools/35.0.0"
probe_jar="$probe_sdk/platforms/android-35/android.jar"
probe_output="${1:?Pass an output directory}"
mkdir -p "$probe_output/classes" "$probe_output/dex"
javac -source 8 -target 8 -cp "$probe_jar" -d "$probe_output/classes" "$probe_source/ProbeReceiver.java" "$probe_source/ProbeActivity.java"
jar cf "$probe_output/classes.jar" -C "$probe_output/classes" .
"$probe_tools/d8" --lib "$probe_jar" --min-api 26 --output "$probe_output/dex" "$probe_output/classes.jar"
"$probe_tools/aapt" package -f -M "$probe_source/AndroidManifest.xml" -I "$probe_jar" -F "$probe_output/unsigned.apk"
(cd "$probe_output/dex" && "$probe_tools/aapt" add "$probe_output/unsigned.apk" classes.dex)
"$probe_tools/zipalign" -f 4 "$probe_output/unsigned.apk" "$probe_output/aligned.apk"
if [[ ! -f "$probe_output/probe.keystore" ]]; then
  keytool -genkeypair -keystore "$probe_output/probe.keystore" -storepass android -keypass android -alias probe -dname CN=ModuTestProbe -keyalg RSA -validity 30 -noprompt
fi
"$probe_tools/apksigner" sign --ks "$probe_output/probe.keystore" --ks-pass pass:android --out "$probe_output/sms-probe.apk" "$probe_output/aligned.apk"
