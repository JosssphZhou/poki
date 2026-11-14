import Foundation

/// Whether a Custom Endpoint address may use cleartext HTTP.
///
/// The built app keeps ATS on. `NSAllowsLocalNetworking` already permits plain HTTP to the voice
/// bridge, loopback and LAN hosts. Poki grants cleartext to one more host when the owner opts in at
/// build time with POKI_HTTP_ENDPOINT_HOST. That host appears in NSExceptionDomains with
/// NSExceptionAllowsInsecureHTTPLoads set to YES. Every other host keeps full ATS.
enum PlainHTTPPolicy {
    static func isAllowed(_ address: String, ats: [String: Any]? = appTransportSecurity()) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http",
              let host = parts.host?.lowercased() else { return true }
        if let domains = ats?["NSExceptionDomains"] as? [String: Any],
           let entry = domains[host] as? [String: Any],
           entry["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true { return true }
        return ats?["NSAllowsLocalNetworking"] as? Bool == true && isLocal(host)
    }

    /// The hosts NSAllowsLocalNetworking covers: loopback, .local, unqualified and private IPv4.
    static func isLocal(_ host: String) -> Bool {
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) { return true }
        if host.hasSuffix(".local") || !host.contains(".") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        if octets[0] == 10 || octets[0] == 127 { return true }
        if octets[0] == 192 && octets[1] == 168 { return true }
        if octets[0] == 172 && (16...31).contains(octets[1]) { return true }
        if octets[0] == 169 && octets[1] == 254 { return true }
        return false
    }

    static func appTransportSecurity() -> [String: Any]? {
        Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
    }
}
