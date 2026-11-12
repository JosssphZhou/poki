import Foundation
import PiSwiftAI
import Security
import XCTest
@testable import Poki

@MainActor
final class ChatGPTProfileTests: XCTestCase {
    func testIndependentRegistrationsSurviveReloadAndSameEmailDoesNotMerge() async throws {
        let storage = ProfileStorage()
        let profiles = storage.open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.title, second.title)
        XCTAssertEqual(first.email, second.email)
        XCTAssertEqual(first.subject, second.subject)
        XCTAssertEqual(storage.open().all.map(\.id), [first.id, second.id])
        try profiles.rename(first.id, to: "Research")
        XCTAssertEqual(storage.open().profile(first.id)?.title, "Research")
        XCTAssertEqual(storage.open().profile(second.id)?.title, second.title)
        do {
            try profiles.rename(second.id, to: "research")
            XCTFail("Duplicate labels make accounts ambiguous")
        } catch ChatGPTOAuth.Failure.duplicateLabel {}
    }

    func testReauthorizationMatchesClientAndSubjectAndPreservesOtherAccount() async throws {
        let profiles = ProfileStorage().open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
        do {
            _ = try await profiles.authorize(first.id) { _ in grant("oaiapp_a", subject: "different") }
            XCTFail("A returning client must match the verified subject")
        } catch ChatGPTOAuth.Failure.invalidIdentity {}
        do {
            _ = try await profiles.authorize(first.id) { _ in grant("oaiapp_b") }
            XCTFail("Another registration must be rejected")
        } catch ChatGPTOAuth.Failure.invalidIdentity {}
        do {
            _ = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
            XCTFail("The same client cannot be registered twice")
        } catch ChatGPTOAuth.Failure.duplicateRegistration {}
        let updated = try await profiles.authorize(first.id) { previous in
            XCTAssertEqual(previous?.id, first.id)
            XCTAssertEqual(previous?.idToken, first.idToken)
            return grant("oaiapp_a", suffix: "new")
        }
        XCTAssertEqual(updated.id, first.id)
        XCTAssertNotEqual(updated.credentials?.access, first.credentials?.access)
        XCTAssertEqual(profiles.profile(second.id)?.credentials?.access, second.credentials?.access)
    }

    func testSignOutRetainsRegistrationAndRemoveKeepsOtherCredentials() async throws {
        let storage = ProfileStorage()
        let profiles = storage.open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a") }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
        XCTAssertTrue(profiles.beginRun(first.id))
        do {
            _ = try await profiles.signOut(first.id, remove: true) { _ in XCTFail("Active runs must keep their session"); return true }
            XCTFail("A running profile must stay usable")
        } catch ChatGPTOAuth.Failure.accountBusy {}
        profiles.endRun(first.id)
        let revoked = try await profiles.signOut(first.id, remove: false) { credentials in
            XCTAssertEqual(credentials.clientId, first.clientID)
            return false
        }
        XCTAssertFalse(revoked)
        let reloaded = storage.open()
        XCTAssertEqual(reloaded.profile(first.id)?.clientID, first.clientID)
        XCTAssertNil(reloaded.profile(first.id)?.credentials)
        XCTAssertNil(reloaded.profile(first.id)?.idToken)
        let removed = try await reloaded.signOut(first.id, remove: true) { _ in XCTFail("No renewable session"); return false }
        XCTAssertTrue(removed)
        XCTAssertNil(storage.open().profile(first.id))
        XCTAssertEqual(storage.open().profile(second.id)?.credentials?.access, second.credentials?.access)
    }

    func testLegacyMigrationRetriesAtomicWriteAndCannotResurrectRemovedAccount() async throws {
        let storage = ProfileStorage()
        let legacy = grant("oaiapp_legacy").credentials
        storage.legacy = try JSONEncoder().encode(legacy)
        storage.failWrite = true
        XCTAssertTrue(storage.open().all.isEmpty)
        XCTAssertNotNil(storage.legacy)
        XCTAssertNil(storage.data)
        storage.failWrite = false
        let profiles = storage.open()
        let migrated = try XCTUnwrap(profiles.all.first)
        XCTAssertEqual(migrated.clientID, legacy.clientId)
        XCTAssertEqual(migrated.credentials?.access, legacy.access)
        XCTAssertNil(migrated.subject)
        XCTAssertNil(storage.legacy)
        // Simulate a failure deleting the legacy item after the new record was committed.
        storage.legacy = try JSONEncoder().encode(legacy)
        _ = try await profiles.signOut(migrated.id, remove: true) { _ in true }
        XCTAssertTrue(storage.open().all.isEmpty)
    }

    func testRefreshCoalescesAndNeverOverwritesAnotherProfile() async throws {
        let storage = ProfileStorage()
        let profiles = storage.open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a", expired: true) }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
        let recorder = RefreshRecorder()
        async let one = profiles.accessToken(first.id, refresh: { try await recorder.refresh($0) })
        async let two = profiles.accessToken(first.id, refresh: { try await recorder.refresh($0) })
        let (a, b) = await (one, two)
        let refreshedClients = await recorder.clients
        XCTAssertEqual(refreshedClients, ["oaiapp_a"])
        XCTAssertEqual(a, "access-oaiapp_a-fresh")
        XCTAssertEqual(a, b)
        XCTAssertEqual(storage.open().profile(first.id)?.credentials?.refresh, "refresh-oaiapp_a-fresh")
        XCTAssertEqual(storage.open().profile(second.id)?.credentials?.refresh, second.credentials?.refresh)

        let unknown = await profiles.accessToken(UUID(), refresh: { _ in XCTFail("Unknown IDs never refresh"); throw URLError(.unknown) })
        XCTAssertNil(unknown)
    }

    func testWrongClientRefreshIsRejectedWithoutChangingEitherAccount() async throws {
        let profiles = ProfileStorage().open()
        let first = try await profiles.authorize(nil) { _ in grant("oaiapp_a", expired: true) }
        let second = try await profiles.authorize(nil) { _ in grant("oaiapp_b") }
        let token = await profiles.accessToken(first.id, refresh: { _ in grant("oaiapp_b", suffix: "wrong").credentials })
        XCTAssertNil(token)
        XCTAssertEqual(profiles.profile(first.id)?.credentials?.refresh, first.credentials?.refresh)
        XCTAssertEqual(profiles.profile(second.id)?.credentials?.refresh, second.credentials?.refresh)
    }

    func testAuthorizationURLAndCallbackSeparateNewAndReturningRegistrations() throws {
        let redirect = "http://127.0.0.1:1455/auth/callback"
        let host = "urn:uuid:00000000-0000-0000-0000-000000000001"
        let first = ChatGPTOAuth.Attempt(redirect: redirect, profile: nil)
        let newQuery = try query(first.url(hostID: host))
        XCTAssertEqual(newQuery["client_id"], "dynamic_agent_client")
        XCTAssertEqual(newQuery["agent_name_hint"], "Poki")
        XCTAssertEqual(newQuery["ext_agent_host_id"], host)
        XCTAssertThrowsError(try first.code(from: XCTUnwrap(URL(string: "\(redirect)?code=fixture&state=\(first.state)"))))
        XCTAssertThrowsError(try first.code(from: XCTUnwrap(URL(string: "\(redirect)?code=fixture&state=wrong&client_id=oaiapp_a"))))
        XCTAssertThrowsError(try first.code(from: XCTUnwrap(URL(string: "\(redirect)?code=fixture&state=\(first.state)&state=\(first.state)&client_id=oaiapp_a"))))

        let profile = ChatGPTProfile(id: UUID(), number: 1, clientID: "oaiapp_a", subject: "subject",
                                     email: "owner@example.invalid", idToken: "fixture-id-token")
        let returning = ChatGPTOAuth.Attempt(redirect: redirect, profile: profile)
        let existingQuery = try query(returning.url(hostID: host))
        XCTAssertEqual(existingQuery["client_id"], profile.clientID)
        XCTAssertEqual(existingQuery["id_token_hint"], profile.idToken)
        XCTAssertEqual(existingQuery["login_hint"], profile.email)
        XCTAssertNil(existingQuery["agent_name_hint"])
        XCTAssertNotEqual(first.state, returning.state)
        XCTAssertNotEqual(first.nonce, returning.nonce)
        XCTAssertNotEqual(first.verifier, returning.verifier)
        let ok = try XCTUnwrap(URL(string: "\(redirect)?code=fixture&state=\(returning.state)"))
        XCTAssertEqual(try returning.code(from: ok).client, profile.clientID)
        let mismatch = try XCTUnwrap(URL(string: "\(redirect)?code=fixture&state=\(returning.state)&client_id=oaiapp_b"))
        XCTAssertThrowsError(try returning.code(from: mismatch))
    }

    func testPlanModelCatalogUsesOAuthSchemaAndPreservesServerOrder() throws {
        let data = Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"Sol","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hidden"},{"slug":"gpt-6.1-sol","display_name":"Duplicate","visibility":"list"},{"slug":"gpt-6.1-terra","display_name":"Terra","visibility":"list"}]}"#.utf8)
        let models = try ChatGPTOAuth.decodeModelCatalog(data)
        XCTAssertEqual(models.map(\.id), ["gpt-6.1-sol", "gpt-6.1-terra"])
        XCTAssertEqual(models.map(\.name), ["Sol", "Terra"])
        XCTAssertEqual(try ChatGPTOAuth.decodeModelCatalog(Data(#"{"models":[]}"#.utf8)), [])
        let keyCatalog = Data(#"{"data":[{"id":"gpt-6.1-sol"}]}"#.utf8)
        XCTAssertThrowsError(try ChatGPTOAuth.decodeModelCatalog(keyCatalog))
        XCTAssertEqual(try ModelCatalog.decodeModels(keyCatalog, provider: .openai).map(\.id), ["gpt-6.1-sol"])
    }

    func testLegacyPlanCatalogRefreshKeepsFailureSeparateFromEmptyResult() async throws {
        let storage = ProfileStorage()
        let authorization = grant("oaiapp_legacy")
        storage.legacy = try JSONEncoder().encode(authorization.credentials)
        let profiles = storage.open()
        let legacy = try XCTUnwrap(profiles.all.first)
        let failed = await profiles.reloadModels(legacy.id) { _ in throw URLError(.badServerResponse) }
        XCTAssertFalse(failed)
        XCTAssertNil(profiles.profile(legacy.id)?.models)
        let empty = await profiles.reloadModels(legacy.id) { _ in
            try ChatGPTOAuth.decodeModelCatalog(Data(#"{"models":[]}"#.utf8))
        }
        XCTAssertTrue(empty)
        XCTAssertEqual(profiles.profile(legacy.id)?.models, [])
        let loaded = await profiles.reloadModels(legacy.id) { token in
            XCTAssertEqual(token, authorization.credentials.access)
            return try ChatGPTOAuth.decodeModelCatalog(Data(#"{"models":[{"slug":"gpt-6.1-sol","display_name":"Sol","visibility":"list"}]}"#.utf8))
        }
        XCTAssertTrue(loaded)
        XCTAssertEqual(storage.open().profile(legacy.id)?.models?.map(\.id), ["gpt-6.1-sol"])
    }

    func testIDTokenSignatureAndBinding() throws {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let bytes = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        // Security exports the public key as a DER sequence containing modulus and exponent.
        var cursor = 0
        func readLength(_ tag: UInt8) throws -> Int {
            guard cursor + 1 < bytes.count, bytes[cursor] == tag else { throw URLError(.cannotDecodeContentData) }
            let first = Int(bytes[cursor + 1])
            cursor += 2
            guard first >= 128 else { return first }
            let count = first & 127
            guard count > 0, count <= 4, cursor + count <= bytes.count else { throw URLError(.cannotDecodeContentData) }
            let length = bytes[cursor..<(cursor + count)].reduce(0) { $0 * 256 + Int($1) }
            cursor += count
            return length
        }
        func readInteger() throws -> Data {
            let length = try readLength(2)
            guard cursor + length <= bytes.count else { throw URLError(.cannotDecodeContentData) }
            defer { cursor += length }
            return Data(bytes[cursor..<(cursor + length)].drop(while: { $0 == 0 }))
        }
        _ = try readLength(0x30)
        let n = try readInteger()
        let e = try readInteger()
        let keys = ChatGPTOAuth.Keys(keys: [.init(kty: "RSA", kid: "test", alg: "RS256", use: "sig", n: n.base64URL, e: e.base64URL)])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let header = Data(#"{"alg":"RS256","kid":"test"}"#.utf8).base64URL
        let claims = Data(#"{"iss":"https://auth.openai.com","sub":"fixture","aud":["oaiapp_a"],"nonce":"nonce","iat":1799999999,"exp":1800000060}"#.utf8).base64URL
        let body = "\(header).\(claims)"
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(body.utf8) as CFData, nil) as Data?)
        let jwt = "\(body).\(signature.base64URL)"
        XCTAssertEqual(try ChatGPTOAuth.verify(jwt, keys: keys, client: "oaiapp_a", nonce: "nonce", now: now).sub, "fixture")
        XCTAssertThrowsError(try ChatGPTOAuth.verify(jwt, keys: keys, client: "oaiapp_b", nonce: "nonce", now: now))
        XCTAssertThrowsError(try ChatGPTOAuth.verify(jwt, keys: keys, client: "oaiapp_a", nonce: "wrong", now: now))
        XCTAssertThrowsError(try ChatGPTOAuth.verify(jwt, keys: keys, client: "oaiapp_a", nonce: "nonce", now: now.addingTimeInterval(61)))
        let altered = "\(body).\(Data(repeating: 0, count: signature.count).base64URL)"
        XCTAssertThrowsError(try ChatGPTOAuth.verify(altered, keys: keys, client: "oaiapp_a", nonce: "nonce", now: now))
    }

    private func query(_ url: URL) throws -> [String: String] {
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
    }
}

@MainActor
final class ProfileStorage {
    var data: Data?
    var legacy: Data?
    var failWrite = false

    func open() -> ChatGPTProfiles {
        ChatGPTProfiles(read: { self.data }, write: {
            if self.failWrite { throw URLError(.cannotWriteToFile) }
            self.data = $0
        }, readLegacy: { self.legacy }, eraseLegacy: { self.legacy = nil }, didChange: {})
    }
}

func grant(_ client: String, subject: String = "same-subject", suffix: String = "old", expired: Bool = false) -> ChatGPTOAuth.Authorization {
    let credentials = OAuthCredentials(refresh: "refresh-\(client)-\(suffix)", access: "access-\(client)-\(suffix)",
                                       expires: expired ? 0 : Date().timeIntervalSince1970 * 1000 + 3_600_000,
                                       clientId: client, scopes: [ChatGPTOAuth.directScope])
    return ChatGPTOAuth.Authorization(subject: subject, email: "owner@example.invalid", idToken: "fixture-\(client)-\(suffix)",
                                      credentials: credentials, models: [.init(id: "gpt-6.1-sol", name: "Sol")])
}

private actor RefreshRecorder {
    private(set) var clients: [String] = []

    func refresh(_ previous: OAuthCredentials) async throws -> OAuthCredentials {
        let id = try XCTUnwrap(previous.clientId)
        clients.append(id)
        try await Task.sleep(for: .milliseconds(50))
        return grant(id, suffix: "fresh").credentials
    }
}
