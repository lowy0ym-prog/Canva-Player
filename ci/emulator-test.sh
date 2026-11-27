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
mkdir -p bulk; for i in $(seq 1 90); do printf "# Note $i\n\nSome text for file $i.\n- one\n- two\n" > bulk/note-$i.md; printf "a,b,c\n$i,2,3\n" > bulk/table-$i.csv; done
adb push bulk /sdcard/Documents/Bulk
adb shell appops set $PKG MANAGE_EXTERNAL_STORAGE allow
adb shell input keyevent KEYCODE_HOME
adb logcat -c
adb shell am start -n $PKG/.MainActivity; sleep 10
shot 01_folders
python3 ci/ui.py text "All"; sleep 10; shot 02_all_thumbnails_loading
# smoothness: scroll the gallery grid back and forth and read the frame stats
adb shell dumpsys gfxinfo $PKG reset >/dev/null
for i in 1 2 3 4 5 6; do adb shell input swipe 540 1800 540 600 250; adb shell input swipe 540 600 540 1800 250; done
adb shell dumpsys gfxinfo $PKG | grep -E "Total frames|Janky frames|50th|90th|95th|99th" | tee $OUT/smoothness.txt
shot 02b_after_scroll
# same scroll again with every preview already cached (warm), then the phone's own Settings app as a yardstick
adb shell dumpsys gfxinfo $PKG reset >/dev/null
for i in 1 2 3 4 5 6; do adb shell input swipe 540 1800 540 600 250; adb shell input swipe 540 600 540 1800 250; done
echo "--- Folio warm" | tee -a $OUT/smoothness.txt
adb shell dumpsys gfxinfo $PKG | grep -E "Total frames|Janky frames:|50th percentile|90th percentile" | tee -a $OUT/smoothness.txt
adb shell am start -a android.settings.SETTINGS >/dev/null; sleep 3
adb shell dumpsys gfxinfo com.android.settings reset >/dev/null
for i in 1 2 3 4 5 6; do adb shell input swipe 540 1800 540 600 250; adb shell input swipe 540 600 540 1800 250; done
echo "--- Android Settings (yardstick)" | tee -a $OUT/smoothness.txt
adb shell dumpsys gfxinfo com.android.settings | grep -E "Total frames|Janky frames:|50th percentile|90th percentile" | tee -a $OUT/smoothness.txt
adb shell am start -n $PKG/.MainActivity; sleep 3; python3 ci/ui.py text "All"; sleep 3
sleep 12; shot 03_all_thumbnails
# scroll chrome: slow swipe, look in the middle of it (date at the top, scroll-to-top ball, bottom bar gone)
adb shell input swipe 540 1900 540 100 8000 &
sleep 4.2; shot 03a_while_scrolling
BALL=$(python3 ci/ui.py hasdesc "Scroll to top"); echo "$BALL"
echo "$BALL" | grep -q PRESENT || { echo "::error::scroll-to-top button did not appear while scrolling"; fail=1; }
wait
BX=$(echo "$BALL" | awk '{print $4}'); BY=$(echo "$BALL" | awk '{print $5}')
if [ -n "$BX" ]; then adb shell input tap $BX $BY; sleep 1.2; shot 03b_after_ball_tap
  python3 ci/ui.py has "Today" || { echo "::error::scroll-to-top button did not return to the top"; fail=1; }; fi
sleep 2; shot 03c_settled_blur
python3 ci/ui.py has "Folders" || { echo "::error::bottom bar did not come back after scrolling stopped"; fail=1; }
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
# viewer: full-screen behaviour and every button
need() { python3 ci/ui.py "$@" || { echo "::error::viewer check failed: $*"; fail=1; }; }
adb shell am start -a android.intent.action.VIEW -d file:///sdcard/Download/github-git-cheat-sheet.md -t text/markdown >/dev/null
sleep 1; shot v1_viewer_controls
need hasdesc "Information"
sleep 4; python3 ci/ui.py text "GOT IT"; sleep 1; shot v2_viewer_auto_hidden
need absentdesc "Information"
adb shell input tap 540 1100; sleep 1; shot v3_viewer_tap_shows
need hasdesc "Information"
# every button
python3 ci/ui.py desc "Add to favorites"; sleep 1; shot v4_after_favorite
python3 ci/ui.py desc "Information"; sleep 1; shot v5_info_dialog
need has "OK"; python3 ci/ui.py text "OK"; sleep 1
python3 ci/ui.py desc "Quick Tools"; sleep 1.5; shot v6_quick_tools
adb shell input keyevent KEYCODE_BACK; sleep 1
python3 ci/ui.py desc "Reload"; sleep 2; shot v7_after_reload
need hasdesc "Information"
# scrolling must hide the controls and never bring them back
adb shell input swipe 540 1700 540 500 300; sleep 1; shot v8_scrolled_hidden
need absentdesc "Information"
adb shell input swipe 540 1700 540 500 300; sleep 1
need absentdesc "Information"
# touching the page to stop a fling is not a tap
adb shell input swipe 540 1800 540 300 120; adb shell input tap 540 1000; sleep 1
need absentdesc "Information"
# a real tap brings them back
sleep 1; adb shell input tap 540 1000; sleep 1; shot v9_tap_shows_again
need hasdesc "Information"
adb shell input keyevent KEYCODE_BACK; sleep 1
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
