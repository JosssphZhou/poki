import SwiftUI
import UIKit

/// The message field with app capsules (ESP-377). `text` is the plain text and the only
/// source: an app's name in it shows as a capsule, the capsule is one character to the caret and to
/// backspace, and reading the field gives the plain text back with the names in place.
struct CapsuleField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var maxLines = 6
    var maxHeight: CGFloat = 200
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Whether the message is scrolled away from its first line, for a swipe down on the field: that
    /// swipe scrolls the message back, it does not put the keyboard away.
    var scroll: CapsuleScroll? = nil
    /// How far the field top sits below the top edge of the composer sheet.
    var above: CGFloat = 0
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
        view.accessibilityLabel = AppLocalization.text(LocalizedStringResource("Message Poki"))
        view.updateFont(for: UIContentSizeCategory(typeSize))
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
            view.keyboardDismissMode = context.coordinator.mode(view)
            view.alwaysBounceVertical = true
        }
        context.coordinator.watch(view)
        return view
    }

    static func dismantleUIView(_ view: CapsuleTextView, coordinator: Coordinator) { coordinator.clear() }

    func updateUIView(_ view: CapsuleTextView, context: Context) {
        context.coordinator.parent = self
        view.updateFont(for: UIContentSizeCategory(typeSize))
        view.accessibilityLabel = AppLocalization.text(LocalizedStringResource("Message Poki"))
        // A write from outside (a recommendation, dictation, Send emptying the field): render it whole,
        // caret at the end.
        if view.plainText != text { view.setPlain(text) }
        DispatchQueue.main.async { [coordinator = context.coordinator] in coordinator.rest(view) }
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
        return CGSize(width: width, height: min(fit, most, max(maxHeight, font.lineHeight + view.textContainerInset.top + view.textContainerInset.bottom)))
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
        /// Where the finger came down, in the window. A pan is seen some points later, and its own
        /// count of the way starts short of them.
        private var touchDown: CGPoint?
        /// A swipe on the field is under way: interactive dismissal stays as the swipe began until it ends.
        private var dragging = false
        private weak var lined: UIView?
        private weak var field: UITextView?

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
                dragging = true
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
        /// here to where the finger came down, so the keyboard and the bar over it are under the finger
        /// from the moment the drag is seen. A message scrolled away from its first line scrolls back
        /// instead, and the keyboard stays. So does a keyboard this swipe brings up: one that was down
        /// as the swipe began is not taken back down to the finger once it is up.
        private func follow(_ pan: UIPanGestureRecognizer, on view: UITextView) {
            keyboardTop = nil
            guard #available(iOS 26.0, *), let root = view.window?.rootViewController?.view else { return }
            let guide = root.keyboardLayoutGuide
            let start = touchDown.map { root.convert($0, from: nil).y } ?? pan.location(in: root).y
            let stays = startedScrolled || !view.isFirstResponder
            view.keyboardDismissMode = stays ? .none : .interactive
            if !stays {
                guide.keyboardDismissPadding = max(0, guide.layoutFrame.minY - start)
                lined = root
            }
            keyboardTop = guide.layoutFrame.minY
        }

        func mode(_ view: UITextView) -> UIScrollView.KeyboardDismissMode {
            view.isFirstResponder ? .interactive : .none
        }

        func watch(_ view: CapsuleTextView) {
            field = view
            view.onLayout = { [weak self, weak view] in if let view { self?.rest(view) } }
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardShown), name: UIResponder.keyboardDidShowNotification, object: nil)
        }

        @objc private func keyboardShown() { if let field { rest(field) } }

        /// Between swipes on iOS 26, keep the window keyboard dismissal line on the top edge of the
        /// composer sheet while this field holds focus, as Messages does (WWDC23, Keep up with the
        /// keyboard). Clear the shared window guide when focus leaves this field.
        func rest(_ view: UITextView) {
            guard #available(iOS 26.0, *), !dragging else { return }
            guard view.isFirstResponder, let root = view.window?.rootViewController?.view else { return clear() }
            let guide = root.keyboardLayoutGuide
            let line = max(0, guide.layoutFrame.minY - view.convert(view.bounds, to: root).minY + parent.above)
            if abs(guide.keyboardDismissPadding - line) > 0.5 { guide.keyboardDismissPadding = line }
            lined = root
        }

        func clear() {
            guard #available(iOS 17.0, *) else { return }
            lined?.keyboardLayoutGuide.keyboardDismissPadding = 0
            lined = nil
        }

        /// As the swipe ends: whether the keyboard left its place under it.
        private func keyboardFollowed(_ view: UITextView) -> Bool {
            dragging = false
            DispatchQueue.main.async { [self] in
                guard !dragging else { return }
                if #available(iOS 26.0, *) { view.keyboardDismissMode = mode(view) }
                rest(view)
            }
            guard let keyboardTop, let root = view.window?.rootViewController?.view else { return false }
            return root.keyboardLayoutGuide.layoutFrame.minY > keyboardTop + 1
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touchDown = touch.location(in: nil)
            return true
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

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.focused { parent.focused = true }
            if #available(iOS 26.0, *), !dragging { textView.keyboardDismissMode = mode(textView) }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.focused { parent.focused = false }
            if #available(iOS 26.0, *), !dragging { textView.keyboardDismissMode = mode(textView) }
            clear()
        }
    }
}

/// Where the message field is scrolled, read when a swipe on the field starts.
final class CapsuleScroll {
    var scrolledDown = false
}

final class CapsuleTextView: UITextView {
    static var bodyFont: UIFont { .preferredFont(forTextStyle: .body) }
    private var requestedCategory: UIContentSizeCategory?
    private var needsFontRefresh = false

    func updateFont(for category: UIContentSizeCategory) {
        requestedCategory = category
        refreshFont()
    }

    private func refreshFont() {
        guard markedTextRange == nil else { needsFontRefresh = true; return }
        let traits = traitCollection.modifyingTraits {
            $0.preferredContentSizeCategory = requestedCategory ?? traitCollection.preferredContentSizeCategory
        }
        let next = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traits)
        guard needsFontRefresh || font != next else { return }
        needsFontRefresh = false
        font = next
        redraw()
        invalidateIntrinsicContentSize()
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // The pills are pictures drawn for one appearance and one text size: draw them again.
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self]) { (view: CapsuleTextView, _: UITraitCollection) in
            view.needsFontRefresh = true
            view.refreshFont()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

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
        if needsFontRefresh { refreshFont() }
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
