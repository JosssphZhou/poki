import Foundation
import XCTest
@testable import Poki

/// The opt-in grants cleartext only to the named host(s). Every other host keeps ATS.
final class PlainHTTPPolicyTests: XCTestCase {
    private func ats(_ hosts: [String]) -> [String: Any] {
        var entries: [String: Any] = [:]
        for host in hosts { entries[host] = ["NSExceptionAllowsInsecureHTTPLoads": true] }
        return ["NSAllowsLocalNetworking": true, "NSExceptionDomains": entries]
    }

    func testDefaultBuildStillAllowsLocalHosts() {
        let plain: [String: Any] = ["NSAllowsLocalNetworking": true]
        for host in [
            "127.0.0.1", "localhost", "api.localhost", "my-mac.local", "my-mac.local.", "devbox",
            "192.168.1.20", "10.0.0.5", "172.20.1.4", "169.254.10.20",
            "[::1]", "[0:0:0:0:0:0:0:1]", "[fd12:3456:789a::1]", "[fc00::1]",
            "[fe80::1]", "[fe80::1%25en0]", "[::ffff:192.168.1.20]", "[::ffff:127.0.0.1]",
        ] {
            XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://\(host):3425/v1", ats: plain), host)
        }
    }

    func testDefaultBuildRefusesPublicAndMalformedHosts() {
        let plain: [String: Any] = ["NSAllowsLocalNetworking": true]
        for url in [
            "http://203.0.113.9:3425/v1",
            "http://gateway.example.com/v1",
            "http://[2001:db8:12::34]:3425/v1",
            "http://[2606:4700:4700::1111]/v1",
            "http://[::ffff:203.0.113.9]:3425/v1",
            "http://[::]:3425/v1",
            "http://[fe80::1%25]:3425/v1",
            "http://3405803785:3425/v1",
            "http://0xcb007109:3425/v1",
            "http://192.168.999.1:3425/v1",
            "http://10.0.0.-1:3425/v1",
            "http://10..1.2.3:3425/v1",
            "http://.local:3425/v1",
        ] {
            XCTAssertFalse(PlainHTTPPolicy.isAllowed(url, ats: plain), url)
        }
    }

    func testOptInAllowsOnlyTheNamedHostIncludingBracketedIPv6() {
        let configured = ats(["203.0.113.9", "2001:db8:12::34", "gateway.example.com"])
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://203.0.113.9:3425/v1", ats: configured))
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("HTTP://Gateway.Example.COM.:3425/v1", ats: configured))
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://[2001:db8:12::34]:3425/v1", ats: configured))
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://[2001:0DB8:0012:0:0:0:0:0034]:3425/v1", ats: configured))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://[2001:db8:12::35]:3425/v1", ats: configured))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://sub.gateway.example.com/v1", ats: configured))
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://203.0.113.10:3425/v1", ats: configured))
    }

    func testExceptionDomainOverridesLocalNetworkingAndHonorsSubdomains() {
        let atsDict: [String: Any] = [
            "NSAllowsLocalNetworking": true,
            "NSExceptionDomains": [
                "blocked.local": ["NSExceptionAllowsInsecureHTTPLoads": false],
                "corp.example.com": [
                    "NSExceptionAllowsInsecureHTTPLoads": true,
                    "NSIncludesSubdomains": true,
                ],
            ],
        ]
        XCTAssertFalse(PlainHTTPPolicy.isAllowed("http://blocked.local:3425/v1", ats: atsDict))
        XCTAssertTrue(PlainHTTPPolicy.isAllowed("http://gw.corp.example.com/v1", ats: atsDict))
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
