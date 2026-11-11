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
        settle { field.text == "" }
        XCTAssertEqual(sent, [], "Return in an empty field sends nothing")
        XCTAssertEqual(field.text, "", "and leaves no new line behind")

        field.insertText("Open Settings")
        settle(for: 0.3)
        field.insertText("\n")
        settle { !sent.isEmpty }
        XCTAssertEqual(sent, ["Open Settings"])
        settle { field.text == "" }
        XCTAssertEqual(field.text, "", "the field empties once the message is sent")

        // Autocorrect fixes the last word, then the Send key adds its new line: two edits, as UIKit makes them.
        field.insertText("I dont")
        settle(for: 0.3)
        field.replace(try XCTUnwrap(Self.range(field, last: 4)), withText: "don\u{2019}t")
        field.insertText("\n")
        settle { sent.count == 2 }
        XCTAssertEqual(sent, ["Open Settings", "I don\u{2019}t"])
    }

    func testPastingTextThatEndsInANewLineKeepsTheDraft() throws {
        var sent: [String] = []
        let field = try composer { sent.append($0) }
        // Only written, never read here: reading another app's copy would wait for the Allow Paste alert.
        // Paste over the selected draft: other text, then the same text, each ending in a new line.
        for pasted in ["hello\n", "Draft\n"] {
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.insertText("Draft")
            settle(for: 0.3)
            UIPasteboard.general.string = pasted
            field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
            field.paste(nil)
            settle { field.text == pasted }
            settle(for: 0.3)
            XCTAssertEqual(sent, [], "pasting \(pasted.debugDescription) is not the Send key")
            XCTAssertEqual(field.text, pasted)
        }
        // Paste a lone new line at the end of the draft.
        field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
        field.insertText("Draft")
        settle(for: 0.3)
        UIPasteboard.general.string = "\n"
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.paste(nil)
        settle { field.text == "Draft\n" }
        settle(for: 0.3)
        XCTAssertEqual(sent, [], "pasting a new line is not the Send key")
        XCTAssertEqual(field.text, "Draft\n")
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
        settle { Self.textView(in: window) != nil }
        let field = try XCTUnwrap(Self.textView(in: window), "the message field is on screen")
        field.becomeFirstResponder()
        settle(for: 0.2)
        return field
    }

    /// Runs the main run loop until `done` holds, for at most two seconds: SwiftUI applies the text
    /// view's edits to the field's binding, and the field's answer back, on later turns of the loop.
    private func settle(until done: () -> Bool) {
        let end = Date().addingTimeInterval(2)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }

    /// A pause the field's binding needs to catch up, as between a person's keystrokes, and the wait for
    /// an outcome that is nothing happening.
    private func settle(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func range(_ field: UITextView, last count: Int) -> UITextRange? {
        guard let start = field.position(from: field.endOfDocument, offset: -count) else { return nil }
        return field.textRange(from: start, to: field.endOfDocument)
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let text = view as? UITextView { return text }
        for child in view.subviews { if let found = textView(in: child) { return found } }
        return nil
    }
}
