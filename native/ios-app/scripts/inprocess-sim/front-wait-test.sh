#!/bin/bash
# Regression tests for main.m's front-app wait loop using a virtual clock and stubbed PKInProcess.
# Usage: front-wait-test.sh <BOOTED_SIMULATOR_UDID> [NATIVE_DIR]
set -euo pipefail
UDID="${1:?supply a booted simulator UDID}"
HERE="$(cd "$(dirname "$0")" && pwd)"
NATIVE="${2:-$HERE/../../Poki/Native}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/poki-front-wait-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" \
  -fobjc-arc -fmodules -Wall -Werror -Wno-deprecated-declarations -I "$NATIVE" \
  -c "$HERE/main.m" -o "$WORK/main.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" \
  -fobjc-arc -fmodules -Wall -Werror -Wno-deprecated-declarations -Wno-incomplete-implementation -I "$NATIVE" \
  -c "$HERE/front-wait-test.m" -o "$WORK/front-wait-test.o"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -isysroot "$SDK" \
  -fobjc-arc -fmodules -framework UIKit "$WORK/main.o" "$WORK/front-wait-test.o" -o "$WORK/front-wait-test"

run_case() {
  local name="$1"
  local fronts="$2"
  shift 2
  local home="$WORK/$name"
  mkdir -p "$home/Documents"
  local trace="$home/trace.log"
  local stderr_log="$home/stderr.log"
  local rc=0
  SIMCTL_CHILD_HOME="$home" \
  SIMCTL_CHILD_POKI_TEST_DOCS="$home/Documents" \
  SIMCTL_CHILD_POKI_TEST_FRONTS="$fronts" \
  SIMCTL_CHILD_POKI_TEST_TRACE="$trace" \
    xcrun simctl spawn "$UDID" "$WORK/front-wait-test" "$@" >"$home/stdout.log" 2>"$stderr_log" || rc=$?
  printf '%s' "$rc" >"$home/rc.txt"
}

run_case springboard_then_fixture \
  "local.poki.inprocess-check,com.apple.springboard,com.apple.Preferences,local.pokimcp.fixture" \
  -mode read -tag shot

run_case empty_and_custom_fixture \
  "NIL,,com.apple.springboard,local.pokimcp.fixture,com.example.target" \
  -mode read -tag custom -fixture com.example.target

run_case timeout_springboard \
  "local.poki.inprocess-check,com.apple.springboard" \
  -mode read -tag timeout-sb

run_case timeout_other_app \
  "NIL,com.apple.Preferences" \
  -mode field -tag timeout-other -fixture com.example.target

run_case timeout_empty_front \
  "NIL" \
  -mode read -tag timeout-empty

python3 - "$WORK" <<'PY'
import json
import pathlib
import sys

work = pathlib.Path(sys.argv[1])
failures = []

def check(cond, msg):
    if not cond:
        failures.append(msg)

def load(case, tag):
    base = work / case
    rc = int((base / "rc.txt").read_text().strip())
    stderr = (base / "stderr.log").read_text()
    trace = (base / "trace.log").read_text().splitlines() if (base / "trace.log").exists() else []
    json_path = base / "Documents" / f"{tag}.json"
    if not json_path.exists():
        raise AssertionError(f"{case}: missing {json_path} (rc={rc}, stderr={stderr!r}, trace={trace})")
    data = json.loads(json_path.read_text())
    return rc, stderr, trace, data

rc, stderr, trace, data = load("springboard_then_fixture", "shot")
check(rc == 0, f"springboard_then_fixture: expected exit 0, got {rc} (stderr={stderr!r})")
check(data.get("front", {}).get("bundleId") == "local.pokimcp.fixture",
      f"springboard_then_fixture: expected local.pokimcp.fixture in front, got {data.get('front')}")
check(abs(data.get("front_wait_seconds", -1) - 1.5) < 0.01,
      f"springboard_then_fixture: expected 1.5s virtual wait, got {data.get('front_wait_seconds')}")
check("front_error" not in data, f"springboard_then_fixture: unexpected front_error {data.get('front_error')}")
check("sourceXML:local.pokimcp.fixture" in trace, f"springboard_then_fixture: sourceXML not read on fixture: {trace}")
check(not any(t.startswith("sourceXML:") and t != "sourceXML:local.pokimcp.fixture" for t in trace),
      f"springboard_then_fixture: read non-target app before fixture arrived: {trace}")
check(not any(t.startswith("screenshot:") and t != "screenshot:local.pokimcp.fixture" for t in trace),
      f"springboard_then_fixture: captured non-target app before fixture arrived: {trace}")

rc, stderr, trace, data = load("empty_and_custom_fixture", "custom")
check(rc == 0, f"empty_and_custom_fixture: expected exit 0, got {rc} (stderr={stderr!r})")
check(data.get("front", {}).get("bundleId") == "com.example.target",
      f"empty_and_custom_fixture: expected com.example.target in front, got {data.get('front')}")
check(abs(data.get("front_wait_seconds", -1) - 2.0) < 0.01,
      f"empty_and_custom_fixture: expected 2.0s virtual wait, got {data.get('front_wait_seconds')}")
check("sourceXML:com.example.target" in trace, f"empty_and_custom_fixture: sourceXML not read on custom target: {trace}")
check(not any(t.startswith("sourceXML:") and t != "sourceXML:com.example.target" for t in trace),
      f"empty_and_custom_fixture: read wrong app before custom target arrived: {trace}")

rc, stderr, trace, data = load("timeout_springboard", "timeout-sb")
check(rc != 0, f"timeout_springboard: expected non-zero exit on timeout, got {rc}")
check(data.get("front", {}).get("bundleId") == "com.apple.springboard",
      f"timeout_springboard: expected last front com.apple.springboard, got {data.get('front')}")
check(data.get("last_front_bundle") == "com.apple.springboard",
      f"timeout_springboard: expected last_front_bundle com.apple.springboard, got {data.get('last_front_bundle')!r}")
check(data.get("expected_front") == "local.pokimcp.fixture",
      f"timeout_springboard: expected expected_front local.pokimcp.fixture, got {data.get('expected_front')!r}")
check(data.get("front_error") == "front_app_timeout",
      f"timeout_springboard: expected front_error=front_app_timeout, got {data.get('front_error')!r}")
check(data.get("front_wait_seconds", 0) >= 60.0,
      f"timeout_springboard: expected >=60s wait, got {data.get('front_wait_seconds')}")
check("com.apple.springboard" in stderr,
      f"timeout_springboard: expected last front bundle in stderr, got {stderr!r}")
check(not any(t.startswith("sourceXML:") for t in trace),
      f"timeout_springboard: must not call sourceXML after timeout: {trace}")
check(not any(t.startswith("screenshot:") for t in trace),
      f"timeout_springboard: must not call screenshot after timeout: {trace}")

rc, stderr, trace, data = load("timeout_other_app", "timeout-other")
check(rc != 0, f"timeout_other_app: expected non-zero exit on timeout, got {rc}")
check(data.get("front", {}).get("bundleId") == "com.apple.Preferences",
      f"timeout_other_app: expected last front com.apple.Preferences, got {data.get('front')}")
check(data.get("last_front_bundle") == "com.apple.Preferences",
      f"timeout_other_app: expected last_front_bundle com.apple.Preferences, got {data.get('last_front_bundle')!r}")
check(data.get("expected_front") == "com.example.target",
      f"timeout_other_app: expected expected_front com.example.target, got {data.get('expected_front')!r}")
check(data.get("front_error") == "front_app_timeout",
      f"timeout_other_app: expected front_error=front_app_timeout, got {data.get('front_error')!r}")
check(data.get("front_wait_seconds", 0) >= 60.0,
      f"timeout_other_app: expected >=60s wait, got {data.get('front_wait_seconds')}")
check("com.apple.Preferences" in stderr,
      f"timeout_other_app: expected last front bundle in stderr, got {stderr!r}")
check(not any(t.startswith("sourceXML:") for t in trace),
      f"timeout_other_app: must not call sourceXML after timeout: {trace}")

rc, stderr, trace, data = load("timeout_empty_front", "timeout-empty")
check(rc != 0, f"timeout_empty_front: expected non-zero exit on timeout, got {rc}")
check(data.get("last_front_bundle") == "",
      f"timeout_empty_front: expected empty last_front_bundle, got {data.get('last_front_bundle')!r}")
check(data.get("expected_front") == "local.pokimcp.fixture",
      f"timeout_empty_front: expected expected_front local.pokimcp.fixture, got {data.get('expected_front')!r}")
check(data.get("front_error") == "front_app_timeout",
      f"timeout_empty_front: expected front_error=front_app_timeout, got {data.get('front_error')!r}")
check(data.get("front_wait_seconds", 0) >= 60.0,
      f"timeout_empty_front: expected >=60s wait, got {data.get('front_wait_seconds')}")
check("local.pokimcp.fixture" in stderr,
      f"timeout_empty_front: expected timeout message in stderr, got {stderr!r}")
check(not any(t.startswith("sourceXML:") for t in trace),
      f"timeout_empty_front: must not call sourceXML after timeout: {trace}")
check(not any(t.startswith("screenshot:") for t in trace),
      f"timeout_empty_front: must not call screenshot after timeout: {trace}")

if failures:
    print("FAIL front-wait-test:", file=sys.stderr)
    for f in failures:
        print(f"  - {f}", file=sys.stderr)
    sys.exit(1)

print("PASS front-wait-test (5/5 cases)")
PY
