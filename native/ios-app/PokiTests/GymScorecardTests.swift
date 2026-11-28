import Foundation
import PokiCore
import XCTest
@testable import Poki

@MainActor
final class GymScorecardTests: XCTestCase {
    func testCallAcceptsPokiInFrontLookWithoutPictureAndFlagsMissingTaskPicture() async {
        var nextReply: (text: String, pictures: [Data]) = ("", [])
        let env = GymEnvironment(call: { _, _ in nextReply }, log: { _ in })
        let scorecard = GymScorecard(env: env)

        nextReply = (
            "poki: Poki is in front, showing the owner's chat with you, so no screen of the task is read yet.\nopen the app the task needs with do {\"actions\":[{\"launch\":{\"bundle\":\"...\"}}]}",
            []
        )
        _ = await scorecard.call("look (cold)", "look")
        XCTAssertEqual(scorecard.failures, [], "Poki's privacy-guarded front screen intentionally omits screenshots")

        nextReply = ("skills: 0 stored", [])
        _ = await scorecard.call("read skills", "skills")
        XCTAssertEqual(scorecard.failures, [])

        nextReply = ("routines: 0 stored", [])
        _ = await scorecard.call("read routines", "routines")
        XCTAssertEqual(scorecard.failures, [])

        nextReply = ("app: Settings   read: 2026-11-15T10:00:00Z (120 ms)\nelements (1):\n 1 StaticText \"Settings\" [0,0,100,20]", [])
        _ = await scorecard.call("look at Settings", "look")
        XCTAssertEqual(scorecard.failures, ["setup / look at Settings: no picture"])
    }

    func testClearSafariOverlaysDismissesTipViewAndReadsLoadedPageBehindIt() async {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        var sentCalls: [(String, JSON)] = []
        let tipOverlay = """
        app: Safari   read: 2026-11-15T09:22:24Z (1550 ms)
        did: wait_until: "Gym Local Page" appeared after 765 ms (sent, 766 ms)
        elements (6; a new screen: numbered from 1 again):
         1 Other "dismiss popup" [0,0,402,874]
         2 Other "TipView" [72,593,320,199]
         6 Button "Close" [352,607,26,26]
        """
        let afterClose = """
        app: Safari   read: 2026-11-15T09:22:26Z (210 ms)
        did: tap 6 (sent, 80 ms)
        elements (2; only the changed are listed):
        +7 Toolbar "Toolbar" [0,796,402,44]
        """
        let fullPage = """
        app: Safari   read: 2026-11-15T09:22:27Z (190 ms)
        elements (4):
         1 Other "Gym Local Page" [0,62,402,845]
         2 StaticText "Gym Local Page" [24,86,220,28]
        """
        let scorecard = GymScorecard(env: GymEnvironment(call: { name, args in
            await MainActor.run { sentCalls.append((name, args)) }
            return (name == "do" ? afterClose : fullPage, [jpeg])
        }, log: { _ in }))

        let cleared = await scorecard.clearSafariOverlays(tipOverlay, target: "Gym Local Page")
        XCTAssertNotNil(scorecard.ref(in: cleared, "Gym Local Page"))
        XCTAssertEqual(sentCalls.map(\.0), ["do", "look"])
        XCTAssertEqual(scorecard.failures, [])
    }

    func testSafariPagesServeLoopbackHTMLWithScrollableLinkAndSecondPage() async throws {
        let server = try GymLocalServer.safariPages()
        defer { server.stop() }
        XCTAssertGreaterThan(server.port, 0)

        let (firstData, firstResponse) = try await URLSession.shared.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/first")))
        XCTAssertEqual((firstResponse as? HTTPURLResponse)?.statusCode, 200)
        let firstHTML = String(decoding: firstData, as: UTF8.self)
        XCTAssertTrue(firstHTML.contains("Gym Local Page"))
        XCTAssertTrue(firstHTML.contains("<a href=\"/second\">Learn more</a>"))

        let (secondData, secondResponse) = try await URLSession.shared.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/second")))
        XCTAssertEqual((secondResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: secondData, as: UTF8.self).contains("Gym Second Page"))

        let (_, missingResponse) = try await URLSession.shared.data(from: XCTUnwrap(URL(string: "http://127.0.0.1:\(server.port)/missing")))
        XCTAssertEqual((missingResponse as? HTTPURLResponse)?.statusCode, 404)
    }
}
