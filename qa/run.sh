#!/usr/bin/env bash
# Runs inside the emulator. Never echoes BYPASS / QA_* (cdp.py scrubs; final sed scrubs artifacts too).
set -u
H="$PREVIEW_HOST"; O=artifacts; mkdir -p $O/shots $O/text
A=com.android.chrome
n=0
shot(){ n=$((n+1)); f=$(printf "%02d-%s" $n "$1"); adb exec-out screencap -p > "$O/shots/$f.png"; python3 qa/cdp.py text > "$O/text/$f.txt" 2>&1; python3 qa/uia.py dump > "$O/text/$f.ui.txt" 2>&1; echo "shot $f"; }
uia(){ python3 qa/uia.py "$@" || true; }
dismiss(){ for i in 1 2 3 4; do uia tap '^(Accept & continue|Use without an account|No thanks|Got it|No, thanks|Continue|Not now)$' | grep -q tapped || break; sleep 2; done; }

adb shell settings put global window_animation_scale 0; adb shell settings put global transition_animation_scale 0; adb shell settings put global animator_duration_scale 0
adb shell "echo '_ --disable-fre --no-default-browser-check --no-first-run --disable-digital-asset-link-verification-for-url=https://$H' > /data/local/tmp/chrome-command-line"
adb shell cat /data/local/tmp/chrome-command-line > $O/chrome-command-line.txt
adb shell am set-debug-app --persistent $A
adb shell dumpsys package $A | grep -E "versionName" | head -1 | tee $O/chrome-version.txt
adb shell getprop ro.build.fingerprint >> $O/chrome-version.txt
adb logcat -c
adb shell am start -n $A/com.google.android.apps.chrome.Main -d about:blank; sleep 10; dismiss
adb forward tcp:9222 localabstract:chrome_devtools_remote
for i in $(seq 1 10); do python3 qa/cdp.py tabs && break; sleep 3; done
shot chrome-start

echo "== PWA: bypass + login"
python3 qa/cdp.py nav "https://$H/?x-vercel-protection-bypass=$BYPASS&x-vercel-set-bypass-cookie=samesitenone" ; sleep 12
python3 qa/cdp.py nav "https://$H/login"; sleep 10; dismiss
shot pwa-login-page
python3 qa/cdp.py login 2>&1 | tee $O/text/login-result.txt; sleep 12
shot pwa-after-login

echo "== PWA: install via Chrome menu"
python3 qa/cdp.py installability > $O/installability-before.txt 2>&1
python3 qa/cdp.py holdheaders 900 > $O/holdheaders.txt 2>&1 &
sleep 20
uia tap 'menu_button|More options|Customize and control'; sleep 2
shot pwa-menu
python3 qa/cdp.py installability > $O/installability.txt 2>&1
python3 qa/uia.py tap '^Install app$' > $O/install-menu.txt || python3 qa/uia.py tap '^Add to (H|h)ome screen$' >> $O/install-menu.txt
sleep 4
shot pwa-install-dialog
python3 qa/uia.py dump > $O/install-dialog-ui.txt
uia tap '^Install$'; sleep 8; shot pwa-install-progress
for i in $(seq 1 18); do adb shell pm list packages | grep -qi webapk && break; uia tap '^(Install|Add|Add automatically|Add to home screen)$' >/dev/null; sleep 5; done
shot pwa-after-install
adb shell pm list packages | grep -i webapk | tee $O/webapk-packages.txt
WEBAPK=$(sed -n 's/package://p' $O/webapk-packages.txt | head -1)
adb shell input keyevent HOME; sleep 2; shot home-screen

TEXT="QA share text: paid 120 ILS to Dentist Cohen on 2026-10-22"
adb install -r qa-sharer.apk | tee $O/sharer-install.txt
chooser(){ adb shell am start -n com.ten10qa.sharer/.ShareActivity --es pkg "''" --es mode "$1" --es text "\"${2:-}\"" --ez chooser true | tee -a $O/am.txt; }
share(){ adb shell am start -n com.ten10qa.sharer/.ShareActivity --es pkg "$1" --es mode "$2" --es text "\"${3:-}\"" | tee -a $O/am.txt; }
adb push qa/assets/receipt.png /sdcard/Download/receipt.png
adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Download/receipt.png; sleep 4
adb shell content query --uri content://media/external/images/media --projection _id:_display_name | tee $O/mediastore.txt
MID=$(grep receipt.png $O/mediastore.txt | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | tail -1)
URI="content://media/external/images/media/$MID"
echo "file uri: $URI" | tee $O/file-uri.txt

if [ -n "$WEBAPK" ]; then
  echo "== PWA text (WebAPK $WEBAPK)"
  adb shell dumpsys package "$WEBAPK" | grep -A3 -E "android.intent.action.SEND" > $O/webapk-intents.txt
  adb shell cmd package query-activities -a android.intent.action.SEND -t text/plain | grep -iE "webapk|name=" > $O/webapk-share-activities.txt
  for mode in text file; do
    chooser "$mode" "$TEXT (PWA sheet)"; sleep 6; shot pwa-$mode-sharesheet
    uia tap '^Ten10' || { adb shell input swipe 160 560 160 200; sleep 2; shot pwa-$mode-sharesheet-scrolled; uia tap '^Ten10'; }
    sleep 25; shot pwa-$mode-sheet-result
    adb shell am force-stop "$WEBAPK"; sleep 2
  done
  share "$WEBAPK" text "$TEXT (PWA direct)"; sleep 25; shot pwa-text-direct
  share "$WEBAPK" file; sleep 25; shot pwa-file-direct
else
  echo "NO WEBAPK minted; falling back to in-page POST /share-target (exercises SW + app intake, not the OS share sheet)" | tee $O/pwa-fallback.txt
  adb shell am start -n $A/com.google.android.apps.chrome.Main -d "https://$H/"; sleep 10
  python3 qa/cdp.py sharetext "$TEXT" | tee -a $O/pwa-fallback.txt; sleep 15
  shot pwa-text-share-fallback
  python3 qa/cdp.py sharefile qa/assets/receipt.png | tee -a $O/pwa-fallback.txt; sleep 15
  shot pwa-file-share-fallback
fi

if [ "${SKIP_TWA:-}" = 1 ]; then echo "skip TWA"; else
echo "== TWA"
adb install -r ten10-twa-debug.apk | tee $O/twa-install.txt
adb shell dumpsys package com.ten10_app.twa | grep -B1 -A4 "android.intent.action.SEND" > $O/twa-intents.txt
adb shell pm get-app-links com.ten10_app.twa > $O/twa-applinks.txt 2>&1
adb shell monkey -p com.ten10_app.twa -c android.intent.category.LAUNCHER 1; sleep 15; dismiss
shot twa-launch
share com.ten10_app.twa text "$TEXT (TWA warm)"; sleep 20; shot twa-text-share-warm
share com.ten10_app.twa file; sleep 20; shot twa-file-share-warm
adb shell am force-stop com.ten10_app.twa; adb shell am force-stop $A; sleep 2
share com.ten10_app.twa text "$TEXT (TWA cold)"; sleep 25; shot twa-text-share-cold
adb shell am force-stop com.ten10_app.twa; adb shell am force-stop $A; sleep 2
share com.ten10_app.twa file; sleep 25; shot twa-file-share-cold
if python3 qa/cdp.py text 2>/dev/null | grep -q "/login"; then python3 qa/cdp.py login 2>&1 | tee -a $O/text/login-result.txt; sleep 15; shot twa-after-login; fi
fi
adb logcat -d > $O/logcat-full.txt
grep -iE "chromium|cr_|ten10|webapk|WebApk|Installab|AddToHomescreen|A2HS|PackageInstaller|Finsky|Phonesky|TrustedWeb|TWA|ShareTarget|browserhelper" $O/logcat-full.txt > $O/logcat-filtered.txt
rm $O/logcat-full.txt
# scrub every text artifact
for v in "$BYPASS" "$QA_EMAIL" "$QA_PASSWORD"; do [ -n "$v" ] && grep -rlF -- "$v" $O | while read f; do python3 - "$f" "$v" <<'PY'
import sys;p,v=sys.argv[1],sys.argv[2];b=open(p,'rb').read().replace(v.encode(),b'***');open(p,'wb').write(b)
PY
done; done
echo done
