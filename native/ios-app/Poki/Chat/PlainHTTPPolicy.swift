import Foundation

/// Whether a Custom Endpoint address may use cleartext HTTP.
///
/// The built app keeps ATS on. Poki grants cleartext to exactly one host when the owner opts in at
/// build time with POKI_HTTP_ENDPOINT_HOST. That host appears in NSExceptionDomains with
/// NSExceptionAllowsInsecureHTTPLoads set to YES. Every other host keeps full ATS.
enum PlainHTTPPolicy {
    static func isAllowed(_ address: String, ats: [String: Any]? = appTransportSecurity()) -> Bool {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http",
              let host = parts.host?.lowercased() else { return true }
        guard let domains = ats?["NSExceptionDomains"] as? [String: Any],
              let entry = domains[host] as? [String: Any] else { return false }
        return entry["NSExceptionAllowsInsecureHTTPLoads"] as? Bool == true
    }

    static func appTransportSecurity() -> [String: Any]? {
        Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
    }
}
