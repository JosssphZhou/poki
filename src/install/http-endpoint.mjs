// The explicit opt-in for a plain-HTTP Custom Endpoint host. Poki Setup passes these to the
// signing bridge through POKI_HTTP_ENDPOINT_HOST, which injects one NSExceptionDomains entry per
// host into the signed app's Info.plist. The rules mirror desktop/core/src/sign/mod.rs.

export function normalizeHttpHosts(values) {
    return values.map(value => value.trim().toLowerCase().replace(/\.+$/, ''));
}

export function isHttpHost(value) {
    if (!value || value.includes('://') || value.includes('@') || value.includes('?')
        || value.includes('#') || /\s/.test(value)) return false;
    const parts = value.split('/');
    if (parts.length > 2) return false;
    if (parts.length === 2 && (!parts[1] || !/^\d+$/.test(parts[1]))) return false;
    // "host:port" is not a host. IPv6 literals and CIDR ranges keep their colons.
    if (parts.length === 1 && (value.match(/:/g) ?? []).length === 1) {
        const port = value.slice(value.lastIndexOf(':') + 1);
        if (port && /^\d+$/.test(port)) return false;
    }
    return true;
}
