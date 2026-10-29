#!/usr/bin/env bash
# Install the U-file APK on a running Android emulator and run the app's own
# end-to-end check (src/selftest.ts): organize, undo, duplicates, trash,
# FilmCraft editing and export. Also checks that the APK has no INTERNET
# permission. Writes the report, screenshots and logcat to $2.
#
#   scripts/emulator-selftest.sh <apk> <output-dir>
set -euo pipefail

apk="$1"
out="$2"
pkg=com.cybereun.filemoa
mkdir -p "$out"

adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 5; done

echo "== test files"
fixtures="$(mktemp -d)"
ffmpeg -loglevel error -f lavfi -i testsrc2=size=320x240:rate=24 -f lavfi -i sine=frequency=440 \
  -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$fixtures/clip.mp4"
ffmpeg -loglevel error -f lavfi -i testsrc2=size=320x240 -frames:v 1 "$fixtures/photo.jpg"
cp "$fixtures/photo.jpg" "$fixtures/photo-copy.jpg"
printf 'U-file self-test\n' > "$fixtures/notes.txt"
printf '%%PDF-1.4\n%%%%EOF\n' > "$fixtures/report.pdf"
# Shared storage is mounted a little after boot completes; wait until it takes writes.
for attempt in $(seq 1 30); do
  adb shell 'mkdir -p /sdcard/Download && touch /sdcard/Download/.ufile-probe && rm /sdcard/Download/.ufile-probe' >/dev/null 2>&1 && break
  sleep 5
done
adb shell rm -rf /sdcard/Download/ufile-selftest /sdcard/Download/U-file
adb shell mkdir -p /sdcard/Download/ufile-selftest/data
for file in "$fixtures"/*; do
  for attempt in 1 2 3 4 5; do
    adb push "$file" /sdcard/Download/ufile-selftest/data/ >/dev/null && break
    [ "$attempt" = 5 ] && exit 1
    sleep 5
  done
done
adb shell touch /sdcard/Download/ufile-selftest/RUN_SELFTEST

echo "== install"
adb install -r "$apk"
if adb shell dumpsys package "$pkg" | grep -q 'android.permission.INTERNET'; then
  echo "FAIL: the APK requests the INTERNET permission"
  exit 1
fi
echo "ok: no INTERNET permission"
# What the user grants on the "All files access" screen.
adb shell appops set --uid "$pkg" MANAGE_EXTERNAL_STORAGE allow

echo "== run"
adb logcat -c
adb shell am start -W -n "$pkg/.MainActivity"
report=/sdcard/Download/U-file/U-file-selftest.json
progress=/sdcard/Download/ufile-selftest/progress.log
for round in $(seq 1 120); do
  sleep 20
  adb exec-out screencap -p > "$out/screen-$(printf '%03d' "$round").png" || true
  if adb shell ls "$report" >/dev/null 2>&1; then
    adb pull "$report" "$out/selftest.json" >/dev/null
    break
  fi
  # The page logs as soon as it loads; silence after 2 minutes means it never ran.
  if [ "$round" -ge 6 ] && ! adb shell test -s "$progress"; then
    echo "FAIL: the app's page did not start the self-test"
    break
  fi
done
adb exec-out screencap -p > "$out/screen-final.png" || true
echo "== progress.log"
adb shell cat "$progress" 2>/dev/null || echo "(none)"
adb logcat -d > "$out/logcat.txt" || true
echo "== app log (last lines)"
grep -iE 'chromium|tauri|wry|filemoa|AndroidRuntime|FATAL' "$out/logcat.txt" | tail -n 150 || true

if [ ! -f "$out/selftest.json" ]; then
  echo "FAIL: the self-test did not finish within 40 minutes"
  exit 1
fi
cat "$out/selftest.json"
jq -e '.ok == true' "$out/selftest.json" >/dev/null
echo "== all checks passed"
