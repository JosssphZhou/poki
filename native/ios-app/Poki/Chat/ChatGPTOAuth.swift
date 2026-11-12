import CryptoKit
import Foundation
import PiSwiftAI
import Security

/// OpenAI's public-client, loopback OAuth flow for open-source apps.
enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let dynamicClient = "dynamic_agent_client"
    static let directScope = "chatgpt.tokens.use.direct"
    static let redirectPath = "/auth/callback"

    enum Failure: LocalizedError {
        case invalidCallback, invalidGrant, invalidIdentity, duplicateRegistration, duplicateLabel, missingAccount, accountBusy
        case browser, cancelled, service

        var errorDescription: String? {
            switch self {
            case .invalidCallback: String(localized: "ChatGPT returned an invalid sign-in response. Try again.")
            case .invalidGrant: String(localized: "ChatGPT plan access was not granted. Try signing in again.")
            case .invalidIdentity: String(localized: "ChatGPT could not verify the identity for this registration.")
            case .duplicateRegistration: String(localized: "This ChatGPT registration is already saved. Open its account to sign in again.")
            case .duplicateLabel: String(localized: "Another ChatGPT account already uses this label.")
            case .missingAccount: String(localized: "This ChatGPT account is no longer saved.")
            case .accountBusy: String(localized: "This ChatGPT account is being updated. Try again in a moment.")
            case .browser: String(localized: "Poki could not open the ChatGPT sign-in browser.")
            case .cancelled: String(localized: "Sign-in was cancelled.")
            case .service: String(localized: "Poki could not connect to ChatGPT. Try again.")
            }
        }
    }

    struct Attempt {
        let redirect: String
        let state = random()
        let nonce = random()
        let verifier = random()
        let profile: ChatGPTProfile?

        func url(hostID: String) -> URL {
            var url = URLComponents(string: "\(issuer)/api/accounts/authorize")!
            var fields = [
                "client_id": profile?.clientID ?? dynamicClient,
                "ext_agent_host_id": hostID,
                "response_type": "code",
                "redirect_uri": redirect,
                "resource": resource,
                "scope": "openid profile email offline_access resource.invoke \(directScope)",
                "state": state,
                "nonce": nonce,
                "code_challenge_method": "S256",
                "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL,
            ]
            if let profile {
                fields["id_token_hint"] = profile.idToken
                fields["login_hint"] = profile.email
            } else {
                fields["agent_name_hint"] = "Poki"
            }
            url.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
            return url.url!
        }

        func code(from callback: URL) throws -> (code: String, client: String) {
            guard let expected = URL(string: redirect),
                  let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  parts.scheme == expected.scheme, parts.host == expected.host, parts.port == expected.port,
                  parts.path == expected.path, parts.fragment == nil, parts.user == nil, parts.password == nil
            else { throw Failure.invalidCallback }
            var fields: [String: String] = [:]
            for item in parts.queryItems ?? [] {
                guard fields[item.name] == nil else { throw Failure.invalidCallback }
                fields[item.name] = item.value ?? ""
            }
            guard fields["state"] == state else { throw Failure.invalidCallback }
            if fields["error"] != nil { throw Failure.cancelled }
            guard let code = fields["code"], !code.isEmpty,
                  let client = fields["client_id"] ?? profile?.clientID, isIssuedClient(client),
                  profile == nil || client == profile?.clientID else { throw Failure.invalidCallback }
            return (code, client)
        }
    }

    struct Authorization {
        let subject: String
        let email: String?
        let idToken: String
        let credentials: OAuthCredentials
        let models: [ChatModelChoice]?
    }

    struct Identity: Decodable {
        let iss: String
        let sub: String
        let nonce: String
        let aud: [String]
        let exp: Double
        let iat: Double
        let nbf: Double?
        let azp: String?
        let email: String?

        enum CodingKeys: String, CodingKey { case iss, sub, nonce, aud, exp, iat, nbf, azp, email }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            iss = try values.decode(String.self, forKey: .iss)
            sub = try values.decode(String.self, forKey: .sub)
            nonce = try values.decode(String.self, forKey: .nonce)
            aud = try (try? values.decode([String].self, forKey: .aud)) ?? [values.decode(String.self, forKey: .aud)]
            exp = try values.decode(Double.self, forKey: .exp)
            iat = try values.decode(Double.self, forKey: .iat)
            nbf = try values.decodeIfPresent(Double.self, forKey: .nbf)
            azp = try values.decodeIfPresent(String.self, forKey: .azp)
            email = try values.decodeIfPresent(String.self, forKey: .email)
        }
    }

    private struct Token: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let expires_in: Double
        let scope: String?
        let token_type: String?

        func credentials(client: String, previous: OAuthCredentials? = nil) throws -> OAuthCredentials {
            let scopes = scope.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) } ?? previous?.scopes
            guard !access_token.isEmpty, let refresh = refresh_token ?? previous?.refresh, !refresh.isEmpty,
                  expires_in.isFinite, expires_in > 0,
                  token_type?.lowercased() == "bearer" || (token_type == nil && previous != nil),
                  scopes?.contains(directScope) == true else { throw Failure.invalidGrant }
            return OAuthCredentials(refresh: refresh, access: access_token, expires: Date().timeIntervalSince1970 * 1000 + expires_in * 1000,
                                    clientId: client, scopes: scopes)
        }
    }

    struct Keys: Decodable {
        struct Key: Decodable {
            let kty: String
            let kid: String
            let alg: String?
            let use: String?
            let n: String
            let e: String
        }
        let keys: [Key]
    }

    private struct Header: Decodable {
        let alg: String
        let kid: String
        let crit: [String]?
    }

    static func isIssuedClient(_ id: String) -> Bool {
        !id.isEmpty && id != dynamicClient && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canUsePlan(_ credentials: OAuthCredentials) -> Bool {
        !credentials.access.isEmpty && !credentials.refresh.isEmpty && credentials.expires.isFinite
            && credentials.scopes?.contains(directScope) == true
    }

    private static func random() -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }).base64URL
    }

    static func exchange(_ attempt: Attempt, callback: URL) async throws -> Authorization {
        let result = try attempt.code(from: callback)
        let token = try await tokenRequest([
            "grant_type": "authorization_code", "client_id": result.client, "code": result.code,
            "code_verifier": attempt.verifier, "redirect_uri": attempt.redirect, "resource": resource,
        ])
        let credentials = try token.credentials(client: result.client)
        guard let idToken = token.id_token else { throw Failure.invalidIdentity }
        let jwks = try await request(URLRequest(url: URL(string: "\(issuer)/.well-known/jwks.json")!))
        let identity = try verify(idToken, keys: JSONDecoder().decode(Keys.self, from: jwks),
                                  client: result.client, nonce: attempt.nonce)
        if let expected = attempt.profile?.subject, identity.sub != expected { throw Failure.invalidIdentity }
        return Authorization(subject: identity.sub, email: identity.email, idToken: idToken, credentials: credentials,
                             models: try? await models(credentials.access))
    }

    static func verify(_ token: String, keys: Keys, client: String, nonce: String,
                       now: Date = Date()) throws -> Identity {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]),
              let claims = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try? JSONDecoder().decode(Header.self, from: headerData),
              header.alg == "RS256", header.crit == nil,
              let key = keys.keys.first(where: { $0.kid == header.kid && $0.kty == "RSA" &&
                  ($0.alg == nil || $0.alg == "RS256") && ($0.use == nil || $0.use == "sig") }),
              let n = Data(base64URL: key.n), n.count >= 256, let e = Data(base64URL: key.e), !e.isEmpty
        else { throw Failure.invalidIdentity }
        let publicKey = der(tag: 0x30, bytes: integer(n) + integer(e))
        let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let rsa = SecKeyCreateWithData(publicKey as CFData, attributes as CFDictionary, nil),
              SecKeyVerifySignature(rsa, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil),
              let identity = try? JSONDecoder().decode(Identity.self, from: claims),
              identity.iss == issuer, identity.aud.contains(client), identity.nonce == nonce, !identity.sub.isEmpty,
              identity.azp == nil || identity.azp == client,
              identity.aud.count == 1 || identity.azp == client,
              identity.exp > now.timeIntervalSince1970, identity.iat <= now.timeIntervalSince1970 + 5,
              (identity.nbf ?? identity.iat) <= now.timeIntervalSince1970 + 5
        else { throw Failure.invalidIdentity }
        return identity
    }

    private static func integer(_ bytes: Data) -> Data {
        let unsigned = Data(bytes.drop(while: { $0 == 0 }))
        let positive = unsigned.first.map { $0 >= 128 ? Data([0]) + unsigned : unsigned } ?? Data([0])
        return der(tag: 2, bytes: positive)
    }

    private static func der(tag: UInt8, bytes: Data) -> Data {
        var size = bytes.count
        if size < 128 { return Data([tag, UInt8(size)]) + bytes }
        var length: [UInt8] = []
        while size > 0 {
            length.insert(UInt8(size & 255), at: 0)
            size >>= 8
        }
        return Data([tag, 0x80 | UInt8(length.count)] + length) + bytes
    }

    static func refresh(_ previous: OAuthCredentials) async throws -> OAuthCredentials {
        guard let client = previous.clientId, isIssuedClient(client) else { throw Failure.invalidGrant }
        let token = try await tokenRequest([
            "grant_type": "refresh_token", "client_id": client, "refresh_token": previous.refresh, "resource": resource,
        ])
        return try token.credentials(client: client, previous: previous)
    }

    static func revoke(_ credentials: OAuthCredentials) async -> Bool {
        struct Discovery: Decodable { let revocation_endpoint: URL }
        guard let client = credentials.clientId,
              let data = try? await request(URLRequest(url: URL(string: "\(issuer)/.well-known/openid-configuration")!)),
              let endpoint = try? JSONDecoder().decode(Discovery.self, from: data).revocation_endpoint,
              endpoint.scheme == "https", endpoint.host() == "auth.openai.com",
              endpoint.user == nil, endpoint.password == nil else { return false }
        let post = form(endpoint, ["token": credentials.refresh, "token_type_hint": "refresh_token", "client_id": client])
        for attempt in 0..<3 {
            do {
                let (_, status) = try await response(post)
                if status == 200 { return true }
                if status < 500 { return false }
            } catch {}
            if attempt < 2 { try? await Task.sleep(for: .seconds(attempt + 1)) }
        }
        return false
    }

    static func models(_ token: String) async throws -> [ChatModelChoice] {
        var query = URLRequest(url: URL(string: "\(resource)/models")!)
        query.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try decodeModelCatalog(await request(query))
    }

    // Sign in with ChatGPT uses a plan OAuth token. The API-key list at the same URL uses data[].id.
    static func decodeModelCatalog(_ data: Data) throws -> [ChatModelChoice] {
        struct Item: Decodable {
            let slug: String
            let display_name: String
            let visibility: String
        }
        struct Catalog: Decodable { let models: [Item] }
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        var seen: Set<String> = []
        return catalog.models.compactMap { item in
            guard item.visibility == "list", !item.slug.isEmpty, !item.display_name.isEmpty,
                  seen.insert(item.slug).inserted else { return nil }
            return ChatModelChoice(id: item.slug, name: item.display_name)
        }
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> Token {
        let query = form(URL(string: "\(issuer)/api/accounts/oauth/token")!, fields)
        return try JSONDecoder().decode(Token.self, from: await request(query))
    }

    private static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var parts = URLComponents()
        parts.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return request
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    private static func response(_ request: URLRequest) async throws -> (Data, Int) {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.service }
        return (data, http.statusCode)
    }

    private static func request(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await response(request)
        guard (200..<300).contains(status) else { throw Failure.service }
        return data
    }
}
