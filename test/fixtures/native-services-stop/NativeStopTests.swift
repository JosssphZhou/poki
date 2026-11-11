import Foundation
import XCTest
@testable import PokiCore

final class NativeStopTests: XCTestCase {
    func testCancelledNativeInputMustFinishBeforeSettleEvenAfterSessionReopens() async throws {
        let device = NativeDevice.shared
        device.started = expectation(description: "The native device received the tap")
        defer { device.finishInput() }
        let transport = NativeServicesWDA(screen: CGSize(width: 402, height: 874))
        let runner = Runner(url: URL(string: "http://native.invalid")!, transport: transport)
        _ = try await runner.session()
        let tap = Task {
            try await runner.raw("POST", "/session/native-services/wda/tap", ["x": 100, "y": 120], timeout: 10)
        }
        await fulfillment(of: [device.started], timeout: 2)
        tap.cancel()
        do {
            _ = try await tap.value
            XCTFail("The cancelled request must return without waiting for the device")
        } catch is CancellationError {}
        XCTAssertFalse(runner.hasSession)

        let beforeCompletion = await runner.settle(timeout: 0)
        XCTAssertFalse(beforeCompletion, "settle reported completion while native input was still pending")
        _ = try await runner.session()
        _ = try await runner.raw("GET", "/source")
        let afterReads = await runner.settle(timeout: 0)
        XCTAssertFalse(afterReads, "session and accessibility replies do not mean the native input ended")

        device.finishInput()
        let afterCompletion = await runner.settle(timeout: 1)
        XCTAssertTrue(afterCompletion, "settle must succeed once the native input callback completes")
    }
}
