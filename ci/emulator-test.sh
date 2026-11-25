#!/usr/bin/env bash
# Runs inside the Android emulator. Fails on crashes, on files that don't open, and saves screenshots.
PKG=com.canvaplayer.app
OUT=shots; mkdir -p $OUT
shot() { adb exec-out screencap -p > "$OUT/$1.png"; }
fail=0
adb install -r app.apk || exit 1
adb shell mkdir -p /sdcard/Download /sdcard/Documents/Notes
adb push ci-samples/. /sdcard/Download/
adb shell cp /sdcard/Download/github-git-cheat-sheet.md /sdcard/Documents/Notes/
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow
adb shell input keyevent KEYCODE_HOME
adb logcat -c
adb shell am start -n $PKG/.MainActivity; sleep 10
shot 01_folders
python3 ci/ui.py text "All"; sleep 10; shot 02_all_thumbnails_loading
sleep 12; shot 03_all_thumbnails
python3 ci/ui.py desc "More options" ; sleep 1; shot 04_overflow; adb shell input keyevent KEYCODE_BACK
python3 ci/ui.py text "Favorites"; sleep 2; shot 05_favorites
python3 ci/ui.py text "Recent"; sleep 2; shot 06_recent
python3 ci/ui.py text "Folders"; sleep 2; python3 ci/ui.py text "Download"; sleep 3; shot 07_inside_folder
adb shell input keyevent KEYCODE_BACK; sleep 1
python3 ci/ui.py desc "Settings"; sleep 3; shot 08_settings
adb shell input keyevent KEYCODE_BACK; sleep 1

check_open() { # name, viewintent args...
  local name=$1; shift
  adb shell am start -a android.intent.action.VIEW "$@" >/dev/null; sleep 6
  top=$(adb shell dumpsys activity activities | grep -E "topResumedActivity|ResumedActivity" | head -2)
  echo "[$name] $top"
  shot "open_$name"
  if ! echo "$top" | grep -q "$PKG"; then
    if echo "$top" | grep -q "ResolverActivity"; then echo "[$name] chooser shown, app is one of the choices (other apps also handle this type)";
    else echo "::error::$name did not open in the app"; fail=1; fi
  fi
  adb shell input keyevent KEYCODE_BACK; sleep 1
}
check_open md_typeless   -d file:///sdcard/Download/github-git-cheat-sheet.md
check_open md_textplain  -d file:///sdcard/Download/github-git-cheat-sheet.md -t text/plain
check_open md_octet      -d file:///sdcard/Download/github-git-cheat-sheet.md -t application/octet-stream
check_open ttf_octet     -d file:///sdcard/Download/Alatsi.ttf -t application/octet-stream
check_open ttf_font      -d file:///sdcard/Download/Alatsi.ttf -t font/ttf
check_open csv_textplain -d file:///sdcard/Download/scores.csv -t text/plain
check_open json          -d file:///sdcard/Download/config.json -t application/json
check_open svg           -d file:///sdcard/Download/logo.svg -t image/svg+xml
check_open geojson       -d file:///sdcard/Download/route.geojson -t application/octet-stream
check_open html          -d file:///sdcard/Download/sample-page.html -t text/html

# unsupported file must NOT be claimed by the app
adb shell am start -a android.intent.action.VIEW -d file:///sdcard/Download/nothing.xyz -t application/octet-stream >/dev/null; sleep 3
shot unsupported_not_ours
adb shell input keyevent KEYCODE_HOME

# dark mode
adb shell cmd uimode night yes; sleep 2
adb shell am start -n $PKG/.MainActivity; sleep 5
python3 ci/ui.py text "All"; sleep 6; shot 09_dark_all
adb shell cmd uimode night no

if adb logcat -d | grep -A12 "FATAL EXCEPTION" | grep -q "$PKG"; then
  echo "::error::App crashed"; adb logcat -d | grep -B2 -A25 "FATAL EXCEPTION" | head -80; fail=1
fi
adb logcat -d > $OUT/logcat.txt
exit $fail
