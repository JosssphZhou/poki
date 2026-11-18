import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Whether a Custom Endpoint address may use cleartext HTTP.
///
/// The built app keeps ATS on. `NSAllowsLocalNetworking` already permits plain HTTP to the voice
/// bridge, loopback and LAN hosts. Poki grants cleartext to named hosts when the owner opts in
/// with `--allow-http-host` (signing) or `POKI_HTTP_ENDPOINT_HOST` (build). Each opted-in host
/// appears in `NSExceptionDomains` with `NSExceptionAllowsInsecureHTTPLoads` set to YES. Every
/// other host keeps full ATS.
enum PlainHTTPPolicy {
    static func isAllowed(_ address: String, ats: [String: Any]? = appTransportSecurity()) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http",
              let rawHost = parts.host, !rawHost.isEmpty, rawHost != "[]" else { return true }
        let host = canonicalHost(rawHost)
        if let entry = matchingExceptionEntry(for: host, in: ats?["NSExceptionDomains"] as? [String: Any]) {
            return entry["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true
        }
        if ats?["NSAllowsArbitraryLoads"] as? Bool == true { return true }
        return ats?["NSAllowsLocalNetworking"] as? Bool == true && isLocal(rawHost)
    }

    /// The hosts `NSAllowsLocalNetworking` covers: loopback, private/link-local IPv4 and IPv6
    /// (including zoned `fe80::/10` and local IPv4-mapped `::ffff:0:0/96`), `.local`/`.localhost`
    /// names, and unqualified RFC 1123 hostnames.
    static func isLocal(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix(".") && !host.hasSuffix("..") {
            let withoutRoot = String(host.dropLast())
            if isDNSHost(withoutRoot) { host = withoutRoot }
        }
        guard !host.isEmpty else { return false }

        if host.contains(":") {
            return isLocalIPv6(host)
        }

        var four = in_addr()
        if inet_pton(AF_INET, host, &four) == 1 {
            return withUnsafeBytes(of: four.s_addr) { bytes in
                let b = bytes.bindMemory(to: UInt8.self)
                return isLocalIPv4(b[0], b[1], b[2], b[3])
            }
        }
        // Non-canonical numeric/hex/octal IPv4 forms (e.g. 3405803785, 0xcb007109, 127.1) are
        // never unqualified DNS hostnames.
        if inet_aton(host, &four) == 1 { return false }

        guard isDNSHost(host) else { return false }
        return !host.contains(".")
            || host == "localhost"
            || (host.count > ".localhost".count && host.hasSuffix(".localhost"))
            || (host.count > ".local".count && host.hasSuffix(".local"))
    }

    static func appTransportSecurity() -> [String: Any]? {
        Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
    }

    /// Normalizes a URL host (including bracketed or uncompressed IPv6 and trailing-dot FQDNs) to
    /// the lowercase canonical key form `NSExceptionDomains` uses.
    private static func canonicalHost(_ rawHost: String) -> String {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix(".") && !host.hasSuffix("..") {
            let withoutRoot = String(host.dropLast())
            if isDNSHost(withoutRoot) { host = withoutRoot }
        }
        if host.contains(":"), !host.contains("%") {
            var six = in6_addr()
            if inet_pton(AF_INET6, host, &six) == 1 {
                var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                if inet_ntop(AF_INET6, &six, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                    return String(cString: buf).lowercased()
                }
            }
        }
        return host
    }

    /// Looks up the most specific `NSExceptionDomains` entry for `host`, honoring
    /// `NSIncludesSubdomains` on parent DNS domains.
    private static func matchingExceptionEntry(for host: String, in domains: [String: Any]?) -> [String: Any]? {
        guard let domains, !host.isEmpty else { return nil }
        if let exact = domains[host] as? [String: Any] { return exact }
        var normalized: [String: [String: Any]] = [:]
        for (key, value) in domains {
            guard let entry = value as? [String: Any] else { continue }
            normalized[canonicalHost(key)] = entry
        }
        if let exact = normalized[host] { return exact }
        guard isDNSHost(host) else { return nil }
        var rest = host[...]
        while let dot = rest.firstIndex(of: ".") {
            rest = rest[rest.index(after: dot)...]
            let parent = String(rest)
            if let entry = normalized[parent], entry["NSIncludesSubdomains"] as? Bool == true {
                return entry
            }
        }
        return nil
    }

    private static func isLocalIPv6(_ rawHost: String) -> Bool {
        var host = rawHost
        if let zone = host.firstIndex(of: "%") {
            let zoneID = host[host.index(after: zone)...]
            guard !zoneID.isEmpty else { return false }
            host = String(host[..<zone])
        }
        var six = in6_addr()
        guard inet_pton(AF_INET6, host, &six) == 1 else { return false }
        return withUnsafeBytes(of: six) { bytes in
            let b = bytes.bindMemory(to: UInt8.self)
            // ::1 (loopback)
            if (0..<15).allSatisfy({ b[$0] == 0 }) && b[15] == 1 { return true }
            // fc00::/7 (unique local addresses, including fd00::/8)
            if b[0] & 0xfe == 0xfc { return true }
            // fe80::/10 (link-local, with or without a zone ID)
            if b[0] == 0xfe && b[1] & 0xc0 == 0x80 { return true }
            // ::ffff:0:0/96 (IPv4-mapped IPv6 targeting a local IPv4 range)
            if (0..<10).allSatisfy({ b[$0] == 0 }) && b[10] == 0xff && b[11] == 0xff {
                return isLocalIPv4(b[12], b[13], b[14], b[15])
            }
            return false
        }
    }

    private static func isLocalIPv4(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) -> Bool {
        if b0 == 10 || b0 == 127 { return true }
        if b0 == 192 && b1 == 168 { return true }
        if b0 == 172 && (16...31).contains(b1) { return true }
        if b0 == 169 && b1 == 254 { return true }
        return false
    }

    private static func isDNSHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if let last = labels.last, !last.isEmpty,
           last.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) {
            return false
        }
        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            guard !bytes.isEmpty, bytes.count <= 63 else { return false }
            let isAlnum: (UInt8) -> Bool = {
                (UInt8(ascii: "a")...UInt8(ascii: "z")).contains($0)
                    || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0)
            }
            guard isAlnum(bytes[0]), isAlnum(bytes[bytes.count - 1]) else { return false }
            return bytes.allSatisfy { isAlnum($0) || $0 == UInt8(ascii: "-") }
        }
    }
}
