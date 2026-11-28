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

def check_success(case, tag, target):
    rc, stderr, trace, data = load(case, tag)
    check(rc == 0, f"{case}: expected exit 0, got {rc} (stderr={stderr!r})")
    check(data.get("front", {}).get("bundleId") == target,
          f"{case}: expected {target} in front, got {data.get('front')}")
    check("front_error" not in data, f"{case}: unexpected front_error {data.get('front_error')}")
    check(f"sourceXML:{target}" in trace, f"{case}: sourceXML not read on {target}: {trace}")
    check(f"screenshot:{target}" in trace, f"{case}: screenshot not captured on {target}: {trace}")
    check(not any(t.startswith("sourceXML:") and t != f"sourceXML:{target}" for t in trace),
          f"{case}: read non-target app before {target} arrived: {trace}")
    check(not any(t.startswith("screenshot:") and t != f"screenshot:{target}" for t in trace),
          f"{case}: captured non-target app before {target} arrived: {trace}")

def check_timeout(case, tag, expected_front, last_front):
    rc, stderr, trace, data = load(case, tag)
    check(rc == 1, f"{case}: expected exit 1 on timeout, got {rc} (stderr={stderr!r})")
    check((data.get("front", {}).get("bundleId") or "") == last_front,
          f"{case}: expected last front {last_front!r}, got {data.get('front')}")
    check(data.get("last_front_bundle") == last_front,
          f"{case}: expected last_front_bundle {last_front!r}, got {data.get('last_front_bundle')!r}")
    check(data.get("expected_front") == expected_front,
          f"{case}: expected expected_front {expected_front!r}, got {data.get('expected_front')!r}")
    check(data.get("front_error") == "front_app_timeout",
          f"{case}: expected front_error=front_app_timeout, got {data.get('front_error')!r}")
    check(data.get("front_wait_seconds", 0) >= 60.0,
          f"{case}: expected >=60s wait, got {data.get('front_wait_seconds')}")
    check(expected_front in stderr, f"{case}: expected {expected_front!r} in stderr, got {stderr!r}")
    if last_front:
        check(last_front in stderr, f"{case}: expected {last_front!r} in stderr, got {stderr!r}")
    check(not any(t.startswith("sourceXML:") for t in trace),
          f"{case}: must not call sourceXML after timeout: {trace}")
    check(not any(t.startswith("screenshot:") for t in trace),
          f"{case}: must not call screenshot after timeout: {trace}")

check_success("springboard_then_fixture", "shot", "local.pokimcp.fixture")
check_success("empty_and_custom_fixture", "custom", "com.example.target")
check_timeout("timeout_springboard", "timeout-sb", "local.pokimcp.fixture", "com.apple.springboard")
check_timeout("timeout_other_app", "timeout-other", "com.example.target", "com.apple.Preferences")
check_timeout("timeout_empty_front", "timeout-empty", "local.pokimcp.fixture", "")

if failures:
    print("FAIL front-wait-test:", file=sys.stderr)
    for f in failures:
        print(f"  - {f}", file=sys.stderr)
    sys.exit(1)

print("PASS front-wait-test (5/5 cases)")
PY
