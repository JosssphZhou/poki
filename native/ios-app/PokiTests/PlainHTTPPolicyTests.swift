import Foundation
import XCTest
@testable import Poki

/// The opt-in grants cleartext to exactly one host. Every other host keeps ATS.
final class PlainHTTPPolicyTests: XCTestCase {
    private func ats(_ hosts: [String]) -> [String: Any] {
        var entries: [String: Any] = [:]
        for host in hosts { entries[host] = ["NSExceptionAllowsInsecureHTTPLoads": true] }
        return ["NSAllowsLocalNetworking": true, "NSExceptionDomains": entries]
    }

    func testDefaultBuildStillAllowsLocalHosts() {
        let plain: [String: Any] = ["NSAllowsLocalNetworking": true]
        for host in ["127.0.0.1", "localhost", "my-mac.local", "192.168.1.20", "10.0.0.5", "172.20.1.4"] {
            XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://\(host):3425/v1", ats: plain), host)
        }
    }

    func testDefaultBuildRefusesPublicHosts() {
        let plain: [String: Any] = ["NSAllowsLocalNetworking": true]
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://203.0.113.9:3425/v1", ats: plain))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://gateway.example.com/v1", ats: plain))
    }

    func testOptInAllowsOnlyTheNamedHost() {
        let configured = ats(["203.0.113.9"])
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://203.0.113.9:3425/v1", ats: configured))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://gateway.example.com/v1", ats: configured))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://203.0.113.10:3425/v1", ats: configured))
    }

    func testLocalNetworkingTurnedOffClosesLocalHosts() {
        let off: [String: Any] = [:]
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://127.0.0.1:8765/v1", ats: off))
    }

    func testHTTPSAlwaysAllowed() {
        let plain: [String: Any] = ["NSAllowsLocalNetworking": true]
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("https://api.openai.com/v1/models", ats: plain))
    }
}
