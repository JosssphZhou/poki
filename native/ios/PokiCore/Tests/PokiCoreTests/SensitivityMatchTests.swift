import XCTest
@testable import PokiCore

/// The four labels from #352. Each one is a button a person taps, and none of them is caught by the
/// whole-word-or-short-label rule as it stands: the words sit in the middle of a label that is longer than
/// four tokens, so `matches` returns nil and the tap goes through without asking the owner.
///
/// These are written to fail on current main on purpose. The assertions check that the action is reported,
/// not which word reported it, so a fix is free to return a longer phrase from the same list.
final class SensitivityMatchTests: XCTestCase {
    private let payments = SensitivityRules().payments

    /// Five tokens, so the short-label shortcut does not apply, and "purchase" is neither first nor last.
    func testAPurchaseInAFiveTokenButtonIsStillAPayment() {
        XCTAssertNotNil(
            SensitivityRules.matches("Complete purchase of 3 items", payments),
            "'Complete purchase of 3 items' is a payment button and was not recognised as one"
        )
    }

    /// "pay" is inside "payment" here, which the right-hand boundary rejects, and the label is too long for the shortcut.
    func testAPaymentMentionedLateInASentenceIsStillAPayment() {
        XCTAssertNotNil(
            SensitivityRules.matches("Tap here to complete the payment", payments),
            "'Tap here to complete the payment' is a payment button and was not recognised as one"
        )
    }

    /// Hyphens are not whitespace, so a long hyphenated string counts as one token and passes the short-label
    /// test. It is not a button label and nothing in it should be read as a whole label.
    func testALongHyphenatedNameIsNotTreatedAsAShortLabel() {
        XCTAssertNil(
            SensitivityRules.matches("Re-open-settings-and-transfer-funds-please", payments),
            "a hyphenated string was counted as one short token, so 'transfer' matched inside a name"
        )
    }

    /// The payment phrase is the stronger rule and comes later in the text; "send" must not decide this one.
    func testTheStrongerRuleWinsOverAWeakerWordLaterInTheLabel() {
        XCTAssertNotNil(
            SensitivityRules.matches("Please send money to Sam and reply afterwards", payments),
            "'send money' was not recognised inside a longer label"
        )
    }
}
