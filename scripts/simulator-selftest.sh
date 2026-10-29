#!/usr/bin/env bash
# Install the U-file simulator build on an iPad simulator and run the app's
# own end-to-end check (src/selftest.ts). Writes the report and screenshots
# to $3.
#
#   scripts/simulator-selftest.sh <U-file.app> <fixtures-dir> <output-dir>
set -euo pipefail

app="$1"
fixtures="$2"
out="$3"
bundle=com.cybereun.filemoa
mkdir -p "$out"

# The smallest iPad: CI's Macs have only a virtual GPU, and a 13-inch screen's
# render targets exhaust its memory before an editor frame is drawn.
udid="$(xcrun simctl list devices available -j | jq -r '
  [.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("iPad"))]
  | (map(select(.name | test("mini"))) + map(select(.name | test("^iPad \\("))) + .) | first | .udid')"
xcrun simctl list devices available | grep "$udid" || true
if [ -z "$udid" ] || [ "$udid" = null ]; then
  echo "FAIL: no iPad simulator available"
  xcrun simctl list devices available
  exit 1
fi
echo "== iPad simulator $udid"
xcrun simctl boot "$udid" || true
xcrun simctl bootstatus "$udid" -b

echo "== install"
xcrun simctl install "$udid" "$app"
docs="$(xcrun simctl get_app_container "$udid" "$bundle" data)/Documents"
rm -rf "$docs/ufile-selftest" "$docs/U-file"
mkdir -p "$docs/ufile-selftest/data"
cp "$fixtures"/* "$docs/ufile-selftest/data/"
touch "$docs/ufile-selftest/RUN_SELFTEST"

echo "== run"
xcrun simctl launch "$udid" "$bundle"
report="$docs/U-file/U-file-selftest.json"
progress="$docs/ufile-selftest/progress.log"
for round in $(seq 1 120); do
  sleep 20
  xcrun simctl io "$udid" screenshot "$out/screen-$(printf '%03d' "$round").png" >/dev/null 2>&1 || true
  if [ -f "$report" ]; then
    cp "$report" "$out/selftest.json"
    break
  fi
  # The page logs as soon as it loads; silence after 2 minutes means it never ran.
  if [ "$round" -ge 6 ] && [ ! -s "$progress" ]; then
    echo "FAIL: the app's page did not start the self-test"
    break
  fi
done
xcrun simctl io "$udid" screenshot "$out/screen-final.png" >/dev/null 2>&1 || true
echo "== progress.log"
cat "$progress" 2>/dev/null || echo "(none)"
cp "$progress" "$out/" 2>/dev/null || true
echo "== app log (last lines)"
xcrun simctl spawn "$udid" log show --last 45m --style compact \
  --predicate 'process == "U-file" OR subsystem CONTAINS "WebKit"' 2>/dev/null | tail -n 150 || true

if [ ! -f "$out/selftest.json" ]; then
  echo "FAIL: the self-test did not finish within 40 minutes"
  exit 1
fi
cat "$out/selftest.json"
jq -e '.ok == true' "$out/selftest.json" >/dev/null
echo "== all checks passed"
