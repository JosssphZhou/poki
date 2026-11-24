#!/usr/bin/env python3
"""Verify the App Transport Security scope of the plain-HTTP Custom Endpoint opt-in.

Checks:
  1. Both project.yml and project-external.yml keep NSAllowsArbitraryLoads and denylists absent,
     even if an invalid ambient POKI_HTTP_ENDPOINT_HOST is present without opt-in.
  2. NSAllowsLocalNetworking stays on for the voice bridge and loopback services.
  3. An explicit opt-in enforces the single-host contract via preGenCommand (matching
     src/install/http-endpoint.mjs and desktop/core/src/sign/mod.rs), adds exactly one
     canonical NSExceptionDomains host with insecure loads allowed and no subdomain widening,
     and wires the Poki target pre-build plist check.
  4. Invalid, empty/unset, multi-host, wildcard, CIDR, bracketed, zoned, or non-canonical
     POKI_HTTP_ENDPOINT_HOST values fail loudly without writing Poki/Info.plist.
  5. Direct --plist validation accepts valid opt-in Info.plist files and rejects tampered ones.
  6. A real cleartext HTTP request to a local server succeeds (bypassing any ambient HTTP proxy).
  7. A real HTTPS request to a host the app already uses succeeds.

When the XCODEGEN environment variable names an XcodeGen binary (or xcodegen is on PATH), the
script generates the real Poki/Info.plist for both top-level specs and restores any pre-existing
plists afterwards. Otherwise it resolves each spec's include graph, executes preGenCommand, and
serializes the ATS dictionary through plistlib.
"""

import http.server
import importlib.util
import os
import plistlib
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC_DIR = os.path.join(ROOT, "native", "ios-app")
TOP_SPECS = ("project.yml", "project-external.yml")
BASE = os.path.join(SPEC_DIR, "project-base.yml")
OPT_IN = os.path.join(SPEC_DIR, "project-http-endpoint.yml")
VALIDATOR_SCRIPT = os.path.join(SPEC_DIR, "scripts", "validate-http-endpoint-host.py")
GENERATED_PLISTS = (
    os.path.join(SPEC_DIR, "Poki", "Info.plist"),
    os.path.join(SPEC_DIR, "PokiWidgets", "Info.plist"),
    os.path.join(SPEC_DIR, "PokiTunnel", "Info.plist"),
)
PLIST = GENERATED_PLISTS[0]
VAR_RE = re.compile(r"\$\{([^{}]+)\}")
FAILURES = []

VALID_CANONICAL_HOSTS = (
    "203.0.113.9",
    "2001:db8:12::34",
    "::ffff:203.0.113.9",
    "gateway.example.com",
    "my-mac.local",
    "xn--bcher-kva.example",
    "devbox",
)

INVALID_HOSTS = (
    None,
    "",
    "   ",
    ".",
    "..",
    "http://gateway.example.com",
    "https://gateway.example.com",
    "gateway.example.com:3425",
    "gateway.example.com:",
    "gateway.example.com:abc",
    "gateway.example.com:80:80",
    "dead:beef",
    "[2001:db8:12::34]",
    "[2001:db8:12::34]:3425",
    "fe80::1%en0",
    ":::",
    "192.168.1.0/24",
    "2001:db8:12::/48",
    "999.999.999.999",
    "127.1",
    "01.2.3.4",
    "3405803785",
    "203.0.113.9.",
    "::ffff:01.2.3.4",
    ".example.com",
    "example..com",
    "example.com..",
    "-bad.example.com",
    "bad-.example.com",
    "*.example.com",
    "a" * 64 + ".example.com",
    "a." * 127 + "com",
    "203.0.113.9,evil.com",
    "${POKI_HTTP_ENDPOINT_HOST}",
    "gateway.example.com/v1",
    "user@gateway.example.com",
    "gateway.example.com?x=1",
    "gateway.example.com#f",
    "has space",
    "203.0.113.9\n",
    "; id",
    "$(id)",
    "bücher.example",
    "\u212a.example.com",
)

NON_CANONICAL_HOSTS = (
    ("Gateway.Example.COM", "gateway.example.com"),
    ("Gateway.Example.COM.", "gateway.example.com"),
    (" 203.0.113.9 ", "203.0.113.9"),
    ("2001:0DB8:0012:0:0:0:0:0034", "2001:db8:12::34"),
    ("2001:0db8:0012:0:0:0:0:0034", "2001:db8:12::34"),
    ("::ffff:cb00:7109", "::ffff:203.0.113.9"),
)


def _load_validator():
    prev = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("validate_http_endpoint_host", VALIDATOR_SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.dont_write_bytecode = prev


VALIDATOR = _load_validator()


def check(ok, label, detail=""):
    print(("PASS  " if ok else "FAIL  ") + label + (("  " + detail) if detail else ""))
    if not ok:
        FAILURES.append(label)


def is_valid_exception_host(value):
    return VALIDATOR.is_valid_exception_host(value)


def _build_env(opt_in, host, ambient_host=None):
    env = dict(os.environ)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env.pop("POKI_HTTP_ENDPOINT_OPT_IN", None)
    env.pop("POKI_HTTP_ENDPOINT_HOST", None)
    if opt_in:
        env["POKI_HTTP_ENDPOINT_OPT_IN"] = "1"
        if host is not None:
            env["POKI_HTTP_ENDPOINT_HOST"] = host
    elif ambient_host is not None:
        env["POKI_HTTP_ENDPOINT_HOST"] = ambient_host
    return env


def run_pre_gen_command(command, opt_in, host, ambient_host=None):
    return subprocess.run(
        ["bash", "-c", command],
        cwd=SPEC_DIR,
        env=_build_env(opt_in, host, ambient_host=ambient_host),
        capture_output=True,
        text=True,
    )


def built_plist_ats(spec_name, opt_in, host, ambient_host=None):
    binary = os.environ.get("XCODEGEN") or shutil.which("xcodegen")
    if not binary:
        return None, None, {}, "spec rendering", ""
    saved = {}
    for path in GENERATED_PLISTS:
        saved[path] = open(path, "rb").read() if os.path.isfile(path) else None
    env = _build_env(opt_in, host, ambient_host=ambient_host)
    try:
        proc = subprocess.run(
            [binary, "generate", "--spec", os.path.join(SPEC_DIR, spec_name), "--only-plists", "--quiet"],
            capture_output=True,
            text=True,
            env=env,
        )
        if proc.returncode != 0:
            plist_untouched = (
                (not os.path.isfile(PLIST))
                if saved[PLIST] is None
                else (os.path.isfile(PLIST) and open(PLIST, "rb").read() == saved[PLIST])
            )
            detail = (proc.stderr or proc.stdout).strip()
            return False, None, {"plist_untouched": plist_untouched}, "real XcodeGen plist", detail
        with open(PLIST, "rb") as handle:
            ats = plistlib.load(handle).get("NSAppTransportSecurity")
        # Read preGenCommand / preBuildScripts from YAML if available so hook checks still run.
        meta = {}
        try:
            import yaml  # noqa: F401
            _, _, yaml_meta, _, _ = render_with_yaml(
                spec_name, opt_in, host, ambient_host=ambient_host, run_hooks=False
            )
            meta.update(yaml_meta)
        except ImportError:
            pass
        return True, ats, meta, "real XcodeGen plist", ""
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
        elif isinstance(out.get(key), list) and isinstance(value, list):
            out[key] = out[key] + value
        else:
            out[key] = value
    return out


def expand_vars(value, env):
    if isinstance(value, dict):
        return {expand_vars(k, env): expand_vars(v, env) for k, v in value.items()}
    if isinstance(value, list):
        return [expand_vars(item, env) for item in value]
    if isinstance(value, str):
        return VAR_RE.sub(lambda m: env[m.group(1)] if m.group(1) in env else m.group(0), value)
    return value


def render_with_yaml(spec_name, opt_in, host, ambient_host=None, run_hooks=True):
    try:
        import yaml
    except ImportError:
        return None
    env = {}
    if opt_in:
        env["POKI_HTTP_ENDPOINT_OPT_IN"] = "1"
        if host is not None:
            env["POKI_HTTP_ENDPOINT_HOST"] = host
    elif ambient_host is not None:
        env["POKI_HTTP_ENDPOINT_HOST"] = ambient_host

    def load_spec(path):
        doc = yaml.safe_load(open(path, encoding="utf-8").read()) or {}
        doc = expand_vars(doc, env)
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
    pre_gen = merged_doc.get("options", {}).get("preGenCommand")
    pre_build = merged_doc.get("targets", {}).get("Poki", {}).get("preBuildScripts", [])
    meta = {"pre_gen": pre_gen, "pre_build": pre_build}
    if run_hooks and pre_gen:
        proc = run_pre_gen_command(pre_gen, opt_in, host, ambient_host=ambient_host)
        if proc.returncode != 0:
            return False, None, meta, "spec rendering", (proc.stderr or proc.stdout).strip()
    ats = merged_doc["targets"]["Poki"]["info"]["properties"]["NSAppTransportSecurity"]
    return True, plistlib.loads(plistlib.dumps(ats)), meta, "spec rendering", ""


def _parse_fallback_pre_gen(opt_text):
    match = re.search(r"^\s*preGenCommand:\s*(.+?)\s*$", opt_text, re.MULTILINE)
    return match.group(1) if match else None


def render(spec_name, opt_in, host, ambient_host=None):
    ok, ats, meta, source, err = built_plist_ats(spec_name, opt_in, host, ambient_host=ambient_host)
    if ok is not None:
        return ok, ats, meta, source, err
    rendered = render_with_yaml(spec_name, opt_in, host, ambient_host=ambient_host)
    if rendered is not None:
        return rendered

    top_text = open(os.path.join(SPEC_DIR, spec_name), encoding="utf-8").read()
    base_text = open(BASE, encoding="utf-8").read()
    opt_text = open(OPT_IN, encoding="utf-8").read()
    has_base = "project-base.yml" in top_text
    has_gated_opt_in = (
        "path: project-http-endpoint.yml" in top_text
        and "enable: ${POKI_HTTP_ENDPOINT_OPT_IN}" in top_text
    )
    pre_gen = _parse_fallback_pre_gen(opt_text)
    has_pre_build = (
        "preBuildScripts:" in opt_text
        and "validate-http-endpoint-host.py" in opt_text
        and "--plist" in opt_text
        and "$SRCROOT" in opt_text
        and "${SRCROOT}" not in opt_text
    )
    no_unintended_hooks = (
        "preGenCommand" not in base_text
        and "preBuildScripts" not in base_text
        and "preGenCommand" not in top_text
        and "preBuildScripts" not in top_text
    )
    meta = {
        "pre_gen": pre_gen if opt_in else None,
        "has_pre_build": has_pre_build if opt_in else False,
        "no_unintended_hooks": no_unintended_hooks,
    }
    if opt_in:
        if not pre_gen:
            return False, None, meta, "source text (no PyYAML, no XcodeGen)", "missing preGenCommand"
        proc = run_pre_gen_command(pre_gen, True, host, ambient_host=ambient_host)
        if proc.returncode != 0:
            return False, None, meta, "source text (no PyYAML, no XcodeGen)", (proc.stderr or proc.stdout).strip()
    result = {
        "NSAllowsLocalNetworking": has_base and ("NSAllowsLocalNetworking: true" in base_text),
        "forbidden": ("NSAllowsArbitraryLoads" in base_text) or ("NSAllowsArbitraryLoads" in top_text) or not has_gated_opt_in,
    }
    if opt_in:
        sub_host = host if host is not None else "${POKI_HTTP_ENDPOINT_HOST}"
        rendered_opt = opt_text.replace("${POKI_HTTP_ENDPOINT_HOST}", sub_host)
        result["NSExceptionDomains"] = plistlib.loads(
            plistlib.dumps({sub_host: {"NSExceptionAllowsInsecureHTTPLoads": True}})
        )
        result["opt_in_text_ok"] = (
            has_gated_opt_in
            and has_pre_build
            and ('"%s":' % sub_host in rendered_opt)
            and "NSExceptionAllowsInsecureHTTPLoads: true" in rendered_opt
            and "NSAllowsArbitraryLoads" not in rendered_opt
            and "NSIncludesSubdomains" not in rendered_opt
        )
    return True, result, meta, "source text (no PyYAML, no XcodeGen)", ""


def _pre_build_hook_ok(meta):
    if "has_pre_build" in meta:
        return meta["has_pre_build"]
    scripts = meta.get("pre_build") or []
    return any(
        isinstance(s, dict)
        and "validate-http-endpoint-host.py" in str(s.get("script", ""))
        and "--plist" in str(s.get("script", ""))
        and "$SRCROOT" in str(s.get("script", ""))
        and "${SRCROOT}" not in str(s.get("script", ""))
        for s in scripts
    )


def assert_default(spec_name):
    ok, ats, meta, source, err = render(spec_name, False, "", ambient_host="http://evil.example.com")
    print("\n=== Default build [%s] (%s) ===" % (spec_name, source))
    check(ok, "%s: default build succeeds despite invalid ambient POKI_HTTP_ENDPOINT_HOST" % spec_name, err)
    if not ok or ats is None:
        return
    if "no_unintended_hooks" in meta:
        check(meta["no_unintended_hooks"], "%s: default build leaves validation hooks out" % spec_name)
    else:
        check(not meta.get("pre_gen"), "%s: default build has no preGenCommand" % spec_name)
        check(not meta.get("pre_build"), "%s: default build has no preBuildScripts" % spec_name)
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
    ok, ats, meta, source, err = render(spec_name, True, host)
    print("\n=== Explicit opt-in [%s] for %s (%s) ===" % (spec_name, host, source))
    check(is_valid_exception_host(host), "%s: %s is a valid canonical ATS host key" % (spec_name, host))
    check(ok, "%s: XcodeGen opt-in accepts %s" % (spec_name, host), err)
    if not ok or ats is None:
        return
    if source != "real XcodeGen plist" or meta:
        check(bool(meta.get("pre_gen")), "%s: preGenCommand is wired for %s" % (spec_name, host))
        check(_pre_build_hook_ok(meta), "%s: preBuildScripts plist check is wired for %s" % (spec_name, host))
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


def assert_opt_in_rejected(spec_name, raw_host, expected_canonical=None):
    ok, _, meta, source, err = render(spec_name, True, raw_host)
    label = "%s: rejects %r (%s)" % (spec_name, raw_host, source)
    check(not ok and bool(err), label, err if ok else "")
    if "plist_untouched" in meta:
        check(meta["plist_untouched"], "%s: failed opt-in for %r leaves Poki/Info.plist untouched" % (spec_name, raw_host))
    if expected_canonical is not None:
        check(expected_canonical in err,
              "%s: non-canonical %r names %r" % (spec_name, raw_host, expected_canonical),
              err)


def assert_plist_validator():
    print("\n=== Direct --plist build-phase validator ===")

    def run_plist(ats_dict, fmt=plistlib.FMT_XML):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "Info.plist")
            with open(path, "wb") as handle:
                plistlib.dump({"NSAppTransportSecurity": ats_dict}, handle, fmt=fmt)
            return subprocess.run(
                [sys.executable, VALIDATOR_SCRIPT, "--plist", path],
                env=_build_env(False, None),
                capture_output=True,
                text=True,
            )

    for fmt_name, fmt in (("XML", plistlib.FMT_XML), ("binary", plistlib.FMT_BINARY)):
        res = run_plist({
            "NSAllowsLocalNetworking": True,
            "NSExceptionDomains": {"203.0.113.9": {"NSExceptionAllowsInsecureHTTPLoads": True}},
        }, fmt=fmt)
        check(res.returncode == 0, "--plist accepts valid %s opt-in Info.plist" % fmt_name, res.stderr.strip())

    bad_plists = [
        ("invalid host", {"NSExceptionDomains": {"http://evil.example.com": {"NSExceptionAllowsInsecureHTTPLoads": True}}}),
        ("non-canonical host", {"NSExceptionDomains": {"Gateway.Example.COM": {"NSExceptionAllowsInsecureHTTPLoads": True}}}),
        ("unexpanded variable", {"NSExceptionDomains": {"${POKI_HTTP_ENDPOINT_HOST}": {"NSExceptionAllowsInsecureHTTPLoads": True}}}),
        ("zero hosts", {"NSAllowsLocalNetworking": True, "NSExceptionDomains": {}}),
        ("two hosts", {"NSExceptionDomains": {"203.0.113.9": {"NSExceptionAllowsInsecureHTTPLoads": True}, "gateway.example.com": {"NSExceptionAllowsInsecureHTTPLoads": True}}}),
        ("subdomain widening", {"NSExceptionDomains": {"gateway.example.com": {"NSExceptionAllowsInsecureHTTPLoads": True, "NSIncludesSubdomains": True}}}),
        ("global arbitrary loads", {"NSAllowsArbitraryLoads": True, "NSExceptionDomains": {"203.0.113.9": {"NSExceptionAllowsInsecureHTTPLoads": True}}}),
        ("denylist entry", {"NSExceptionDomains": {"203.0.113.9": {"NSExceptionAllowsInsecureHTTPLoads": False}}}),
    ]
    for case_name, ats_dict in bad_plists:
        res = run_plist(ats_dict)
        check(res.returncode != 0 and bool(res.stderr.strip()), "--plist rejects %s" % case_name, res.stderr.strip())


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
    hosts = [env_host] if env_host is not None else list(VALID_CANONICAL_HOSTS)
    for spec_name in TOP_SPECS:
        assert_default(spec_name)
        for host in hosts:
            assert_opt_in(spec_name, host)
        print("\n=== Reject invalid and non-canonical hosts [%s] ===" % spec_name)
        for bad in INVALID_HOSTS:
            assert_opt_in_rejected(spec_name, bad)
        for raw_host, canonical in NON_CANONICAL_HOSTS:
            assert_opt_in_rejected(spec_name, raw_host, expected_canonical=canonical)
    assert_plist_validator()
    local_http_request()
    existing_https_request()
    print("\n" + ("%d failure(s)" % len(FAILURES) if FAILURES else "all checks passed"))
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
