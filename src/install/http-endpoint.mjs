// The explicit opt-in for a plain-HTTP Custom Endpoint host. Poki Setup passes these to the
// signing bridge through POKI_HTTP_ENDPOINT_HOST, which injects one NSExceptionDomains entry per
// host into the signed app's Info.plist. The rules mirror desktop/core/src/sign/mod.rs.

export function normalizeHttpHosts(values) {
    return values.map(value => value.trim().toLowerCase().replace(/\.+$/, ''));
}

export function isHttpHost(value) {
    if (!value || value.includes('://') || value.includes('@') || value.includes('?')
        || value.includes('#') || /\s/.test(value)) return false;
    // No path or CIDR mask: an NSExceptionDomains key names one host and matches it literally.
    if (value.includes('/')) return false;
    // "host:port" is not a host. One colon can never be a host: IPv6 literals have at least two.
    if ((value.match(/:/g) ?? []).length === 1) return false;
    return true;
}
