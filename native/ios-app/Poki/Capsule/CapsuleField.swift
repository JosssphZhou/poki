import SwiftUI
import UIKit

/// The message field with app capsules (ESP-377). `text` is the plain text and the only
/// source: an app's name in it shows as a capsule, the capsule is one character to the caret and to
/// backspace, and reading the field gives the plain text back with the names in place.
struct CapsuleField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var maxLines = 6
    /// Whether the message is scrolled away from its first line, for a swipe down on the field: that
    /// swipe scrolls the message back, it does not put the keyboard away.
    var scroll: CapsuleScroll? = nil
    /// An upright swipe on the field itself, true for up. The text view's own drag wins over a SwiftUI
    /// gesture around it while it has the keyboard, so the field reads the swipe itself as well. From
    /// iOS 26 a drag down takes the keyboard with the finger and this is not called for it.
    var onSwipe: ((Bool) -> Void)? = nil
    /// Return: the keyboard's Send key, as on the current field.
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> CapsuleTextView {
        let view = CapsuleTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = CapsuleTextView.bodyFont
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.returnKeyType = .send
        view.enablesReturnKeyAutomatically = true
        view.isScrollEnabled = true
        view.showsVerticalScrollIndicator = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityIdentifier = "capsule.field"
        view.accessibilityLabel = String(localized: "Message Poki")
        view.setPlain(text)
        let swipe = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.swiped(_:)))
        swipe.delegate = context.coordinator
        swipe.cancelsTouchesInView = false
        view.addGestureRecognizer(swipe)
        // From iOS 26 a drag down on the field takes the keyboard down under the finger: the system's
        // interactive dismissal, which the bar the field sits in follows from that version on. Before
        // it the bar stayed where it was until the keyboard had gone (FB13296535), so there the swipe
        // puts the keyboard away as the finger lifts. A message that fits is nothing to scroll, and the
        // text view would not take the drag: it is told to.
        if #available(iOS 26.0, *) {
            view.keyboardDismissMode = .interactive
            view.alwaysBounceVertical = true
        }
        return view
    }

    func updateUIView(_ view: CapsuleTextView, context: Context) {
        context.coordinator.parent = self
        // A write from outside (a recommendation, dictation, Send emptying the field): render it whole,
        // caret at the end.
        if view.plainText != text { view.setPlain(text) }
        if focused, !view.isFirstResponder {
            DispatchQueue.main.async { view.becomeFirstResponder() }
        } else if !focused, view.isFirstResponder {
            DispatchQueue.main.async { view.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: CapsuleTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 280
        let fit = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let font = view.font ?? CapsuleTextView.bodyFont
        let most = (font.lineHeight * CGFloat(maxLines) + view.textContainerInset.top + view.textContainerInset.bottom).rounded(.up)
        return CGSize(width: width, height: min(fit, most))
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: CapsuleField
        /// The message was scrolled away from its first line when the swipe began.
        private var startedScrolled = false
        /// This swipe has already asked for the keyboard.
        private var raised = false
        /// The keyboard's top in the root view when the swipe began (iOS 26), for telling at its end
        /// whether the keyboard went with the finger.
        private var keyboardTop: CGFloat?

        init(parent: CapsuleField) { self.parent = parent }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                guard textView.markedTextRange == nil else { return true }
                if let view = textView as? CapsuleTextView { parent.text = view.plainText }
                parent.onSubmit()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let view = textView as? CapsuleTextView else { return }
            view.reconcile()
            if parent.text != view.plainText { parent.text = view.plainText }
        }

        @objc func swiped(_ pan: UIPanGestureRecognizer) {
            guard let view = pan.view as? UITextView else { return }
            let (move, speed) = (pan.translation(in: view), pan.velocity(in: view))
            let upright = abs(move.y) > abs(move.x) * 1.5
            switch pan.state {
            case .began:
                startedScrolled = Self.scrolledDown(view)
                raised = false
                follow(pan, on: view)
            case .changed:
                // Up brings the keyboard while the finger is still moving, not when it lifts.
                if !raised, upright, move.y < -12 {
                    raised = true
                    parent.onSwipe?(true)
                }
            case .ended, .cancelled:
                let followed = keyboardFollowed(view)
                guard pan.state == .ended, upright else { return }
                if !raised, move.y < -24 || speed.y < -600 { parent.onSwipe?(true) }
                // A keyboard that went with the finger is the system's to settle, down or back up, on
                // the finger's speed. One that stayed is put away as the finger lifts.
                if move.y > 24 || speed.y > 600, !startedScrolled, !followed { parent.onSwipe?(false) }
            default: break
            }
        }

        /// As a swipe on the field begins (iOS 26). The system starts taking the keyboard down where a
        /// drag meets it; `keyboardDismissPadding` on the root view's keyboard guide moves that line up
        /// (WWDC23, Keep up with the keyboard; the root view's guide as in atlou/KeyboardAccessory, MIT),
        /// here to where the finger came down, so the keyboard and the bar over it start with the finger
        /// and keep its distance. A message scrolled away from its first line scrolls back instead, and
        /// the keyboard stays.
        private func follow(_ pan: UIPanGestureRecognizer, on view: UITextView) {
            keyboardTop = nil
            guard #available(iOS 26.0, *), let root = view.window?.rootViewController?.view else { return }
            let guide = root.keyboardLayoutGuide
            let start = pan.location(in: root).y - pan.translation(in: root).y
            view.keyboardDismissMode = startedScrolled ? .none : .interactive
            guide.keyboardDismissPadding = startedScrolled ? 0 : max(0, guide.layoutFrame.minY - start)
            keyboardTop = guide.layoutFrame.minY
        }

        /// As the swipe ends: whether the keyboard left its place under it. The line goes back to the
        /// keyboard's own top for the next drag, the conversation's included, once every recogniser
        /// has seen this one end.
        private func keyboardFollowed(_ view: UITextView) -> Bool {
            guard let keyboardTop, let root = view.window?.rootViewController?.view else { return false }
            let guide = root.keyboardLayoutGuide
            let followed = guide.layoutFrame.minY > keyboardTop + 1
            DispatchQueue.main.async { guide.keyboardDismissPadding = 0 }
            return followed
        }

        /// Alongside the text view's own scrolling and selection.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.scroll?.scrolledDown = Self.scrolledDown(scrollView)
            // Under a finger the message does not pull past its first line, and one that fits stays on
            // it: the drag moves the keyboard and the bar, and the words keep their place in the field.
            guard #available(iOS 26.0, *), scrollView.isTracking else { return }
            let top = -scrollView.adjustedContentInset.top
            let fits = scrollView.contentSize.height <= scrollView.bounds.height + 1
            let held = fits ? top : max(scrollView.contentOffset.y, top)
            if abs(held - scrollView.contentOffset.y) > 0.01 { scrollView.contentOffset.y = held }
        }

        /// Away from the first line of a message taller than the field. A message that fits can sit a
        /// few points off (the caret's line brought into view), and that is not scrolled.
        private static func scrolledDown(_ view: UIScrollView) -> Bool {
            view.contentSize.height > view.bounds.height + 1 && view.contentOffset.y + view.adjustedContentInset.top > 1
        }

        func textViewDidBeginEditing(_ textView: UITextView) { if !parent.focused { parent.focused = true } }
        func textViewDidEndEditing(_ textView: UITextView) { if parent.focused { parent.focused = false } }
    }
}

/// Where the message field is scrolled, read when a swipe on the field starts.
final class CapsuleScroll {
    var scrolledDown = false
}

final class CapsuleTextView: UITextView {
    static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // The pills are pictures drawn for one appearance and one text size: draw them again.
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: CapsuleTextView, _: UITraitCollection) in
            view.font = .preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
            view.redraw()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override var keyCommands: [UIKeyCommand]? {
        let newline = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertLineBreak))
        newline.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [newline]
    }

    @objc private func insertLineBreak(_ command: UIKeyCommand) {
        guard markedTextRange == nil, let selection = selectedTextRange else { return }
        replace(selection, withText: "\n")
        delegate?.textViewDidChange?(self)
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font ?? Self.bodyFont, .foregroundColor: UIColor.label]
    }

    /// The field's text with each capsule read back as the words it stands for.
    var plainText: String { Self.plain(textStorage, in: NSRange(location: 0, length: textStorage.length)) }

    /// Replaces everything with `plain`, caret at the end.
    func setPlain(_ plain: String) {
        textStorage.setAttributedString(render(CapsuleText.segments(plain)))
        selectedRange = NSRange(location: textStorage.length, length: 0)
        typingAttributes = baseAttributes
    }

    /// After every edit: names that are now whole become capsules, and capsules whose words are no
    /// longer a name (a letter typed against them) become text again. Nothing changes while the
    /// keyboard is still composing (Pinyin before it commits), so the composition is never disturbed.
    func reconcile() {
        guard markedTextRange == nil else { return }
        let wanted = CapsuleText.segments(plainText)
        guard wanted != segments() else { return }
        replaceKeepingSelection(with: wanted)
    }

    private func redraw() {
        guard markedTextRange == nil else { return }
        replaceKeepingSelection(with: CapsuleText.segments(plainText))
    }

    private func replaceKeepingSelection(with wanted: [CapsuleText.Segment]) {
        let selection = selectedRange
        let start = plainOffset(selection.location)
        let end = plainOffset(selection.location + selection.length)
        textStorage.beginEditing()
        textStorage.setAttributedString(render(wanted))
        textStorage.endEditing()
        let from = storageOffset(start), to = storageOffset(end)
        selectedRange = NSRange(location: from, length: max(0, to - from))
        typingAttributes = baseAttributes
    }

    // MARK: Plain text in and out

    private func render(_ segments: [CapsuleText.Segment]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let font = font ?? Self.bodyFont
        for segment in segments {
            switch segment {
            case .text(let text):
                out.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .app(let app, let text):
                let pill = PillTextAttachment(pillData: PillTextAttachmentData(app: app, text: text, font: font), traits: traitCollection)
                let one = NSMutableAttributedString(attachment: pill)
                one.addAttributes(baseAttributes, range: NSRange(location: 0, length: one.length))
                out.append(one)
            }
        }
        return out
    }

    private func segments() -> [CapsuleText.Segment] {
        var out: [CapsuleText.Segment] = []
        let string = textStorage.string as NSString
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            if let pill = value as? PillTextAttachment {
                out.append(.app(pill.pillData.app, pill.pillData.text))
            } else if case .text(let before)? = out.last {
                out[out.count - 1] = .text(before + string.substring(with: range))
            } else {
                out.append(.text(string.substring(with: range)))
            }
        }
        return out
    }

    static func plain(_ storage: NSAttributedString, in range: NSRange) -> String {
        var out = ""
        let string = storage.string as NSString
        storage.enumerateAttribute(.attachment, in: range) { value, run, _ in
            if let pill = value as? PillTextAttachment {
                out += pill.pillData.text
            } else {
                out += string.substring(with: run)
            }
        }
        return out
    }

    /// Where a position in the field falls in the plain text.
    private func plainOffset(_ location: Int) -> Int {
        Self.plain(textStorage, in: NSRange(location: 0, length: min(location, textStorage.length))).utf16.count
    }

    /// Where a position in the plain text falls in the field; inside a capsule's words, after the capsule.
    private func storageOffset(_ plain: Int) -> Int {
        var seen = 0
        var result = textStorage.length
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textStorage.length)) { value, run, stop in
            let length = (value as? PillTextAttachment)?.pillData.text.utf16.count ?? run.length
            if plain <= seen + length {
                if let _ = value as? PillTextAttachment {
                    result = plain == seen ? run.location : run.location + 1
                } else {
                    result = run.location + (plain - seen)
                }
                stop.pointee = true
                return
            }
            seen += length
        }
        return result
    }

    // MARK: Copy, cut and paste carry plain text

    override func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        UIPasteboard.general.string = Self.plain(textStorage, in: selectedRange)
    }

    override func cut(_ sender: Any?) {
        guard selectedRange.length > 0, let range = selectedTextRange else { return }
        copy(sender)
        replace(range, withText: "")
        delegate?.textViewDidChange?(self)
    }

    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string, let range = selectedTextRange else { return }
        replace(range, withText: string)
        delegate?.textViewDidChange?(self)
    }

    override var accessibilityValue: String? {
        get { plainText }
        set {}
    }
}
