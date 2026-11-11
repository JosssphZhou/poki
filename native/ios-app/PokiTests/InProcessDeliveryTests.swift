import ObjectiveC
import PokiCore
import UIKit
import XCTest
@testable import Poki

final class InProcessDeliveryTests: XCTestCase {
    func testAnUnconfirmedTouchStaysUnknownAcrossTheInProcessTransport() async throws {
        let method = try XCTUnwrap(class_getInstanceMethod(PKInProcess.self, #selector(PKInProcess.touch(_:timeout:))))
        let original = method_getImplementation(method)
        // Replace only the OS dispatch boundary; use the real route, response mapping and Runner.
        let dispatch: @convention(block) (AnyObject, NSArray, Double) -> PKOutcome = { _, _, _ in
            let outcome = PKOutcome()
            outcome.setValue(PKDelivery.unknown.rawValue, forKey: "delivery")
            outcome.setValue("reply_timeout", forKey: "code")
            return outcome
        }
        let replacement = imp_implementationWithBlock(dispatch)
        method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        let runner = Runner(url: URL(string: "http://in-process")!, transport: InProcessWDA(screen: CGSize(width: 402, height: 874)))
        do {
            _ = try await runner.raw("POST", "/wda/tap", ["x": 100, "y": 200])
            XCTFail("An unconfirmed touch must not be reported as delivered")
        } catch let error as RunnerError {
            XCTAssertEqual(error.delivery, .unknown, "Do not tell the caller it is safe to repeat a touch that may already have landed")
            XCTAssertTrue(error.message.contains("no confirmation"), error.message)
        }
    }
}
