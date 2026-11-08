import XCTest
@testable import Poki

@MainActor
final class GrokCredentialTests: XCTestCase {
    func testARefreshCannotRestoreAnAccountThatSignedOut() async throws {
        let previous = ModelKeys.key(.grok)
        defer {
            if let previous { try? ModelKeys.save(previous, for: .grok) }
            else { ModelKeys.remove(.grok) }
        }
        let expired = GrokTokens(accessToken: "old-access", refreshToken: "old-refresh", expires: .distantPast)
        let fresh = GrokTokens(accessToken: "new-access", refreshToken: "new-refresh", expires: .distantFuture)
        try GrokAccount.save(expired)

        let credential = GrokCredential { token in
            XCTAssertEqual(token, expired.refreshToken)
            ModelKeys.remove(.grok)
            return fresh
        }

        let access = try await credential.accessToken()
        XCTAssertNil(access)
        XCTAssertFalse(GrokAccount.signedIn)
    }
}
