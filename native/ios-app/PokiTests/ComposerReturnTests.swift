import SwiftUI
import UIKit
import XCTest
@testable import Poki

/// The chat's message field as the keyboard drives it: the real composer in a window, typed into
/// through the text view SwiftUI puts on screen (ESP-412: Return showed Send but added a new line).
@MainActor
final class ComposerReturnTests: XCTestCase {
    private var window: UIWindow?

    override func tearDown() {
        window?.isHidden = true
        window = nil
    }

    func testReturnSendsTheMessageAndAnEmptyFieldSendsNothing() throws {
        var sent: [String] = []
        let field = try composer { sent.append($0) }

        field.insertText("\n")
        settle()
        XCTAssertEqual(sent, [], "Return in an empty field sends nothing")
        XCTAssertEqual(field.text, "", "and leaves no new line behind")

        field.insertText("Open Settings")
        settle()
        // The control: the typed words reached the composer, so a failure below is Return's.
        XCTAssertEqual(field.text, "Open Settings")

        field.insertText("\n")
        settle()
        XCTAssertEqual(sent, ["Open Settings"])
        XCTAssertEqual(field.text, "", "the field empties once the message is sent")

        // Autocorrect fixes the last word in the same edit as the Send key's new line.
        field.insertText("I dont")
        settle()
        let word = try XCTUnwrap(field.textRange(from: field.position(from: field.endOfDocument, offset: -4)!, to: field.endOfDocument))
        field.replace(word, withText: "don\u{2019}t\n")
        settle()
        XCTAssertEqual(sent, ["Open Settings", "I don\u{2019}t"])
        XCTAssertEqual(field.text, "")
    }

    // MARK: Hosting

    private func composer(send: @escaping (String) -> Void) throws -> UITextView {
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing())
        let view = ComposerInputView(running: false, send: send, stop: {}, openVoice: {}, openModel: {}, newConversation: {})
            .environment(app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 200)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        self.window = window
        settle()
        let field = try XCTUnwrap(Self.textView(in: window), "the message field is on screen")
        field.becomeFirstResponder()
        settle()
        return field
    }

    /// Lets SwiftUI apply the text view's change to the field's binding and redraw.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let text = view as? UITextView { return text }
        for child in view.subviews { if let found = textView(in: child) { return found } }
        return nil
    }
}
