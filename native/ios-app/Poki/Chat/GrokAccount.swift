import Foundation

struct GrokTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expires: Date
}

enum GrokAccount {
    static var tokens: GrokTokens? {
        guard let stored = ModelKeys.key(.grok),
              let tokens = try? JSONDecoder().decode(GrokTokens.self, from: Data(stored.utf8)),
              !tokens.accessToken.isEmpty else { return nil }
        return tokens
    }

    static var signedIn: Bool { tokens != nil }

    static var canAuthenticate: Bool {
        guard let tokens else { return false }
        return tokens.expires > .now || tokens.refreshToken?.isEmpty == false
    }

    @MainActor
    static func save(_ tokens: GrokTokens) throws {
        try ModelKeys.save(String(decoding: JSONEncoder().encode(tokens), as: UTF8.self), for: .grok)
    }
}

/// Coalesces refreshes so two conversations cannot consume the same rotating refresh token.
@MainActor
final class GrokCredential {
    static let shared = GrokCredential()
    private let refreshTokens: @MainActor (String) async throws -> GrokTokens
    private var refresh: (source: GrokTokens, task: Task<String?, Error>)?

    init(refreshTokens: @escaping @MainActor (String) async throws -> GrokTokens = GrokOAuth.refresh) {
        self.refreshTokens = refreshTokens
    }

    func accessToken() async throws -> String? {
        guard let stored = GrokAccount.tokens else { return nil }
        if stored.expires.timeIntervalSinceNow > 120 { return stored.accessToken }
        if let refresh, refresh.source == stored {
            return try await refresh.task.value
        }
        guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
            return stored.expires.timeIntervalSinceNow > 0 ? stored.accessToken : nil
        }

        let task = Task { () -> String? in
            let fresh = try await refreshTokens(refreshToken)
            // Sign-in, sign-out and this check/write all run on the main actor.
            guard GrokAccount.tokens == stored else { return nil }
            try GrokAccount.save(fresh)
            return fresh.accessToken
        }
        refresh = (stored, task)
        defer { if refresh?.source == stored { refresh = nil } }
        return try await task.value
    }
}

/// xAI device authorization. The public device client and scopes match the Grok OAuth flow
/// implemented by NousResearch Hermes Agent (MIT), without importing its credentials.
enum GrokOAuth {
    private static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    private static let deviceURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    private static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)

    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    struct DeviceCode: Decodable, Sendable {
        let deviceCode: String
        let userCode: String
        let verificationUri: URL
        let verificationUriComplete: URL?
        let expiresIn: Int
        let interval: Int?

        var signInURL: URL {
            if let verificationUriComplete, Self.allowed(verificationUriComplete) { return verificationUriComplete }
            return verificationUri
        }

        static func allowed(_ url: URL) -> Bool {
            url.scheme == "https" && ["auth.x.ai", "accounts.x.ai"].contains(url.host ?? "") &&
                url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
        }
    }

    private struct Reply: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let error: String?

        func tokens(previousRefresh: String? = nil) throws -> GrokTokens {
            guard let accessToken, !accessToken.isEmpty, let expiresIn, expiresIn > 0 else {
                throw Failure.rejected
            }
            return GrokTokens(accessToken: accessToken, refreshToken: refreshToken ?? previousRefresh,
                              expires: Date().addingTimeInterval(TimeInterval(expiresIn)))
        }
    }

    private enum Failure: LocalizedError {
        case invalidResponse, expired, denied, rejected

        var errorDescription: String? {
            switch self {
            case .invalidResponse: String(localized: "xAI returned an invalid sign-in response.")
            case .expired: String(localized: "The Grok sign-in code expired. Start again for a new code.")
            case .denied: String(localized: "Grok sign-in was declined.")
            case .rejected: String(localized: "xAI could not finish Grok sign-in. Check your account and try again.")
            }
        }
    }

    static func begin() async throws -> DeviceCode {
        let (data, status) = try await post(deviceURL, [
            "client_id": clientID, "scope": "openid profile email offline_access grok-cli:access api:access",
        ])
        guard status == 200 else { throw Failure.rejected }
        let code = try decode(DeviceCode.self, from: data)
        guard !code.deviceCode.isEmpty, !code.userCode.isEmpty, code.expiresIn > 0,
              DeviceCode.allowed(code.verificationUri) else { throw Failure.invalidResponse }
        return code
    }

    static func complete(_ code: DeviceCode) async throws -> GrokTokens {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(code.expiresIn)
        var interval = max(1, code.interval ?? 5)
        var delay = interval
        let fields = [
            "client_id": clientID, "device_code": code.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]
        while clock.now + .seconds(delay) < deadline {
            try await clock.sleep(for: .seconds(delay))
            let data: Data
            let status: Int
            do {
                (data, status) = try await post(tokenURL, fields)
            } catch let error as URLError where retryable(error) {
                // Switching to the browser or between networks can interrupt a single request.
                delay = nextDelay(delay, minimum: interval)
                continue
            }
            if status == 429 || [502, 503, 504].contains(status) {
                delay = nextDelay(delay, minimum: interval)
                continue
            }
            delay = interval
            let reply = try decode(Reply.self, from: data)
            if status == 200 { return try reply.tokens() }
            switch reply.error {
            case "authorization_pending": continue
            case "slow_down":
                interval += 5
                delay = interval
            case "access_denied": throw Failure.denied
            case "expired_token": throw Failure.expired
            default: throw Failure.rejected
            }
        }
        throw Failure.expired
    }

    private static func retryable(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .resourceUnavailable, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func nextDelay(_ delay: Int, minimum: Int) -> Int {
        max(minimum, min(delay * 2, 30))
    }

    static func refresh(_ refreshToken: String) async throws -> GrokTokens {
        let (data, status) = try await post(tokenURL, [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken,
        ])
        guard status == 200 else { throw Failure.rejected }
        return try decode(Reply.self, from: data).tokens(previousRefresh: refreshToken)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }

    private static func post(_ url: URL, _ fields: [String: String]) async throws -> (Data, Int) {
        // RFC 8628 form fields, including opaque codes, must encode characters such as '+' and '&'.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")
        }.joined(separator: "&")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        return (data, response.statusCode)
    }
}
