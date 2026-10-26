#!/usr/bin/env bash
# Runs inside android-emulator-runner: install the APK, run the Maestro flow,
# collect screenshots, Maestro debug output and logcat into ./artifacts.
# Every adb call that can block on a vanished device is bounded by timeout.
set -x
ROOT="$GITHUB_WORKSPACE"
OUT="$ROOT/artifacts"
mkdir -p "$OUT/screenshots" "$OUT/maestro-debug"
timeout 30 adb logcat -G 16M || true
timeout 30 adb logcat -c || true
# Android shows a "Viewing full screen" cling over immersive apps on first
# launch; it swallows taps. Mark it as already seen.
timeout 30 adb shell settings put secure immersive_mode_confirmations confirmed || true
timeout 120 adb install -r "$ROOT/apk/app-debug.apk" 2>&1 | tee "$OUT/adb-install.txt"
timeout 30 adb shell getprop ro.product.cpu.abilist | tee "$OUT/device-abi.txt"
# Stream logcat (main + crash buffers) to disk for the whole flow, so a crash
# is on disk even if the device disappears before the end-of-run dump.
adb logcat -v threadtime > "$OUT/logcat-stream.txt" 2>&1 &
LOGCAT_PID=$!
adb logcat -b crash -v threadtime > "$OUT/logcat-crash-stream.txt" 2>&1 &
CRASH_PID=$!
export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true
export MAESTRO_DRIVER_STARTUP_TIMEOUT=180000
"$HOME/.maestro/bin/maestro" --version | tee "$OUT/maestro-version.txt"
cd "$OUT/screenshots"
timeout 900 "$HOME/.maestro/bin/maestro" test "$ROOT/.maestro/kids-mode.yaml" \
  --debug-output "$OUT/maestro-debug" 2>&1 | tee "$OUT/maestro-console.txt"
echo "maestro exit: ${PIPESTATUS[0]}" | tee -a "$OUT/maestro-console.txt"
cd "$ROOT"
kill "$LOGCAT_PID" "$CRASH_PID" 2>/dev/null || true
# Wherever this Maestro version wrote the screenshots, gather them.
find "$ROOT" "$HOME/.maestro" -name '*.png' -newer "$OUT/adb-install.txt" \
  -not -path "$OUT/screenshots/*" -not -path "$ROOT/node_modules/*" \
  -exec cp {} "$OUT/screenshots/" \; 2>/dev/null || true
ls -la "$OUT/screenshots"
timeout 10 adb devices -l | tee "$OUT/adb-devices-end.txt" || true
timeout 60 adb logcat -d > "$OUT/logcat.txt" || true
timeout 30 adb logcat -b crash -d > "$OUT/logcat-crash.txt" || true
# The emulator's own logs, if it wrote any.
mkdir -p "$OUT/emulator"
cp "$HOME"/.android/avd/*.avd/*.log "$OUT/emulator/" 2>/dev/null || true
cp /tmp/android-runner/*.txt /tmp/android-runner/*.log "$OUT/emulator/" 2>/dev/null || true
ls -la /tmp/android-runner 2>/dev/null | tee "$OUT/emulator/android-runner-ls.txt" || true
pgrep -a qemu | tee "$OUT/emulator/qemu-ps.txt" || echo "no qemu process" | tee "$OUT/emulator/qemu-ps.txt"
free -m | tee "$OUT/emulator/free-m.txt" || true
# Emulator crash reports (minidumps) live in a directory, not top-level files.
cp -r /tmp/android-runner/emu-crash-*.db "$OUT/emulator/" 2>/dev/null || true
find /tmp/android-runner -type f -exec ls -la {} \; | tee "$OUT/emulator/crash-files.txt" || true
exit 0
