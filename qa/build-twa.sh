#!/usr/bin/env bash
# Builds a debug-signed TWA from Ten10's twa-manifest.json (copied in qa/twa-manifest.ten10.json),
# re-pointed at the preview host. No secret goes into the APK.
set -euo pipefail
H="$PREVIEW_HOST"
mkdir -p twa && cp qa/assets/icon-512.png twa/icon.png
curl -fsS -H "x-vercel-protection-bypass: $BYPASS" "https://$H/manifest.json" -o twa/manifest.json
(cd twa && python3 -m http.server 8765 >/dev/null 2>&1 &)
sleep 1
jq --arg h "$H" '.host=$h | .startUrl="/?twa=true" | .iconUrl="http://127.0.0.1:8765/icon.png" | .maskableIconUrl="http://127.0.0.1:8765/icon.png"
  | .webManifestUrl="http://127.0.0.1:8765/manifest.json" | .fullScopeUrl=("https://"+$h+"/")
  | .shareTarget.action=("https://"+$h+"/share-target") | .features={} | .enableNotifications=false
  | .signingKey={"path":"./debug.keystore","alias":"androiddebugkey"}' qa/twa-manifest.ten10.json > twa/twa-manifest.json
mkdir -p ~/.bubblewrap
echo "{\"jdkPath\":\"$JAVA_HOME\",\"androidSdkPath\":\"$ANDROID_HOME\"}" > ~/.bubblewrap/config.json
npm i -g @bubblewrap/cli@1.24.1 >/dev/null 2>&1 || npm i -g @bubblewrap/cli
cd twa
yes | bubblewrap update --skipVersionUpgrade --manifest=./twa-manifest.json
chmod +x gradlew
./gradlew --no-daemon -q assembleDebug
find . -name '*.apk' -path '*debug*' | head -1 | xargs -I{} cp {} ../ten10-twa-debug.apk
ls -la ../ten10-twa-debug.apk
