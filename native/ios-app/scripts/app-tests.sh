#!/bin/bash
# app-tests.sh SIMULATOR_UDID [DERIVED_DATA] [SIMCTL_LAUNCH_ARGS...]: builds PokiTests and runs it
# inside Poki on a booted iOS simulator. The bundle is injected into Poki at launch
# (libXCTestBundleInject) instead of going through `xcodebuild test`, whose runner connection hangs
# on some Xcode and simulator pairs.
set -euo pipefail
UDID="$1"
shift
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  DD="$1"
  shift
else
  DD="$APP_DIR/../../build/app-tests"
fi
X="$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer"
TIMEOUT_SECONDS="${POKI_TEST_TIMEOUT:-1200}"

BUILD_ARGS=()
if [ -n "${POKI_SPM_DIR:-}" ]; then
  BUILD_ARGS+=(-clonedSourcePackagesDirPath "$POKI_SPM_DIR")
fi

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    python3 - "$seconds" "$@" <<'PY'
import subprocess, sys
seconds = int(sys.argv[1])
proc = subprocess.Popen(sys.argv[2:])
try:
    sys.exit(proc.wait(timeout=seconds))
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
    sys.exit(124)
PY
  fi
}

xcodegen generate --spec "$APP_DIR/project.yml" >/dev/null
xcodebuild -quiet build-for-testing -project "$APP_DIR/Poki.xcodeproj" -scheme Poki \
  -destination "id=$UDID" -derivedDataPath "$DD" "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
APP="$DD/Build/Products/Debug-iphonesimulator/Poki.app"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
# Setup's last item needs location; the tests check a phone with every item done.
xcrun simctl privacy "$UDID" grant location-always "$BUNDLE"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

# PokiTests read the English text, as on CI's simulator, whatever language this Mac's simulator uses.
LOG="$(mktemp)"
cleanup() {
  if [ -n "${POKI_TEST_LOG:-}" ] && [ -f "$LOG" ]; then
    mkdir -p "$(dirname "$POKI_TEST_LOG")"
    tr '\r' '\n' < "$LOG" > "$POKI_TEST_LOG"
  fi
  rm -f "$LOG"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
}
trap cleanup EXIT
SIMCTL_CHILD_DYLD_INSERT_LIBRARIES="$X/usr/lib/libXCTestBundleInject.dylib" \
SIMCTL_CHILD_XCTestBundlePath="$APP/PlugIns/PokiTests.xctest" \
SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$X/Library/Frameworks:$X/Library/PrivateFrameworks" \
SIMCTL_CHILD_DYLD_LIBRARY_PATH="$X/usr/lib" \
  run_with_timeout "$TIMEOUT_SECONDS" xcrun simctl launch --console-pty "$UDID" "$BUNDLE" -AppleLanguages "(en)" -AppleLocale en_US "$@" >"$LOG" 2>&1 || true
NORM="$(mktemp)"
tr '\r' '\n' < "$LOG" > "$NORM"
mv "$NORM" "$LOG"
grep -E "^Test Case|error:|Executed" "$LOG" || true
if ! grep -qE "Test Suite '(All|Selected) tests' passed" "$LOG"; then
  echo "--- PokiTests did not pass; tail of simulator console ---" >&2
  tail -n 80 "$LOG" >&2 || true
  exit 1
fi
