#!/usr/bin/env bash
# Runs inside android-emulator-runner: install the APK, run the Maestro flow,
# collect screenshots, Maestro debug output and logcat into ./artifacts.
set -x
ROOT="$GITHUB_WORKSPACE"
OUT="$ROOT/artifacts"
mkdir -p "$OUT/screenshots" "$OUT/maestro-debug"
adb logcat -G 16M || true
# Android shows a "Viewing full screen" cling over immersive apps on first
# launch; it swallows taps. Mark it as already seen.
adb shell settings put secure immersive_mode_confirmations confirmed || true
adb logcat -c || true
adb install -r "$ROOT/apk/app-debug.apk" 2>&1 | tee "$OUT/adb-install.txt"
adb shell getprop ro.product.cpu.abilist | tee "$OUT/device-abi.txt"
export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
export MAESTRO_DRIVER_STARTUP_TIMEOUT=180000
"$HOME/.maestro/bin/maestro" --version | tee "$OUT/maestro-version.txt"
cd "$OUT/screenshots"
"$HOME/.maestro/bin/maestro" test "$ROOT/.maestro/kids-mode.yaml" \
  --debug-output "$OUT/maestro-debug" 2>&1 | tee "$OUT/maestro-console.txt"
echo "maestro exit: ${PIPESTATUS[0]}" | tee -a "$OUT/maestro-console.txt"
cd "$ROOT"
# Wherever this Maestro version wrote the screenshots, gather them.
find "$ROOT" "$HOME/.maestro" -name '[01][0-9]*.png' -newer "$OUT/adb-install.txt" \
  -not -path "$OUT/screenshots/*" -exec cp {} "$OUT/screenshots/" \; 2>/dev/null || true
ls -la "$OUT/screenshots"
adb logcat -d > "$OUT/logcat.txt" || true
adb logcat -b crash -d > "$OUT/logcat-crash.txt" || true
exit 0
