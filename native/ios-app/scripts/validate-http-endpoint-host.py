#!/usr/bin/env python3
"""Validate and canonicalize a single NSExceptionDomains host for Poki's plain-HTTP opt-in.

Matches the single-host contract enforced by src/install/http-endpoint.mjs and
desktop/core/src/sign/mod.rs:
  - canonical lowercase ASCII RFC 1123 DNS hostname (no trailing dot), or
  - canonical dotted-quad IPv4 literal, or
  - canonical RFC 5952 lowercase unbracketed, unzoned IPv6 literal (with ::ffff:a.b.c.d
    dotted-quad formatting for IPv4-mapped IPv6 addresses).

Used by XcodeGen's preGenCommand and target pre-build script when POKI_HTTP_ENDPOINT_OPT_IN is
enabled, and imported by scripts/check-ats-scope.py. Compatible with Python 3.9+.
"""

import argparse
import ipaddress
import os
import plistlib
import re
import sys

DNS_LABEL_RE = re.compile(r"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")
ALLOWED_HOST_CHARS_RE = re.compile(r"^[a-z0-9.:-]+$")
IPV6_CHARS_RE = re.compile(r"^[0-9a-f:.]+$")
IPV4_CANDIDATE_RE = re.compile(r"^[0-9]+(?:\.[0-9]+){3}$")


def _canonical_ipv6(addr):
    if addr.ipv4_mapped is not None:
        return "::ffff:%s" % (addr.ipv4_mapped,)
    return str(addr)


def _is_canonical_ipv4(value):
    if not IPV4_CANDIDATE_RE.fullmatch(value):
        return False
    try:
        addr = ipaddress.IPv4Address(value)
    except ValueError:
        return False
    return str(addr) == value


def is_dns_host(value):
    if not value or len(value) > 253:
        return False
    labels = value.split(".")
    if labels[-1] and all("0" <= ch <= "9" for ch in labels[-1]):
        return False
    return all(DNS_LABEL_RE.fullmatch(label) is not None for label in labels)


def normalize_exception_host(raw):
    """Normalize raw input to a canonical ATS host key, or return None if invalid."""
    if not isinstance(raw, str) or not raw.isascii():
        return None
    value = raw.strip().lower()
    if value.endswith(".") and not value.endswith(".."):
        without_root = value[:-1]
        if is_dns_host(without_root):
            value = without_root
    if not value or not ALLOWED_HOST_CHARS_RE.fullmatch(value):
        return None
    if ":" in value:
        if not IPV6_CHARS_RE.fullmatch(value):
            return None
        if "." in value:
            tail = value.rsplit(":", 1)[1]
            if not _is_canonical_ipv4(tail):
                return None
        try:
            addr = ipaddress.IPv6Address(value)
        except ValueError:
            return None
        return _canonical_ipv6(addr)
    if IPV4_CANDIDATE_RE.fullmatch(value):
        return value if _is_canonical_ipv4(value) else None
    return value if is_dns_host(value) else None


def is_valid_exception_host(value):
    """Return True iff value is already a canonical ATS exception host."""
    return isinstance(value, str) and normalize_exception_host(value) == value


def validate_host(raw, source="POKI_HTTP_ENDPOINT_HOST"):
    """Validate that raw is a non-empty, valid, already-canonical single host."""
    if raw is None or raw == "":
        raise ValueError(
            "%s must be set to one canonical DNS name or IP literal when "
            "POKI_HTTP_ENDPOINT_OPT_IN is enabled." % (source,)
        )
    canonical = normalize_exception_host(raw)
    if canonical is None:
        raise ValueError(
            "Invalid %s %r: expected one canonical DNS name or IP literal, without scheme, "
            "port, brackets, zone ID, CIDR mask, path, query, fragment, userinfo or "
            "comma-separated list." % (source, raw)
        )
    if canonical != raw:
        raise ValueError(
            "Non-canonical %s %r: XcodeGen copies the host verbatim into "
            "NSExceptionDomains; pass %r instead." % (source, raw, canonical)
        )
    return canonical


def validate_plist(plist_path):
    """Validate that a generated Info.plist grants plain HTTP to exactly one canonical host."""
    with open(plist_path, "rb") as handle:
        info = plistlib.load(handle)
    if not isinstance(info, dict):
        raise ValueError("Invalid Info.plist root in %s." % (plist_path,))
    ats = info.get("NSAppTransportSecurity")
    if not isinstance(ats, dict):
        raise ValueError("Missing NSAppTransportSecurity dictionary in %s." % (plist_path,))
    if "NSAllowsArbitraryLoads" in ats:
        raise ValueError("Unexpected NSAllowsArbitraryLoads key in %s." % (plist_path,))
    domains = ats.get("NSExceptionDomains")
    if not isinstance(domains, dict) or len(domains) != 1:
        raise ValueError(
            "Expected exactly one NSExceptionDomains entry in %s, found %d."
            % (plist_path, len(domains) if isinstance(domains, dict) else 0)
        )
    host, entry = next(iter(domains.items()))
    validate_host(host, source="NSExceptionDomains key")
    if not isinstance(entry, dict) or entry.get("NSExceptionAllowsInsecureHTTPLoads") is not True:
        raise ValueError(
            "Expected NSExceptionAllowsInsecureHTTPLoads=true for %r in %s." % (host, plist_path)
        )
    if entry.get("NSIncludesSubdomains") is True:
        raise ValueError(
            "Unexpected NSIncludesSubdomains=true for %r in %s." % (host, plist_path)
        )
    return host


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Validate POKI_HTTP_ENDPOINT_HOST or a generated Info.plist for ATS opt-in."
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--host",
        help="Validate the given host string instead of POKI_HTTP_ENDPOINT_HOST.",
    )
    group.add_argument(
        "--plist",
        help="Validate NSExceptionDomains in a generated Info.plist.",
    )
    args = parser.parse_args(argv)
    try:
        if args.plist is not None:
            validate_plist(args.plist)
        elif args.host is not None:
            validate_host(args.host)
        else:
            validate_host(os.environ.get("POKI_HTTP_ENDPOINT_HOST"))
    except (ValueError, OSError, plistlib.InvalidFileException) as err:
        sys.stderr.write("error: %s\n" % (err,))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
