import { isIPv4, isIPv6 } from 'node:net';

// The explicit opt-in for a plain-HTTP Custom Endpoint host. Poki Setup passes at most one
// canonical host to the signing bridge through POKI_HTTP_ENDPOINT_HOST, which injects one
// NSExceptionDomains entry into the signed app's Info.plist. The rules mirror
// desktop/core/src/sign/mod.rs and native/ios-app/scripts/validate-http-endpoint-host.py.

const DNS_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

function isDnsHost(value) {
    if (!value || value.length > 253) return false;
    const labels = value.split('.');
    // An all-numeric final label is an IPv4 form (or malformed IPv4), never a valid DNS TLD/host.
    if (/^\d+$/.test(labels[labels.length - 1])) return false;
    return labels.every(label => DNS_LABEL.test(label));
}

function canonicalizeIpv6(value) {
    const host = new URL(`http://[${value}]/`).hostname.slice(1, -1);
    const mapped = /^::ffff:([0-9a-f]{1,4}):([0-9a-f]{1,4})$/.exec(host);
    if (!mapped) return host;
    const hi = Number.parseInt(mapped[1], 16);
    const lo = Number.parseInt(mapped[2], 16);
    return `::ffff:${(hi >> 8) & 0xff}.${hi & 0xff}.${(lo >> 8) & 0xff}.${lo & 0xff}`;
}

export function normalizeHttpHost(raw) {
    let value = String(raw).trim().toLowerCase();
    // Strip a single root dot on FQDNs ("gateway.example.com."), never on IP literals or "..".
    if (value.endsWith('.') && !value.endsWith('..')) {
        const withoutRoot = value.slice(0, -1);
        if (isDnsHost(withoutRoot)) value = withoutRoot;
    }
    if (isHttpHost(value) && value.includes(':')) value = canonicalizeIpv6(value);
    return value;
}

export function normalizeHttpHosts(values) {
    const out = [];
    const seen = new Set();
    for (const raw of values) {
        const value = normalizeHttpHost(raw);
        if (!isHttpHost(value)) {
            throw new Error(`--allow-http-host takes a DNS name or IP literal, without a scheme, port, brackets, zone, mask, path or userinfo: ${value}`);
        }
        if (!seen.has(value)) {
            seen.add(value);
            out.push(value);
        }
    }
    if (out.length > 1) {
        throw new Error(`--allow-http-host accepts at most one distinct host; got ${out.join(', ')}.`);
    }
    return out;
}

export function isHttpHost(value) {
    if (typeof value !== 'string' || !value) return false;
    // Lowercase ASCII only: NSExceptionDomains matches lowercase ASCII/Punycode host keys, without
    // scheme, port, brackets, zone ID, CIDR prefix (subnet-wide on iOS 17+), path, query or userinfo.
    if (!/^[a-z0-9.:-]+$/.test(value)) return false;
    if (value.includes(':')) {
        return /^[0-9a-f:.]+$/.test(value) && isIPv6(value);
    }
    if (isIPv4(value)) return true;
    return isDnsHost(value);
}
