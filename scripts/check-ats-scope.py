#!/usr/bin/env python3
"""Verify the App Transport Security scope of the plain-HTTP Custom Endpoint opt-in.

Checks:
  1. Both project.yml and project-external.yml keep NSAllowsArbitraryLoads and denylists absent.
  2. NSAllowsLocalNetworking stays on for the voice bridge and loopback services.
  3. An explicit opt-in adds exactly one NSExceptionDomains host (IPv4, IPv6, and DNS), with
     insecure loads allowed and no subdomain widening.
  4. A real cleartext HTTP request to a local server succeeds (bypassing any ambient HTTP proxy).
  5. A real HTTPS request to a host the app already uses succeeds.

When the XCODEGEN environment variable names an XcodeGen binary (or xcodegen is on PATH), the
script generates the real Poki/Info.plist for both top-level specs and restores any pre-existing
plists afterwards. Otherwise it resolves each spec's include graph and serializes the ATS
dictionary through plistlib.
"""

import http.server
import ipaddress
import os
import plistlib
import re
import shutil
import ssl
import subprocess
import sys
import threading
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC_DIR = os.path.join(ROOT, "native", "ios-app")
TOP_SPECS = ("project.yml", "project-external.yml")
BASE = os.path.join(SPEC_DIR, "project-base.yml")
OPT_IN = os.path.join(SPEC_DIR, "project-http-endpoint.yml")
GENERATED_PLISTS = (
    os.path.join(SPEC_DIR, "Poki", "Info.plist"),
    os.path.join(SPEC_DIR, "PokiWidgets", "Info.plist"),
    os.path.join(SPEC_DIR, "PokiTunnel", "Info.plist"),
)
PLIST = GENERATED_PLISTS[0]
DNS_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
FAILURES = []


def check(ok, label, detail=""):
    print(("PASS  " if ok else "FAIL  ") + label + (("  " + detail) if detail else ""))
    if not ok:
        FAILURES.append(label)


def is_valid_exception_host(value):
    if not value or not re.fullmatch(r"[a-z0-9.:-]+", value):
        return False
    if ":" in value:
        if not re.fullmatch(r"[0-9a-f:.]+", value):
            return False
        try:
            addr = ipaddress.IPv6Address(value)
        except ValueError:
            return False
        return str(addr) == value
    if re.fullmatch(r"\d+(?:\.\d+){3}", value):
        try:
            addr = ipaddress.IPv4Address(value)
        except ValueError:
            return False
        return str(addr) == value
    if len(value) > 253:
        return False
    labels = value.split(".")
    if labels[-1].isdigit():
        return False
    return all(DNS_LABEL_RE.fullmatch(label) for label in labels)


def built_plist_ats(spec_name, opt_in, host):
    binary = os.environ.get("XCODEGEN") or shutil.which("xcodegen")
    if not binary:
        return None, "spec rendering"
    saved = {}
    for path in GENERATED_PLISTS:
        saved[path] = open(path, "rb").read() if os.path.isfile(path) else None
    env = dict(os.environ)
    env.pop("POKI_HTTP_ENDPOINT_OPT_IN", None)
    env.pop("POKI_HTTP_ENDPOINT_HOST", None)
    if opt_in:
        env["POKI_HTTP_ENDPOINT_OPT_IN"] = "1"
        env["POKI_HTTP_ENDPOINT_HOST"] = host
    try:
        subprocess.run(
            [binary, "generate", "--spec", os.path.join(SPEC_DIR, spec_name), "--only-plists", "--quiet"],
            check=True,
            capture_output=True,
            env=env,
        )
        with open(PLIST, "rb") as handle:
            return plistlib.load(handle).get("NSAppTransportSecurity"), "real XcodeGen plist"
    finally:
        for path, previous in saved.items():
            if previous is None:
                if os.path.isfile(path):
                    os.remove(path)
            else:
                with open(path, "wb") as handle:
                    handle.write(previous)


def resolve_boolean(raw):
    return str(raw).strip().lower() in ("1", "true", "yes")


def deep_merge(dst, src):
    out = dict(dst)
    for key, value in src.items():
        if isinstance(out.get(key), dict) and isinstance(value, dict):
            out[key] = deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def render_with_yaml(spec_name, opt_in, host):
    try:
        import yaml
    except ImportError:
        return None
    env = {}
    if opt_in:
        env["POKI_HTTP_ENDPOINT_OPT_IN"] = "1"
        env["POKI_HTTP_ENDPOINT_HOST"] = host

    def substitute(text):
        for name, val in env.items():
            text = text.replace("${%s}" % name, val)
        return text

    def load_spec(path):
        doc = yaml.safe_load(substitute(open(path, encoding="utf-8").read())) or {}
        merged = {}
        for item in doc.get("include", []):
            if isinstance(item, str):
                inc_path, enabled = item, True
            else:
                inc_path = item["path"]
                enabled = resolve_boolean(item.get("enable", True))
            if enabled:
                merged = deep_merge(merged, load_spec(os.path.join(os.path.dirname(path), inc_path)))
        doc_no_inc = {k: v for k, v in doc.items() if k != "include"}
        return deep_merge(merged, doc_no_inc)

    merged_doc = load_spec(os.path.join(SPEC_DIR, spec_name))
    ats = merged_doc["targets"]["Poki"]["info"]["properties"]["NSAppTransportSecurity"]
    return plistlib.loads(plistlib.dumps(ats))


def render(spec_name, opt_in, host):
    real, source = built_plist_ats(spec_name, opt_in, host)
    if real is not None:
        return real, source
    rendered = render_with_yaml(spec_name, opt_in, host)
    if rendered is not None:
        return rendered, "spec rendering"
    top_text = open(os.path.join(SPEC_DIR, spec_name), encoding="utf-8").read()
    base_text = open(BASE, encoding="utf-8").read()
    has_base = "project-base.yml" in top_text
    has_gated_opt_in = (
        "path: project-http-endpoint.yml" in top_text
        and "enable: ${POKI_HTTP_ENDPOINT_OPT_IN}" in top_text
    )
    result = {
        "NSAllowsLocalNetworking": has_base and ("NSAllowsLocalNetworking: true" in base_text),
        "forbidden": ("NSAllowsArbitraryLoads" in base_text) or ("NSAllowsArbitraryLoads" in top_text) or not has_gated_opt_in,
    }
    if opt_in:
        opt_text = open(OPT_IN, encoding="utf-8").read().replace("${POKI_HTTP_ENDPOINT_HOST}", host)
        result["NSExceptionDomains"] = plistlib.loads(
            plistlib.dumps({host: {"NSExceptionAllowsInsecureHTTPLoads": True}})
        )
        result["opt_in_text_ok"] = (
            has_gated_opt_in
            and ('"%s":' % host in opt_text)
            and "NSExceptionAllowsInsecureHTTPLoads: true" in opt_text
            and "NSAllowsArbitraryLoads" not in opt_text
            and "NSIncludesSubdomains" not in opt_text
        )
    return result, "source text (no PyYAML, no XcodeGen)"


def assert_default(spec_name):
    ats, source = render(spec_name, False, "")
    print("\n=== Default build [%s] (%s) ===" % (spec_name, source))
    if "forbidden" in ats:
        check(not ats["forbidden"], "%s: NSAllowsArbitraryLoads absent and opt-in gated" % spec_name)
        check(ats.get("NSAllowsLocalNetworking") is True, "%s: NSAllowsLocalNetworking present" % spec_name)
        return
    check("NSAllowsArbitraryLoads" not in ats, "%s: NSAllowsArbitraryLoads absent" % spec_name)
    check(ats.get("NSAllowsLocalNetworking") is True, "%s: NSAllowsLocalNetworking present" % spec_name)
    domains = ats.get("NSExceptionDomains", {})
    check(not domains, "%s: no NSExceptionDomains entries by default" % spec_name, str(sorted(domains)))
    for host, entry in domains.items():
        check(entry.get("NSExceptionAllowsInsecureHTTPLoads") is not False,
              "%s: no denylist entry for %s" % (spec_name, host))


def assert_opt_in(spec_name, host):
    ats, source = render(spec_name, True, host)
    print("\n=== Explicit opt-in [%s] for %s (%s) ===" % (spec_name, host, source))
    check(is_valid_exception_host(host), "%s: %s is a valid canonical ATS host key" % (spec_name, host))
    if "opt_in_text_ok" in ats:
        check(ats["opt_in_text_ok"], "%s: opt-in spec names exactly %s with insecure loads" % (spec_name, host))
        check(not ats.get("forbidden"), "%s: no global exception in opt-in build" % spec_name)
        return
    check("NSAllowsArbitraryLoads" not in ats, "%s: no global exception in opt-in plist" % spec_name)
    check(ats.get("NSAllowsLocalNetworking") is True, "%s: voice bridge exception preserved" % spec_name)
    domains = ats.get("NSExceptionDomains", {})
    check(set(domains) == {host}, "%s: exactly one host" % spec_name, str(sorted(domains)))
    entry = domains.get(host, {})
    check(entry.get("NSExceptionAllowsInsecureHTTPLoads") is True,
          "%s: insecure loads allowed only for %s" % (spec_name, host))
    check(entry.get("NSIncludesSubdomains") is not True, "%s: no subdomain widening" % spec_name)


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
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(url, timeout=5) as response:
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
    last_error = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=10, context=ssl.create_default_context()) as response:
                body = response.read().decode().strip()
                check(response.status == 200 and bool(body), "TLS GET " + url,
                      "status=%d body=%r" % (response.status, body))
                return
        except Exception as error:
            last_error = error
            if attempt < 2:
                time.sleep(1)
    check(False, "TLS GET " + url, repr(last_error))


def main():
    env_host = os.environ.get("POKI_HTTP_ENDPOINT_HOST")
    hosts = [env_host] if env_host is not None else ["203.0.113.9", "2001:db8:12::34", "gateway.example.com"]
    for spec_name in TOP_SPECS:
        assert_default(spec_name)
        for host in hosts:
            assert_opt_in(spec_name, host)
    local_http_request()
    existing_https_request()
    print("\n" + ("%d failure(s)" % len(FAILURES) if FAILURES else "all checks passed"))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
