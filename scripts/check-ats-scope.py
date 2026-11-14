#!/usr/bin/env python3
"""Verify the App Transport Security scope of the plain-HTTP Custom Endpoint opt-in.

Checks:
  1. The built plist (or its deterministic rendering) has no NSAllowsArbitraryLoads and no denylist.
  2. NSAllowsLocalNetworking stays on for the voice bridge and loopback services.
  3. An explicit opt-in adds exactly one NSExceptionDomains host, with insecure loads allowed.
  4. A real cleartext HTTP request to a local server succeeds.
  5. A real HTTPS request to a host the app already uses succeeds.

When the XCODEGEN environment variable names an XcodeGen binary, the script generates the real
Poki/Info.plist for both the default and the opt-in build. Otherwise it renders the same ATS
dictionary from the specs with plistlib.
"""

import http.server
import os
import plistlib
import shutil
import ssl
import subprocess
import sys
import threading
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(ROOT, "native", "ios-app")
BASE = os.path.join(SPEC, "project-base.yml")
OPT_IN = os.path.join(SPEC, "project-http-endpoint.yml")
PLIST = os.path.join(SPEC, "Poki", "Info.plist")
FAILURES = []


def check(ok, label, detail=""):
    print(("PASS  " if ok else "FAIL  ") + label + (("  " + detail) if detail else ""))
    if not ok:
        FAILURES.append(label)


def built_plist_ats(opt_in, host):
    binary = os.environ.get("XCODEGEN") or shutil.which("xcodegen")
    if not binary:
        return None, "spec rendering"
    existed = os.path.isfile(PLIST)
    env = dict(os.environ)
    env.pop("POKI_HTTP_ENDPOINT_OPT_IN", None)
    env.pop("POKI_HTTP_ENDPOINT_HOST", None)
    if opt_in:
        env["POKI_HTTP_ENDPOINT_OPT_IN"] = "1"
        env["POKI_HTTP_ENDPOINT_HOST"] = host
    try:
        subprocess.run([binary, "generate", "--spec", os.path.join(SPEC, "project.yml"),
                        "--only-plists", "--quiet"], check=True, capture_output=True, env=env)
        with open(PLIST, "rb") as handle:
            return plistlib.load(handle).get("NSAppTransportSecurity"), "real XcodeGen plist"
    finally:
        if not existed and os.path.isfile(PLIST):
            os.remove(PLIST)


def spec_ats(path, host=None):
    text = open(path, encoding="utf-8").read()
    if host:
        text = text.replace("${POKI_HTTP_ENDPOINT_HOST}", host)
    try:
        import yaml
        return yaml.safe_load(text)["targets"]["Poki"]["info"]["properties"]["NSAppTransportSecurity"]
    except ImportError:
        return None


def render(opt_in, host):
    real, source = built_plist_ats(opt_in, host)
    if real is not None:
        return real, source
    base = spec_ats(BASE)
    opt = spec_ats(OPT_IN, host) if opt_in else None
    if base is None or (opt_in and opt is None):
        text = open(BASE, encoding="utf-8").read()
        result = {"NSAllowsLocalNetworking": "NSAllowsLocalNetworking: true" in text,
                  "forbidden": "NSAllowsArbitraryLoads: true" in text}
        if opt_in:
            opt_text = open(OPT_IN, encoding="utf-8").read().replace("${POKI_HTTP_ENDPOINT_HOST}", host)
            result["NSExceptionDomains"] = {host: {"NSExceptionAllowsInsecureHTTPLoads": True}}
            result["opt_in_text_ok"] = (host in opt_text
                                        and "NSExceptionAllowsInsecureHTTPLoads: true" in opt_text
                                        and "NSAllowsArbitraryLoads" not in opt_text)
        return result, "source text (no PyYAML, no XcodeGen)"
    merged = dict(base)
    if opt:
        merged["NSExceptionDomains"] = opt["NSExceptionDomains"]
    return plistlib.loads(plistlib.dumps(merged)), "spec rendering"


def assert_default():
    ats, source = render(False, "")
    print("\n=== Default build (" + source + ") ===")
    if "forbidden" in ats:
        check(not ats["forbidden"], "NSAllowsArbitraryLoads absent")
        check(ats.get("NSAllowsLocalNetworking") is True, "NSAllowsLocalNetworking present")
        return
    check("NSAllowsArbitraryLoads" not in ats, "NSAllowsArbitraryLoads absent")
    check(ats.get("NSAllowsLocalNetworking") is True, "NSAllowsLocalNetworking present")
    domains = ats.get("NSExceptionDomains", {})
    check(not domains, "no NSExceptionDomains entries by default", str(sorted(domains)))
    for host, entry in domains.items():
        check(entry.get("NSExceptionAllowsInsecureHTTPLoads") is not False,
              "no denylist entry for " + host)


def assert_opt_in(host):
    ats, source = render(True, host)
    print("\n=== Explicit opt-in for " + host + " (" + source + ") ===")
    if "opt_in_text_ok" in ats:
        check(ats["opt_in_text_ok"], "opt-in spec names exactly one host with insecure loads")
        check(not ats.get("forbidden"), "no global exception in opt-in build")
        return
    check("NSAllowsArbitraryLoads" not in ats, "no global exception in opt-in plist")
    check(ats.get("NSAllowsLocalNetworking") is True, "voice bridge exception preserved")
    domains = ats.get("NSExceptionDomains", {})
    check(set(domains) == {host}, "exactly one host", str(sorted(domains)))
    entry = domains.get(host, {})
    check(entry.get("NSExceptionAllowsInsecureHTTPLoads") is True,
          "insecure loads allowed only for that host")
    check(entry.get("NSIncludesSubdomains") is not True, "no subdomain widening")


def local_http_request():
    print("\n=== Real local HTTP ===")
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"poki-local-http-ok")
        def log_message(self, *_):
            pass
    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = "http://127.0.0.1:%d/v1/models" % server.server_port
    try:
        with urllib.request.urlopen(url, timeout=5) as response:
            body = response.read().decode()
            check(response.status == 200 and body == "poki-local-http-ok",
                  "GET " + url, "status=%d body=%r" % (response.status, body))
    except Exception as error:
        check(False, "GET " + url, repr(error))
    finally:
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()


def existing_https_request():
    print("\n=== Existing HTTPS request ===")
    # raw.githubusercontent.com is a host the app really loads: ProxyApps.modulesBase and
    # DDI.mirror. A failure here fails the check; a skipped request is not a verified request.
    url = "https://raw.githubusercontent.com/JosssphZhou/poki/main/native/ios-app/VERSION"
    try:
        with urllib.request.urlopen(url, timeout=10, context=ssl.create_default_context()) as response:
            body = response.read().decode().strip()
            check(response.status == 200 and bool(body), "TLS GET " + url,
                  "status=%d body=%r" % (response.status, body))
    except Exception as error:
        check(False, "TLS GET " + url, repr(error))


def main():
    host = os.environ.get("POKI_HTTP_ENDPOINT_HOST", "203.0.113.9")
    assert_default()
    assert_opt_in(host)
    local_http_request()
    existing_https_request()
    print("\n" + ("%d failure(s)" % len(FAILURES) if FAILURES else "all checks passed"))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
