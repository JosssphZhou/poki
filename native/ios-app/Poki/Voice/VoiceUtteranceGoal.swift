import Foundation

fileprivate enum VoiceTextNormalizer {
    static func toSimplified(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value > 0x7F }) else { return text }
        return text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }
}

struct VoiceGoalID: Hashable, Codable, Sendable, CustomStringConvertible {
    let rawValue: String
    var description: String { rawValue }
}

enum VoiceUtteranceSource: String, Codable, Equatable, Sendable {
    case ownerMicrophone = "owner_microphone"
    case silentTest = "silent_test"
    case bystander = "bystander"
    case appAudio = "app_audio"
    case screenReader = "screen_reader"
    case quotedText = "quoted_text"

    var authorizesDeviceWork: Bool {
        switch self {
        case .ownerMicrophone, .silentTest: true
        case .bystander, .appAudio, .screenReader, .quotedText: false
        }
    }

    static func parse(_ raw: String?, fallback: Self) -> Self {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty else {
            return fallback
        }
        switch raw {
        case "owner", "owner_microphone", "microphone", "user": return .ownerMicrophone
        case "silent_test", "rehearsal", "test", "test_text": return .silentTest
        case "bystander", "other_speaker": return .bystander
        case "app_audio", "playback", "media": return .appAudio
        case "screen_reader", "voiceover", "assistive": return .screenReader
        case "quoted", "quoted_text", "screen_text": return .quotedText
        default: return fallback
        }
    }
}

enum VoiceTaskRelation: String, Codable, Equatable, Sendable {
    case chitchat
    case continueTask = "continue_task"
    case supplementOrRevise = "supplement_or_revise"
    case replace
    case independentNewTask = "independent_new_task"
    case stop
}

enum VoiceReplacementScope: String, Codable, Equatable, Sendable {
    case none
    case constraintsOnly = "constraints_only"
    case contentAndConstraints = "content_and_constraints"
    case remainingSteps = "remaining_steps"
    case wholeGoal = "whole_goal"

    var invalidatesEarlierRevisions: Bool {
        switch self {
        case .contentAndConstraints, .remainingSteps, .wholeGoal: true
        case .none, .constraintsOnly: false
        }
    }
}

enum VoiceStepOutcome: String, Codable, Equatable, Sendable {
    case running
    case succeeded
    case failedDefinitely = "failed_definitely"
    case unknown
    case blocked

    var blocksRepeat: Bool {
        switch self {
        case .running, .succeeded, .unknown: true
        case .failedDefinitely, .blocked: false
        }
    }

    static func classify(state: VoiceCall.State, output: String) -> Self {
        let lower = output.lowercased()
        let uncertain = lower.hasPrefix("unknown:")
            || lower.contains("may have run")
            || lower.contains("outcome could not be saved")
            || lower.contains("outcome is unknown")
            || lower.contains("not confirmed: no read after it")
        switch state {
        case .running:
            return .running
        case .done:
            return uncertain ? .unknown : .succeeded
        case .failed:
            return uncertain ? .unknown : .failedDefinitely
        }
    }
}

struct VoiceScreenRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px <= x + width && py >= y && py <= y + height
    }
}

struct VoiceObservedElement: Equatable, Sendable {
    let ref: Int
    let type: String
    let text: String
    let frame: VoiceScreenRect?

    var isTextInput: Bool {
        let lower = type.lowercased()
        return lower.contains("textfield") || lower.contains("textview")
            || lower.contains("searchfield") || lower.contains("securetextfield")
    }
}

struct VoiceObservedScreenUpdate: Equatable, Sendable {
    let app: String?
    let elements: [Int: VoiceObservedElement]
    let goneRefs: Set<Int>
    let isDelta: Bool
    let hasUsableEvidence: Bool
}

struct VoiceObservedScreen: Equatable, Sendable {
    var app: String?
    var elements: [Int: VoiceObservedElement] = [:]

    mutating func apply(_ update: VoiceObservedScreenUpdate) {
        let appChanged = update.app != nil && app != nil && update.app != app
        if let updatedApp = update.app { app = updatedApp }
        if update.isDelta && !appChanged {
            for gone in update.goneRefs { elements.removeValue(forKey: gone) }
            for (ref, element) in update.elements { elements[ref] = element }
        } else if !update.elements.isEmpty || appChanged {
            elements = update.elements
        }
    }

    func elements(hitting x: Double, y: Double) -> [VoiceObservedElement] {
        elements.values.filter { $0.frame?.contains(x: x, y: y) == true }
    }

    static func parseUpdate(_ output: String) -> VoiceObservedScreenUpdate? {
        var app: String?
        var elements: [Int: VoiceObservedElement] = [:]
        var goneRefs: Set<Int> = []
        var isDelta = false
        var sawFreshScreen = false
        var sawElements = false
        var readFailed = false

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if !sawElements && (lower.hasPrefix("read: failed") || lower.contains("no element tree:")) {
                readFailed = true
            }
            if !sawElements && lower.hasPrefix("app:") {
                if let parsedApp = parseAppHeader(line) { app = parsedApp }
                continue
            }
            if lower.hasPrefix("elements:") && lower.contains("none changed") {
                isDelta = true
                sawElements = true
                continue
            }
            if lower.hasPrefix("elements (") {
                if lower.contains("only the changed are listed") { isDelta = true }
                if lower.contains("a new screen") { sawFreshScreen = true; isDelta = false }
                sawElements = true
                continue
            }
            if lower.hasPrefix("gone since the last read:") {
                sawElements = true
                let tail = String(line.dropFirst("gone since the last read:".count))
                for part in tail.split(separator: ",") {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    let digits = trimmed.prefix(while: \.isNumber)
                    if let ref = Int(digits) { goneRefs.insert(ref) }
                }
                continue
            }
            if lower.hasPrefix("found by scroll_to:") {
                sawElements = true
                let tail = line.dropFirst("found by scroll_to:".count).trimmingCharacters(in: .whitespaces)
                if let element = parseElementLine(tail) { elements[element.ref] = element }
                continue
            }
            if let element = parseElementLine(line) {
                sawElements = true
                elements[element.ref] = element
            }
        }

        if sawFreshScreen { isDelta = false }
        guard app != nil || !elements.isEmpty || isDelta || !goneRefs.isEmpty else { return nil }
        let usable = !readFailed && (!elements.isEmpty || isDelta || (app != nil && !lowerContainsNoTree(output)))
        return VoiceObservedScreenUpdate(
            app: app,
            elements: elements,
            goneRefs: goneRefs,
            isDelta: isDelta,
            hasUsableEvidence: usable
        )
    }

    private static func lowerContainsNoTree(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("no element tree") || lower.contains("read: failed")
    }

    private static func parseAppHeader(_ line: String) -> String? {
        var value = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        for marker in ["   read:", "  read:", "\tread:", " read:"] {
            if let range = value.range(of: marker, options: .caseInsensitive) {
                value = String(value[..<range.lowerBound])
                break
            }
        }
        for marker in ["   note:", "  note:", "\tnote:"] {
            if let range = value.range(of: marker, options: .caseInsensitive) {
                value = String(value[..<range.lowerBound])
                break
            }
        }
        if let paren = value.range(of: "("), let close = value.range(of: ")", range: paren.upperBound..<value.endIndex) {
            let inside = String(value[paren.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
            if inside.contains(".") {
                value = inside
            }
        }
        let cleaned = value.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.lowercased() != "unknown" else { return nil }
        if cleaned.lowercased().hasPrefix("home screen") || cleaned.lowercased().contains("springboard") {
            return "com.apple.springboard"
        }
        return VoiceAppIdentity.canonical(cleaned)
    }

    private static func parseElementLine(_ line: String) -> VoiceObservedElement? {
        var cursor = line.startIndex
        if cursor < line.endIndex, "+-~*".contains(line[cursor]) {
            cursor = line.index(after: cursor)
        }
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        let numStart = cursor
        while cursor < line.endIndex, line[cursor].isNumber {
            cursor = line.index(after: cursor)
        }
        guard numStart < cursor, let ref = Int(line[numStart..<cursor]) else { return nil }
        if cursor < line.endIndex, line[cursor] == "." {
            cursor = line.index(after: cursor)
        }
        guard cursor < line.endIndex, line[cursor].isWhitespace else { return nil }
        while cursor < line.endIndex, line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        let typeStart = cursor
        while cursor < line.endIndex, !line[cursor].isWhitespace {
            cursor = line.index(after: cursor)
        }
        guard typeStart < cursor else { return nil }
        let type = String(line[typeStart..<cursor])
        let rest = line[cursor...].trimmingCharacters(in: .whitespaces)
        let text: String
        let afterText: Substring
        if let firstQuote = rest.firstIndex(of: "\"") {
            let afterFirst = rest.index(after: firstQuote)
            if let lastQuote = rest[afterFirst...].lastIndex(of: "\"") {
                text = String(rest[afterFirst..<lastQuote])
                afterText = rest[rest.index(after: lastQuote)...]
            } else {
                text = String(rest[afterFirst...])
                afterText = rest[rest.endIndex...]
            }
        } else if let bracket = rest.firstIndex(of: "[") {
            text = rest[..<bracket].trimmingCharacters(in: .whitespaces)
            afterText = rest[bracket...]
        } else {
            text = rest
            afterText = rest[rest.endIndex...]
        }
        let frame = parseFrame(in: afterText) ?? parseFrame(in: rest[...])
        return VoiceObservedElement(ref: ref, type: type, text: text, frame: frame)
    }

    private static func parseFrame(in text: Substring) -> VoiceScreenRect? {
        var search = text.startIndex..<text.endIndex
        while let open = text.range(of: "[", range: search) {
            guard let close = text.range(of: "]", range: open.upperBound..<text.endIndex) else { return nil }
            let inside = text[open.upperBound..<close.lowerBound]
            let nums = inside.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if nums.count == 4, nums[2] >= 0, nums[3] >= 0 {
                return VoiceScreenRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
            }
            search = close.upperBound..<text.endIndex
        }
        return nil
    }
}

enum VoiceAppIdentity {
    private static let aliases: [(canonical: String, names: [String])] = [
        ("com.apple.mobilenotes", ["com.apple.mobilenotes", "备忘录", "備忘錄", "notes", "mobilenotes"]),
        ("com.tencent.xin", ["com.tencent.xin", "微信", "wechat"]),
        ("com.apple.preferences", ["com.apple.preferences", "设置", "設定", "设定", "settings", "preferences"]),
        ("com.apple.reminders", ["com.apple.reminders", "提醒事项", "提醒事項", "reminders"]),
        ("com.apple.mobilesms", ["com.apple.mobilesms", "信息", "訊息", "讯息", "短信", "messages", "sms"]),
        ("com.apple.mobilemail", ["com.apple.mobilemail", "邮件", "郵件", "mail"]),
        ("com.apple.mobilecal", ["com.apple.mobilecal", "日历", "日曆", "calendar"]),
        ("com.apple.mobilesafari", ["com.apple.mobilesafari", "safari", "浏览器"]),
        ("net.whatsapp.whatsapp", ["net.whatsapp.whatsapp", "whatsapp"]),
        ("ph.telegra.telegraph", ["ph.telegra.telegraph", "telegram"]),
        ("com.burbn.instagram", ["com.burbn.instagram", "instagram"]),
        ("com.atebits.tweetie2", ["com.atebits.tweetie2", "twitter"]),
        ("com.facebook.messenger", ["com.facebook.messenger", "messenger"]),
        ("com.hammerandchisel.discord", ["com.hammerandchisel.discord", "discord"]),
        ("com.tinyspeck.chatlyio", ["com.tinyspeck.chatlyio", "slack"]),
    ]

    private static let genericMessageNouns: Set<String> = ["信息", "讯息", "短信", "邮件"]
    private static let messageNounModifiers = ["这条", "那条", "一条", "该", "这封", "那封", "一封", "发条", "发个", "把"]

    static let messagingApps: Set<String> = [
        "com.apple.mobilesms",
        "com.apple.mobilemail",
        "com.tencent.xin",
        "net.whatsapp.whatsapp",
        "ph.telegra.telegraph",
        "com.burbn.instagram",
        "com.atebits.tweetie2",
        "com.facebook.messenger",
        "com.hammerandchisel.discord",
        "com.tinyspeck.chatlyio",
    ]

    static func canonical(_ raw: String) -> String {
        let trimmed = VoiceTextNormalizer.toSimplified(raw.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        for entry in aliases {
            if entry.names.contains(trimmed) { return entry.canonical }
        }
        return trimmed
    }

    static func detectApp(in text: String) -> String? {
        let lower = VoiceTextNormalizer.toSimplified(text).lowercased()
        var best: (canonical: String, position: String.Index)?
        for entry in aliases {
            for name in entry.names {
                if let range = latestOccurrence(of: name, in: lower) {
                    if genericMessageNouns.contains(name) {
                        let prefix = lower[..<range.lowerBound]
                        if messageNounModifiers.contains(where: { prefix.hasSuffix($0) }) {
                            continue
                        }
                    }
                    if best == nil || range.lowerBound > best!.position {
                        best = (entry.canonical, range.lowerBound)
                    }
                }
            }
        }
        return best?.canonical
    }

    private static func latestOccurrence(of word: String, in text: String) -> Range<String.Index>? {
        guard !word.isEmpty else { return nil }
        let isCJK = word.unicodeScalars.contains(where: { $0.value > 0x2E80 })
        let boundary: (Character?) -> Bool = { $0.map { !$0.isLetter && !$0.isNumber } ?? true }
        var search = text.startIndex..<text.endIndex
        var latest: Range<String.Index>?
        while let range = text.range(of: word, range: search) {
            if isCJK {
                latest = range
            } else {
                let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
                let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
                if boundary(before) && boundary(after) { latest = range }
            }
            search = range.upperBound..<text.endIndex
        }
        return latest
    }

    fileprivate static func containsWholeWord(_ text: String, _ word: String) -> Bool {
        latestOccurrence(of: word, in: text) != nil
    }
}

enum VoiceActionTarget: Equatable, Sendable {
    case ref(Int)
    case point(Double, Double)
    case text(String)
}

struct VoiceProposedAction: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case launch(app: String)
        case tap(VoiceActionTarget)
        case longPress(VoiceActionTarget)
        case typeText(String, target: VoiceActionTarget?, clear: Bool)
        case key(String)
        case navigation
        case other(String)
    }

    let kind: Kind
    let hintText: String?
}

struct VoiceToolProposal: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case controlCancel
        case readOnly
        case readScreen
        case openApp(app: String, page: String?)
        case deviceActions([VoiceProposedAction])
    }

    let callID: String
    let toolName: String
    let rawArguments: String
    let delegationID: String?
    let speechItemID: String?
    let goalID: VoiceGoalID?
    let goalRevision: Int?
    let source: VoiceUtteranceSource
    let awaitingUtteranceTranscript: Bool
    let kind: Kind

    init(
        call: VoiceCall,
        goalID: VoiceGoalID?,
        goalRevision: Int?,
        source: VoiceUtteranceSource,
        awaitingUtteranceTranscript: Bool = false
    ) {
        self.callID = call.id
        self.toolName = call.name
        self.rawArguments = call.arguments
        self.delegationID = call.delegation
        self.speechItemID = call.speechItem
        self.goalID = goalID
        self.goalRevision = goalRevision
        self.source = source
        self.awaitingUtteranceTranscript = awaitingUtteranceTranscript
        self.kind = Self.parseKind(name: call.name, arguments: call.arguments)
    }

    var isControlCancel: Bool {
        if case .controlCancel = kind { return true }
        return false
    }

    var isReadOnly: Bool {
        switch kind {
        case .readOnly, .readScreen: true
        case .controlCancel, .openApp, .deviceActions: false
        }
    }

    var opensAppOnly: String? {
        switch kind {
        case .openApp(let app, _):
            return app
        case .deviceActions(let actions) where actions.count == 1:
            if case .launch(let app) = actions[0].kind { return app }
            return nil
        default:
            return nil
        }
    }

    var opensApp: String? {
        switch kind {
        case .openApp(let app, _):
            return app
        case .deviceActions(let actions):
            for action in actions {
                if case .launch(let app) = action.kind { return app }
            }
            return nil
        default:
            return nil
        }
    }

    var isPureNavigation: Bool {
        guard case .deviceActions(let actions) = kind, !actions.isEmpty else { return false }
        return actions.allSatisfy {
            if case .navigation = $0.kind { return true }
            return false
        }
    }

    func semanticKeys(using screen: VoiceObservedScreen) -> Set<String> {
        var keys: Set<String> = []
        switch kind {
        case .controlCancel, .readOnly, .readScreen:
            break
        case .openApp(let app, let page):
            keys.insert("open:\(app)\(page.map { ":\($0)" } ?? "")")
        case .deviceActions(let actions):
            for action in actions {
                switch action.kind {
                case .launch(let app):
                    keys.insert("open:\(app)")
                case .tap(let target), .longPress(let target):
                    for key in targetSemanticKeys(target, hint: action.hintText, screen: screen) {
                        keys.insert(key)
                    }
                case .typeText(let text, let target, _):
                    if let target {
                        for key in targetSemanticKeys(target, hint: action.hintText, screen: screen) {
                            keys.insert(key)
                        }
                    }
                    keys.insert("type:\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
                case .key(let key):
                    keys.insert("key:\(key.lowercased())")
                case .navigation:
                    break
                case .other(let name):
                    keys.insert("other:\(name)")
                }
            }
        }
        return keys
    }

    func createsDraft(using screen: VoiceObservedScreen) -> Bool {
        guard case .deviceActions(let actions) = kind else { return false }
        return actions.contains { action in
            if let hint = action.hintText, Self.matchesDraftCreation(hint) { return true }
            switch action.kind {
            case .tap(let target), .longPress(let target):
                return targetMatches(target, in: screen, predicate: Self.matchesDraftCreation)
            case .typeText(_, let target?, _):
                return targetMatches(target, in: screen, predicate: Self.matchesDraftCreation)
            default:
                return false
            }
        }
    }

    func attemptsSendOrCommit(using screen: VoiceObservedScreen, targetApp: String?) -> Bool {
        guard case .deviceActions(let actions) = kind else { return false }
        let app = screen.app ?? targetApp
        let isMessaging = app.map { VoiceAppIdentity.messagingApps.contains($0) } ?? false
        let hasUnframedSendControl = screen.elements.values.contains {
            !$0.isTextInput && $0.frame == nil && Self.matchesSendOrCommit($0.text)
        }
        return actions.contains { action in
            if let hint = action.hintText, Self.matchesSendOrCommit(hint) { return true }
            switch action.kind {
            case .tap(let target), .longPress(let target):
                if case .point = target, hasUnframedSendControl { return true }
                return targetMatches(target, in: screen, skipTextInputs: true, predicate: Self.matchesSendOrCommit)
            case .typeText(let text, let target, _):
                if isMessaging && text.contains(where: \.isNewline) { return true }
                if let target {
                    if case .point = target, hasUnframedSendControl { return true }
                    return targetMatches(target, in: screen, skipTextInputs: true, predicate: Self.matchesSendOrCommit)
                }
                return false
            case .key(let key):
                return isMessaging && (key.lowercased() == "return" || key.lowercased() == "enter")
            default:
                return false
            }
        }
    }

    private func targetSemanticKeys(_ target: VoiceActionTarget, hint: String?, screen: VoiceObservedScreen) -> [String] {
        var out: [String] = []
        if let hint, Self.matchesDraftCreation(hint) { out.append("draft:create") }
        switch target {
        case .ref(let ref):
            out.append("tap:ref:\(ref)")
            if let element = screen.elements[ref] {
                if Self.matchesDraftCreation(element.text) { out.append("draft:create") }
                if !element.isTextInput, Self.matchesSendOrCommit(element.text) { out.append("send:\(element.ref)") }
            }
        case .point(let x, let y):
            let hits = screen.elements(hitting: x, y: y)
            if hits.isEmpty {
                out.append("tap:pt:\(Int(x.rounded())):\(Int(y.rounded()))")
            } else {
                for element in hits {
                    out.append("tap:ref:\(element.ref)")
                    if Self.matchesDraftCreation(element.text) { out.append("draft:create") }
                    if !element.isTextInput, Self.matchesSendOrCommit(element.text) { out.append("send:\(element.ref)") }
                }
            }
        case .text(let text):
            out.append("tap:text:\(VoiceTextNormalizer.toSimplified(text).trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
            if Self.matchesDraftCreation(text) { out.append("draft:create") }
            if Self.matchesSendOrCommit(text) { out.append("send:text") }
        }
        return out
    }

    private func targetMatches(
        _ target: VoiceActionTarget,
        in screen: VoiceObservedScreen,
        skipTextInputs: Bool = false,
        predicate: (String) -> Bool
    ) -> Bool {
        switch target {
        case .ref(let ref):
            guard let element = screen.elements[ref] else { return false }
            if skipTextInputs && element.isTextInput { return false }
            return predicate(element.text)
        case .point(let x, let y):
            return screen.elements(hitting: x, y: y).contains { element in
                if skipTextInputs && element.isTextInput { return false }
                return predicate(element.text)
            }
        case .text(let text):
            return predicate(text)
        }
    }

    private static let draftCreationPhrases = [
        "新建备忘录", "新建草稿", "写备忘录", "写新备忘录", "新建", "撰写",
        "new note", "create note", "new draft", "compose", "new message", "new reminder", "新建提醒事项",
    ]

    private static let sendCommitPhrases = [
        "发送", "传送", "发出去", "发送消息", "发消息", "寄出", "提交", "发布", "分享", "共享",
        "send", "submit", "post", "publish", "share", "send message", "deliver",
    ]

    private static func matchesDraftCreation(_ text: String) -> Bool {
        matchesPhrases(text, draftCreationPhrases)
    }

    private static func matchesSendOrCommit(_ text: String) -> Bool {
        matchesPhrases(text, sendCommitPhrases)
    }

    private static func matchesPhrases(_ text: String, _ phrases: [String]) -> Bool {
        let lower = VoiceTextNormalizer.toSimplified(text.trimmingCharacters(in: .whitespacesAndNewlines)).lowercased()
        guard !lower.isEmpty else { return false }
        for phrase in phrases {
            if phrase.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
                if lower.contains(phrase) { return true }
            } else if VoiceAppIdentity.containsWholeWord(lower, phrase) {
                return true
            }
        }
        return false
    }

    private static func parseKind(name: String, arguments: String) -> Kind {
        let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
        switch name {
        case VoiceDirect.cancelCurrentTask:
            return .controlCancel
        case "get_ios_version":
            return .readOnly
        case "look", "read_screen":
            return .readScreen
        case "open_app":
            let raw = (args["app"] as? String) ?? (args["name"] as? String) ?? ""
            return .openApp(app: VoiceAppIdentity.canonical(raw), page: args["page"] as? String)
        case "open_settings":
            return .openApp(app: "com.apple.preferences", page: args["page"] as? String)
        case "tap_text":
            let text = (args["text"] as? String) ?? ""
            return .deviceActions([VoiceProposedAction(kind: .tap(.text(text)), hintText: text)])
        case "go_home":
            return .deviceActions([VoiceProposedAction(kind: .navigation, hintText: nil)])
        case "do":
            let rawActions = args["actions"] as? [[String: Any]] ?? []
            return .deviceActions(rawActions.flatMap(parseDoActions))
        default:
            return .deviceActions([VoiceProposedAction(kind: .other(name), hintText: nil)])
        }
    }

    private static func parseTarget(_ raw: Any?) -> VoiceActionTarget? {
        guard let raw else { return nil }
        if let ref = raw as? Int { return .ref(ref) }
        if let text = raw as? String { return .text(text) }
        if let array = raw as? [NSNumber], array.count >= 2 {
            return .point(array[0].doubleValue, array[1].doubleValue)
        }
        if let dict = raw as? [String: Any] {
            if let ref = dict["ref"] as? Int { return .ref(ref) }
            if let x = (dict["x"] as? NSNumber)?.doubleValue, let y = (dict["y"] as? NSNumber)?.doubleValue {
                return .point(x, y)
            }
            if let text = (dict["text"] as? String) ?? (dict["label"] as? String) ?? (dict["find"] as? String) { return .text(text) }
        }
        return nil
    }

    private static func parseDoActions(_ raw: [String: Any]) -> [VoiceProposedAction] {
        if let path = raw["path"] as? [String: Any], let steps = path["steps"] as? [[String: Any]], !steps.isEmpty {
            return steps.flatMap(parseDoActions)
        }
        if let steps = raw["path"] as? [[String: Any]], !steps.isEmpty {
            return steps.flatMap(parseDoActions)
        }
        return [parseDoAction(raw)]
    }

    private static func parseDoAction(_ raw: [String: Any]) -> VoiceProposedAction {
        let hint = (raw["label"] as? String) ?? (raw["target"] as? String) ?? (raw["action"] as? String)
            ?? (raw["run"] as? String) ?? ((raw["run"] as? [String: Any])?["name"] as? String)
        if let launch = raw["launch"] as? String {
            return VoiceProposedAction(kind: .launch(app: VoiceAppIdentity.canonical(launch)), hintText: hint)
        }
        if let launch = raw["launch"] as? [String: Any], let bundle = (launch["bundle"] as? String) ?? (launch["app"] as? String) {
            return VoiceProposedAction(kind: .launch(app: VoiceAppIdentity.canonical(bundle)), hintText: hint)
        }
        if let tapTarget = parseTarget(raw["tap"]) {
            let textHint: String? = if case .text(let s) = tapTarget { hint ?? s } else { hint }
            return VoiceProposedAction(kind: .tap(tapTarget), hintText: textHint)
        }
        if let pressTarget = parseTarget(raw["long_press"]) {
            let textHint: String? = if case .text(let s) = pressTarget { hint ?? s } else { hint }
            return VoiceProposedAction(kind: .longPress(pressTarget), hintText: textHint)
        }
        if let typed = raw["type"] as? String {
            let target = parseTarget(raw["ref"]) ?? parseTarget(raw["into"])
            return VoiceProposedAction(
                kind: .typeText(typed, target: target, clear: raw["clear"] as? Bool ?? false),
                hintText: hint
            )
        }
        if let key = raw["key"] as? String {
            return VoiceProposedAction(kind: .key(key), hintText: hint)
        }
        if raw["swipe"] != nil || raw["scroll_to"] != nil || raw["back"] != nil
            || raw["button"] != nil || raw["wait"] != nil || raw["wait_until"] != nil {
            return VoiceProposedAction(kind: .navigation, hintText: hint)
        }
        return VoiceProposedAction(kind: .other(raw.keys.sorted().joined(separator: ",")), hintText: hint)
    }
}

struct VoiceUtteranceAssessment: Equatable, Sendable {
    let relation: VoiceTaskRelation
    let goalID: VoiceGoalID?
    let revision: Int?
    let baseRevision: Int?
    let replacementScope: VoiceReplacementScope
    let needsFreshEvidence: Bool
    let forbidsSend: Bool
    let allowsSend: Bool
}

struct VoiceUtteranceRecord: Equatable, Sendable {
    let id: String
    let source: VoiceUtteranceSource
    let text: String
    let relation: VoiceTaskRelation
    let goalID: VoiceGoalID?
    let revision: Int?
    let baseRevision: Int?
    let replacementScope: VoiceReplacementScope
    let needsFreshEvidence: Bool
    let receivedAt: Date
}

struct VoiceGoalStep: Equatable, Sendable {
    let callID: String
    let goalID: VoiceGoalID
    let revision: Int
    let session: Int
    let toolName: String
    let semanticKeys: Set<String>
    let opensApp: String?
    let createsDraft: Bool
    let isReadOnly: Bool
    let isPureNavigation: Bool
    var outcome: VoiceStepOutcome
}

struct VoiceGoal: Equatable, Sendable {
    let id: VoiceGoalID
    var revision: Int
    var minimumAllowedRevision: Int
    var baseRevision: Int?
    var originalUtterance: String
    var latestUtterance: String
    var source: VoiceUtteranceSource
    var latestRelation: VoiceTaskRelation
    var replacementScope: VoiceReplacementScope
    var targetApp: String?
    var forbidsSend: Bool
    var needsFreshEvidence: Bool
    var stopped: Bool
    var observedScreen: VoiceObservedScreen
    var steps: [VoiceGoalStep]

    var hasExecutedOrUnknownWork: Bool {
        steps.contains { !$0.isReadOnly && $0.outcome.blocksRepeat }
    }

    var hasUnknownStep: Bool {
        steps.contains { $0.outcome == .unknown }
    }

    var hasRunningStep: Bool {
        steps.contains { $0.outcome == .running }
    }

    var hasActiveDraft: Bool {
        steps.contains { $0.createsDraft && $0.outcome.blocksRepeat }
    }

    func openedAppStep(for app: String) -> VoiceGoalStep? {
        steps.last { $0.opensApp == app && $0.outcome.blocksRepeat }
    }
}

enum VoiceTaskRelationClassifier {
    private static let backchannels: Set<String> = [
        "嗯", "哦", "好的", "好", "行", "明白", "知道了", "好吧", "可以",
        "uh-huh", "mm-hmm", "ok", "okay", "got it", "alright", "sure",
    ]
    private static let stopFillers: Set<String> = [
        "好了", "行了", "好吧", "嗯", "好的", "好", "ok", "okay", "alright",
    ]
    private static let pleasantries: Set<String> = [
        "你好", "嗨", "哈喽", "谢谢", "谢谢你", "多谢", "不客气", "没关系", "没事", "哈哈", "哈哈哈", "早安", "晚安",
        "hello", "hi", "hey", "thanks", "thank you", "you're welcome", "nice", "cool", "good morning", "good night",
    ]
    private static let chitchatPhrases = [
        "你叫什么名字", "你是谁", "讲个笑话", "今天心情", "聊聊天",
        "how are you", "who are you", "tell me a joke", "what is your name",
    ]
    private static let stopPhrases: Set<String> = [
        "停", "停止", "先停", "停一下", "先停一下", "停下来", "停吧", "先停吧", "别动", "别做了", "别写了", "不要写了",
        "不用写了", "别继续了", "不要继续了", "不用继续了", "别弄了", "不要弄了",
        "到这里就停", "到这里就停吧", "到这就停", "到这就停吧", "先到这里", "先到这里吧", "先到这", "先到这吧",
        "算了", "算了吧", "取消", "取消任务", "不要做了", "不用做了", "停止操作", "停止任务",
        "stop", "stop now", "stop it", "stop here", "stop right there", "cancel", "cancel that",
        "never mind", "abort", "stop doing that", "that's enough",
    ]
    private static let continuePhrases: Set<String> = [
        "继续", "接着", "接着做", "继续做", "继续吧", "往下做", "恢复",
        "continue", "resume", "keep going", "go on", "carry on", "proceed",
    ]
    private static let dictationVerbs = [
        "写上", "写入", "写一句", "写进", "输入", "打字", "打上", "填入", "填上",
        "type", "enter", "write", "insert",
    ]
    private static let forbidSendCues = [
        "先别发", "先别发送", "别发", "别发送", "不要发", "不要发送", "先不发", "不发送", "先不发送",
        "先别传送", "别传送", "不要传送", "先不传送", "暂不传送",
        "先不要发", "暂时不发", "暂不发", "千万别发", "千万不要发", "别发出", "不要发出", "不发出", "不发出去",
        "先别把", "别把这条消息发", "先存草稿", "只保存草稿", "保存为草稿", "保存草稿", "存成草稿", "存草稿",
        "先留在草稿", "留在草稿", "放草稿", "放进草稿", "留着别发", "先留着", "别提交", "不要提交", "先不提交", "暂不提交",
        "别寄", "不要寄", "先不寄",
        "don't send", "do not send", "hold off on sending", "hold off", "don't submit", "do not submit",
        "save as draft", "keep as draft", "leave as draft", "leave in draft", "leave it in draft", "keep in draft",
    ]
    private static let allowSendCues = [
        "现在发", "可以发", "发出去", "发出去吧", "现在发送", "可以发送", "现在可以发送", "现在可以发", "可以发了", "现在发吧", "发送吧", "发吧",
        "现在传送", "可以传送",
        "send it now", "send now", "go ahead and send", "you can send",
    ]
    private static let allowSendBlockers = [
        "不", "别", "勿", "莫", "没", "暂", "稍后", "等会儿", "等一下", "草稿", "留着", "先留",
        "don't", "do not", "not", "never", "wait", "hold", "draft",
    ]
    private static let negationMarkers = [
        "暂时不", "暂不", "先不要", "千万不要", "千万别", "先别", "先不", "不要", "还没", "别", "不", "勿", "莫",
    ]
    private static let sendActionTargets = [
        "发出去", "发过去", "发送", "传送", "发出", "发给", "发消息", "提交", "发布", "寄出", "推送",
    ]
    private static let wholeGoalReplaceCues = [
        "不用备忘录了", "别用备忘录了", "换个任务", "全部重写", "从头来", "重来", "不要写备忘录了",
        "start over", "replace the whole", "forget notes", "forget that", "instead, open", "switch to ",
    ]
    private static let remainingStepsReplaceCues = [
        "后面的步骤改成", "后面改成", "剩下的改成", "接下来改成",
        "for the remaining steps", "replace the remaining",
    ]
    private static let reviseCues = [
        "改成", "改为", "改一下", "改做", "换成", "换为", "修改", "更正", "改写", "改掉",
        "不对", "写错了", "说错了", "应该是", "其实", "不是",
        "change it to", "change to", "make it", "update to", "update it to", "actually", "instead of", "fix it to", "correction",
    ]
    private static let supplementCues = [
        "再加", "加上", "补上", "补充", "顺便加", "另外加", "也写上",
        "also add", "add to it", "and also", "append ",
    ]
    private static let launchPrefixes = [
        "打开", "开启", "进入", "去", "切到", "open ", "launch ", "go to ",
    ]

    static func isStopUtterance(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = normalize(trimmed)
        let unquoted = normalize(stripQuotedSpans(trimmed))
        let clauses = splitClauses(unquoted)
        let isLiteralStopDictation = (containsAny(unquoted, dictationVerbs) || unquoted.contains("把停字"))
            && (normalized.contains("停") || normalized.contains("stop"))
        return !isLiteralStopDictation && isStandaloneStop(clauses: clauses, normalized: unquoted)
    }

    static func classify(text: String, source: VoiceUtteranceSource, activeGoal: VoiceGoal?) -> VoiceUtteranceAssessment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.authorizesDeviceWork, !trimmed.isEmpty else {
            return VoiceUtteranceAssessment(
                relation: .chitchat, goalID: nil, revision: nil, baseRevision: nil,
                replacementScope: .none, needsFreshEvidence: false, forbidsSend: false, allowsSend: false
            )
        }

        let normalized = normalize(trimmed)
        let unquoted = normalize(stripQuotedSpans(trimmed))
        let clauses = splitClauses(unquoted)
        let isLiteralStopDictation = (containsAny(unquoted, dictationVerbs) || unquoted.contains("把停字"))
            && (normalized.contains("停") || normalized.contains("stop"))

        let forbidsSendCue = clauses.contains(where: isForbidSendClause)

        if !isLiteralStopDictation, isStandaloneStop(clauses: clauses, normalized: unquoted) {
            return VoiceUtteranceAssessment(
                relation: .stop, goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false,
                forbidsSend: forbidsSendCue || (activeGoal?.forbidsSend ?? false), allowsSend: false
            )
        }

        if isChitchat(clauses: clauses, normalized: unquoted) {
            return VoiceUtteranceAssessment(
                relation: .chitchat, goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false, forbidsSend: activeGoal?.forbidsSend ?? false, allowsSend: false
            )
        }

        let allowsSendCue = !forbidsSendCue && clauses.contains(where: isAllowSendClause)

        if let active = activeGoal, !active.stopped {
            if continuePhrases.contains(unquoted) {
                return VoiceUtteranceAssessment(
                    relation: .continueTask, goalID: active.id, revision: active.revision, baseRevision: active.revision,
                    replacementScope: .none, needsFreshEvidence: active.needsFreshEvidence || active.hasUnknownStep,
                    forbidsSend: active.forbidsSend, allowsSend: false
                )
            }

            if let replaceScope = replacementScopeIfReplace(normalized: unquoted, active: active) {
                return VoiceUtteranceAssessment(
                    relation: .replace, goalID: active.id, revision: active.revision + 1, baseRevision: active.revision,
                    replacementScope: replaceScope, needsFreshEvidence: active.hasExecutedOrUnknownWork,
                    forbidsSend: forbidsSendCue || (allowsSendCue ? false : active.forbidsSend),
                    allowsSend: allowsSendCue
                )
            }

            let mentionedApp = VoiceAppIdentity.detectApp(in: unquoted)
            if let mentionedApp, let activeApp = active.targetApp, mentionedApp != activeApp {
                return VoiceUtteranceAssessment(
                    relation: .independentNewTask, goalID: nil, revision: 1, baseRevision: nil,
                    replacementScope: .none, needsFreshEvidence: false, forbidsSend: forbidsSendCue, allowsSend: allowsSendCue
                )
            }
            if mentionedApp != nil, active.targetApp == nil,
               launchPrefixes.contains(where: { unquoted.hasPrefix($0) }) {
                return VoiceUtteranceAssessment(
                    relation: .independentNewTask, goalID: nil, revision: 1, baseRevision: nil,
                    replacementScope: .none, needsFreshEvidence: false, forbidsSend: forbidsSendCue, allowsSend: allowsSendCue
                )
            }

            let hasContentRevision = containsAny(unquoted, reviseCues)
                || containsAny(unquoted, supplementCues)
                || (mentionedApp != nil && mentionedApp == active.targetApp && containsAny(unquoted, dictationVerbs))
            if hasContentRevision || forbidsSendCue || allowsSendCue {
                let scope: VoiceReplacementScope = hasContentRevision ? .contentAndConstraints : .constraintsOnly
                let needsEvidence = hasContentRevision
                    ? active.hasExecutedOrUnknownWork
                    : (active.needsFreshEvidence || active.hasUnknownStep)
                return VoiceUtteranceAssessment(
                    relation: .supplementOrRevise, goalID: active.id, revision: active.revision + 1, baseRevision: active.revision,
                    replacementScope: scope, needsFreshEvidence: needsEvidence,
                    forbidsSend: forbidsSendCue || (allowsSendCue ? false : active.forbidsSend),
                    allowsSend: allowsSendCue
                )
            }
        }

        return VoiceUtteranceAssessment(
            relation: .independentNewTask, goalID: nil, revision: 1, baseRevision: nil,
            replacementScope: .none, needsFreshEvidence: false, forbidsSend: forbidsSendCue, allowsSend: allowsSendCue
        )
    }

    static func stripQuotedSpans(_ text: String) -> String {
        let pairs: [(Character, Character)] = [
            ("『", "』"), ("「", "」"), ("“", "”"), ("\"", "\""), ("‘", "’"), ("'", "'"), ("《", "》"),
        ]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if let (_, close) = pairs.first(where: { $0.0 == ch }) {
                let next = text.index(after: index)
                if let end = text[next...].firstIndex(of: close) {
                    index = text.index(after: end)
                    continue
                }
            }
            result.append(ch)
            index = text.index(after: index)
        }
        return result
    }

    private static func isForbidSendClause(_ clause: String) -> Bool {
        if containsAny(clause, forbidSendCues) { return true }
        return containsNegatedSend(clause)
    }

    private static func containsNegatedSend(_ clause: String) -> Bool {
        for neg in negationMarkers {
            var search = clause.startIndex..<clause.endIndex
            while let range = clause.range(of: neg, range: search) {
                let tail = clause[range.upperBound...]
                let windowEnd = tail.index(tail.startIndex, offsetBy: min(4, tail.count))
                let window = String(tail[..<windowEnd])
                for target in sendActionTargets where window.contains(target) {
                    return true
                }
                if tail.hasPrefix("发") {
                    let after = tail.dropFirst()
                    if after.isEmpty || after == "了" || after == "吧" || after == "掉" {
                        return true
                    }
                }
                search = range.upperBound..<clause.endIndex
            }
        }
        return false
    }

    private static func isAllowSendClause(_ clause: String) -> Bool {
        !containsAny(clause, dictationVerbs)
            && !containsAny(clause, allowSendBlockers)
            && containsAny(clause, allowSendCues)
    }

    private static func replacementScopeIfReplace(normalized: String, active: VoiceGoal) -> VoiceReplacementScope? {
        if containsAny(normalized, remainingStepsReplaceCues) { return .remainingSteps }
        if containsAny(normalized, wholeGoalReplaceCues) { return .wholeGoal }
        if let namedApp = VoiceAppIdentity.detectApp(in: normalized),
           let activeApp = active.targetApp, namedApp != activeApp,
           (normalized.contains("不用") || normalized.contains("别用") || normalized.contains("不要")
            || normalized.contains("改用") || normalized.contains("换成") || normalized.contains("instead")) {
            return .wholeGoal
        }
        return nil
    }

    private static func isStandaloneStop(clauses: [String], normalized: String) -> Bool {
        if stopPhrases.contains(normalized) { return true }
        guard !clauses.isEmpty else { return false }
        let hasStop = clauses.contains { stopPhrases.contains($0) }
        guard hasStop else { return false }
        return clauses.allSatisfy { part in
            stopPhrases.contains(part)
                || stopPhrases.contains(where: { $0.hasPrefix(part) })
                || isForbidSendClause(part)
                || stopFillers.contains(part)
        }
    }

    private static func isChitchat(clauses: [String], normalized: String) -> Bool {
        if pleasantries.contains(normalized) || backchannels.contains(normalized) { return true }
        if !clauses.isEmpty, clauses.allSatisfy({ backchannels.contains($0) || pleasantries.contains($0) }) { return true }
        return containsAny(normalized, chitchatPhrases)
    }

    private static func normalize(_ text: String) -> String {
        var result = VoiceTextNormalizer.toSimplified(text).lowercased().precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let last = result.last, ".!?。！？,，;；".contains(last) {
            result.removeLast()
        }
        return result
    }

    private static func splitClauses(_ text: String) -> [String] {
        text.split { ",，。.!！?？;；".contains($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        for phrase in phrases {
            if phrase.unicodeScalars.contains(where: { $0.value > 0x2E80 }) {
                if text.contains(phrase) { return true }
            } else if VoiceAppIdentity.containsWholeWord(text, phrase.trimmingCharacters(in: .whitespaces)) {
                return true
            }
        }
        return false
    }
}

enum VoiceExecutionDecision: Equatable, Sendable {
    enum DenialCode: String, Equatable, Sendable {
        case unauthorizedSource = "unauthorized_source"
        case awaitingUtteranceTranscript = "awaiting_utterance_transcript"
        case goalStopped = "goal_stopped"
        case staleRevision = "stale_revision"
        case forbiddenByConstraint = "forbidden_by_constraint"
        case unknownStepRepeat = "unknown_step_repeat"
        case duplicateDraftCreation = "duplicate_draft_creation"
        case duplicateStepInGoal = "duplicate_step_in_goal"
        case needsFreshEvidence = "needs_fresh_evidence"
    }

    case allow(goalID: VoiceGoalID, revision: Int)
    case deny(reason: String, code: DenialCode, goalID: VoiceGoalID?, revision: Int?)
}

enum VoiceExecutionGate {
    static func evaluate(proposal: VoiceToolProposal, goal: VoiceGoal, currentSession: Int) -> VoiceExecutionDecision {
        if !proposal.source.authorizesDeviceWork {
            return .deny(
                reason: "Blocked: source \(proposal.source.rawValue) cannot authorize phone input.",
                code: .unauthorizedSource, goalID: goal.id, revision: goal.revision
            )
        }
        if proposal.isControlCancel {
            return .allow(goalID: goal.id, revision: goal.revision)
        }
        if goal.stopped {
            return .deny(
                reason: "Blocked: goal \(goal.id) was stopped by the user. Do not tap, write, or continue.",
                code: .goalStopped, goalID: goal.id, revision: goal.revision
            )
        }
        if proposal.isReadOnly {
            return .allow(goalID: goal.id, revision: goal.revision)
        }
        if proposal.awaitingUtteranceTranscript {
            return .deny(
                reason: "Blocked: waiting for the latest spoken utterance transcript before running device input.",
                code: .awaitingUtteranceTranscript, goalID: goal.id, revision: goal.revision
            )
        }
        if let proposedRevision = proposal.goalRevision, proposedRevision < goal.minimumAllowedRevision {
            return .deny(
                reason: "Blocked: goal \(goal.id) moved to r\(goal.revision). Do not run steps from r\(proposedRevision).",
                code: .staleRevision, goalID: goal.id, revision: goal.revision
            )
        }
        if goal.forbidsSend, proposal.attemptsSendOrCommit(using: goal.observedScreen, targetApp: goal.targetApp) {
            return .deny(
                reason: "Blocked: goal \(goal.id) r\(goal.revision) forbids sending or submitting. Keep the draft unsent.",
                code: .forbiddenByConstraint, goalID: goal.id, revision: goal.revision
            )
        }

        let createsDraft = proposal.createsDraft(using: goal.observedScreen)
        let semanticKeys = proposal.semanticKeys(using: goal.observedScreen)

        if let unknownPrior = matchingUnknownStep(proposal: proposal, createsDraft: createsDraft, semanticKeys: semanticKeys, in: goal) {
            return .deny(
                reason: "Blocked: step \(unknownPrior.callID) in goal \(goal.id) has an unknown outcome and may already have run. Call look first to verify the screen instead of repeating it.",
                code: .unknownStepRepeat, goalID: goal.id, revision: goal.revision
            )
        }

        if createsDraft, goal.hasActiveDraft, goal.replacementScope != .wholeGoal {
            let priorID = goal.steps.last(where: { $0.createsDraft && $0.outcome.blocksRepeat })?.callID ?? "previous"
            return .deny(
                reason: "Blocked: goal \(goal.id) already has an active draft from \(priorID). Update the existing draft instead of creating another.",
                code: .duplicateDraftCreation, goalID: goal.id, revision: goal.revision
            )
        }

        if let app = proposal.opensAppOnly, goal.replacementScope != .wholeGoal,
           let priorOpen = goal.openedAppStep(for: app) {
            let stillInSameApp = goal.observedScreen.app == nil || goal.observedScreen.app == app
            if stillInSameApp && (goal.revision > priorOpen.revision || currentSession != priorOpen.session) {
                return .deny(
                    reason: "Blocked: goal \(goal.id) already opened \(app) in \(priorOpen.callID). Do not reopen it; continue on the current screen.",
                    code: .duplicateStepInGoal, goalID: goal.id, revision: goal.revision
                )
            }
        }

        if !proposal.isPureNavigation, !semanticKeys.isEmpty,
           let duplicate = goal.steps.last(where: {
               !$0.isReadOnly && !$0.isPureNavigation && $0.outcome.blocksRepeat
                   && $0.semanticKeys == semanticKeys
                   && ($0.revision < goal.revision || $0.session != currentSession)
           }) {
            return .deny(
                reason: "Blocked: step \(duplicate.callID) in goal \(goal.id) already ran with the same action. Do not repeat it.",
                code: .duplicateStepInGoal, goalID: goal.id, revision: goal.revision
            )
        }

        if goal.needsFreshEvidence {
            return .deny(
                reason: "Blocked: goal \(goal.id) r\(goal.revision) needs fresh screen evidence before further input. Call look first.",
                code: .needsFreshEvidence, goalID: goal.id, revision: goal.revision
            )
        }

        return .allow(goalID: goal.id, revision: goal.revision)
    }

    private static func matchingUnknownStep(
        proposal: VoiceToolProposal,
        createsDraft: Bool,
        semanticKeys: Set<String>,
        in goal: VoiceGoal
    ) -> VoiceGoalStep? {
        for step in goal.steps.reversed() where step.outcome == .unknown {
            if createsDraft && step.createsDraft { return step }
            if let app = proposal.opensAppOnly, step.opensApp == app { return step }
            if !proposal.isPureNavigation, !semanticKeys.isEmpty, !step.semanticKeys.isDisjoint(with: semanticKeys) {
                return step
            }
        }
        return nil
    }
}

struct VoiceGoalTracker: Equatable, Sendable {
    static let noteByteLimit = 480

    private var nextGoalNumber = 1
    private var nextUtteranceNumber = 1
    private(set) var activeGoal: VoiceGoal?
    private(set) var history: [VoiceGoal] = []
    private(set) var utterances: [VoiceUtteranceRecord] = []

    private struct UtteranceBinding: Equatable, Sendable {
        let goalID: VoiceGoalID?
        let revision: Int?
        let source: VoiceUtteranceSource
    }

    private struct RecoveryReceipt: Equatable, Sendable {
        let goalID: VoiceGoalID
        let revision: Int
        let session: Int
    }

    private var bindingByItem: [String: UtteranceBinding] = [:]
    private var bindingByDelegation: [String: UtteranceBinding] = [:]
    private var bindingByResponse: [String: UtteranceBinding] = [:]
    private var itemByResponse: [String: String] = [:]
    private var pendingResponsesByItem: [String: [String]] = [:]
    private var pendingUtteranceItems: Set<String> = []
    private var resolvedTranscriptItems: Set<String> = []
    private var latestCommittedItemID: String?
    private var goalIDByCall: [String: VoiceGoalID] = [:]
    private var provisionalGoalByItem: [String: VoiceGoalID] = [:]
    private var latestBinding: UtteranceBinding?
    private var recoverySent: RecoveryReceipt?

    mutating func noteCommittedUtterance(itemID: String) {
        guard !itemID.isEmpty else { return }
        guard bindingByItem[itemID] == nil, !resolvedTranscriptItems.contains(itemID) else { return }
        latestCommittedItemID = itemID
        pendingUtteranceItems.insert(itemID)
    }

    mutating func clearPendingUtterance(itemID: String?) {
        guard let itemID, !itemID.isEmpty else { return }
        pendingUtteranceItems.remove(itemID)
        resolvedTranscriptItems.insert(itemID)
        if latestCommittedItemID == itemID {
            latestCommittedItemID = nil
        }
        if let pending = pendingResponsesByItem.removeValue(forKey: itemID) {
            let fallback = activeGoal.map { UtteranceBinding(goalID: $0.id, revision: $0.revision, source: $0.source) } ?? latestBinding
            if let fallback {
                for responseID in pending { bindingByResponse[responseID] = fallback }
            }
        }
    }

    mutating func ingestCompleteUtterance(
        text: String,
        itemID: String?,
        delegationID: String?,
        source: VoiceUtteranceSource,
        at date: Date
    ) -> VoiceUtteranceRecord {
        if let itemID {
            pendingUtteranceItems.remove(itemID)
            resolvedTranscriptItems.insert(itemID)
        }
        let utteranceID = itemID ?? delegationID ?? nextUtteranceID()

        if source.authorizesDeviceWork,
           let itemID, let provisionalID = provisionalGoalByItem.removeValue(forKey: itemID),
           var active = activeGoal, active.id == provisionalID {
            let assessment = VoiceTaskRelationClassifier.classify(text: text, source: source, activeGoal: nil)
            active.originalUtterance = text
            active.latestUtterance = text
            active.source = source
            active.targetApp = active.targetApp ?? VoiceAppIdentity.detectApp(in: VoiceTaskRelationClassifier.stripQuotedSpans(text))
            active.forbidsSend = active.forbidsSend || assessment.forbidsSend
            if assessment.relation == .stop {
                active.stopped = true
                active.latestRelation = .stop
            }
            activeGoal = active
            let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
            recordBinding(binding, itemID: itemID, delegationID: delegationID)
            let record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: assessment.relation,
                goalID: active.id, revision: active.revision, baseRevision: nil,
                replacementScope: .none, needsFreshEvidence: active.needsFreshEvidence, receivedAt: date
            )
            utterances.append(record)
            return record
        }

        let assessment = VoiceTaskRelationClassifier.classify(text: text, source: source, activeGoal: activeGoal)
        let record: VoiceUtteranceRecord

        switch assessment.relation {
        case .chitchat:
            if !source.authorizesDeviceWork {
                let binding = UtteranceBinding(goalID: nil, revision: nil, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            } else {
                clearPendingUtterance(itemID: itemID)
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .chitchat,
                goalID: assessment.goalID, revision: assessment.revision, baseRevision: assessment.baseRevision,
                replacementScope: .none, needsFreshEvidence: false, receivedAt: date
            )

        case .stop:
            if var active = activeGoal {
                active.stopped = true
                active.latestRelation = .stop
                active.forbidsSend = active.forbidsSend || assessment.forbidsSend
                activeGoal = active
                let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            } else {
                var stoppedGoal = makeProvisionalGoal(itemID: itemID, source: source)
                stoppedGoal.originalUtterance = text
                stoppedGoal.latestUtterance = text
                stoppedGoal.latestRelation = .stop
                stoppedGoal.forbidsSend = assessment.forbidsSend
                stoppedGoal.stopped = true
                activeGoal = stoppedGoal
                let binding = UtteranceBinding(goalID: stoppedGoal.id, revision: stoppedGoal.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .stop,
                goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: false, receivedAt: date
            )

        case .continueTask:
            if var active = activeGoal {
                active.latestRelation = .continueTask
                active.needsFreshEvidence = active.needsFreshEvidence || assessment.needsFreshEvidence
                activeGoal = active
                let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
            }
            record = VoiceUtteranceRecord(
                id: utteranceID, source: source, text: text, relation: .continueTask,
                goalID: activeGoal?.id, revision: activeGoal?.revision, baseRevision: activeGoal?.revision,
                replacementScope: .none, needsFreshEvidence: activeGoal?.needsFreshEvidence ?? false, receivedAt: date
            )

        case .supplementOrRevise, .replace:
            if var active = activeGoal {
                let previous = active.revision
                active.baseRevision = previous
                active.revision = previous + 1
                if assessment.replacementScope.invalidatesEarlierRevisions {
                    active.minimumAllowedRevision = max(active.minimumAllowedRevision, active.revision)
                }
                active.latestUtterance = text
                active.latestRelation = assessment.relation
                active.replacementScope = assessment.replacementScope
                active.forbidsSend = assessment.forbidsSend
                active.needsFreshEvidence = active.needsFreshEvidence || assessment.needsFreshEvidence
                if let detected = VoiceAppIdentity.detectApp(in: VoiceTaskRelationClassifier.stripQuotedSpans(text)),
                   assessment.replacementScope == .wholeGoal || active.targetApp == nil {
                    active.targetApp = detected
                }
                activeGoal = active
                let binding = UtteranceBinding(goalID: active.id, revision: active.revision, source: source)
                recordBinding(binding, itemID: itemID, delegationID: delegationID)
                record = VoiceUtteranceRecord(
                    id: utteranceID, source: source, text: text, relation: assessment.relation,
                    goalID: active.id, revision: active.revision, baseRevision: previous,
                    replacementScope: assessment.replacementScope, needsFreshEvidence: active.needsFreshEvidence, receivedAt: date
                )
            } else {
                record = createNewGoal(
                    utteranceID: utteranceID, text: text, source: source,
                    forbidsSend: assessment.forbidsSend, itemID: itemID, delegationID: delegationID, at: date
                )
            }

        case .independentNewTask:
            record = createNewGoal(
                utteranceID: utteranceID, text: text, source: source,
                forbidsSend: assessment.forbidsSend, itemID: itemID, delegationID: delegationID, at: date
            )
        }

        utterances.append(record)
        return record
    }

    mutating func bindResponse(_ responseID: String, itemID: String?) {
        let effectiveItem = itemID ?? latestCommittedItemID
        if let effectiveItem {
            itemByResponse[responseID] = effectiveItem
            if let binding = bindingByItem[effectiveItem] {
                bindingByResponse[responseID] = binding
            } else if resolvedTranscriptItems.contains(effectiveItem) {
                if let active = activeGoal {
                    bindingByResponse[responseID] = UtteranceBinding(goalID: active.id, revision: active.revision, source: active.source)
                } else if let latestBinding {
                    bindingByResponse[responseID] = latestBinding
                }
            } else {
                pendingUtteranceItems.insert(effectiveItem)
                pendingResponsesByItem[effectiveItem, default: []].append(responseID)
            }
        } else if let latestBinding {
            bindingByResponse[responseID] = latestBinding
        }
    }

    mutating func resolveBinding(
        delegationID: String?,
        responseID: String?,
        speechItemID: String?,
        defaultSource: VoiceUtteranceSource
    ) -> (goalID: VoiceGoalID, revision: Int, source: VoiceUtteranceSource, awaitingTranscript: Bool) {
        let effectiveItem = speechItemID ?? responseID.flatMap { itemByResponse[$0] }
        let transcriptionActive = !utterances.isEmpty
        let hasPendingTranscript = transcriptionActive && (
            effectiveItem.map {
                pendingUtteranceItems.contains($0) && bindingByItem[$0] == nil
            } == true || (delegationID == nil && !pendingUtteranceItems.isEmpty)
        )
        if hasPendingTranscript {
            let goal = activeGoal ?? makeProvisionalGoal(itemID: effectiveItem ?? latestCommittedItemID, source: defaultSource)
            return (goal.id, goal.revision, defaultSource, true)
        }
        let found = delegationID.flatMap({ bindingByDelegation[$0] })
            ?? effectiveItem.flatMap({ bindingByItem[$0] })
            ?? responseID.flatMap({ bindingByResponse[$0] })
            ?? latestBinding
        if let found, !found.source.authorizesDeviceWork {
            let goal = activeGoal ?? makeProvisionalGoal(itemID: effectiveItem, source: found.source)
            return (goal.id, found.revision ?? goal.revision, found.source, false)
        }
        if let found, let goalID = found.goalID {
            return (goalID, found.revision ?? goal(for: goalID)?.revision ?? 1, found.source, false)
        }
        if let active = activeGoal {
            return (active.id, active.revision, active.source, false)
        }
        let provisional = makeProvisionalGoal(itemID: effectiveItem, source: defaultSource)
        return (provisional.id, provisional.revision, provisional.source, false)
    }

    mutating func admit(_ proposal: VoiceToolProposal, session: Int) -> VoiceExecutionDecision {
        let targetGoal: VoiceGoal
        if let goalID = proposal.goalID, let existing = goal(for: goalID) {
            targetGoal = existing
        } else if let active = activeGoal {
            targetGoal = active
        } else {
            targetGoal = makeProvisionalGoal(itemID: proposal.speechItemID, source: proposal.source)
        }

        let decision = VoiceExecutionGate.evaluate(proposal: proposal, goal: targetGoal, currentSession: session)
        guard case .allow(let goalID, let revision) = decision else { return decision }

        let createsDraft = proposal.createsDraft(using: targetGoal.observedScreen)
        let semanticKeys = proposal.semanticKeys(using: targetGoal.observedScreen)
        let step = VoiceGoalStep(
            callID: proposal.callID,
            goalID: goalID,
            revision: revision,
            session: session,
            toolName: proposal.toolName,
            semanticKeys: semanticKeys,
            opensApp: proposal.opensApp,
            createsDraft: createsDraft,
            isReadOnly: proposal.isReadOnly,
            isPureNavigation: proposal.isPureNavigation,
            outcome: .running
        )
        mutateGoal(id: goalID) { goal in
            if goal.targetApp == nil, let opened = proposal.opensApp {
                goal.targetApp = opened
            }
            goal.steps.append(step)
        }
        goalIDByCall[proposal.callID] = goalID
        return decision
    }

    @discardableResult
    mutating func recordStepFinished(callID: String, state: VoiceCall.State, output: String) -> VoiceStepOutcome {
        let outcome = VoiceStepOutcome.classify(state: state, output: output)
        guard let goalID = goalIDByCall[callID] else { return outcome }
        let update = VoiceObservedScreen.parseUpdate(output)
        mutateGoal(id: goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.callID == callID }) else { return }
            goal.steps[index].outcome = outcome
            if let update { goal.observedScreen.apply(update) }
            if outcome == .unknown {
                goal.needsFreshEvidence = true
            } else if outcome == .succeeded, goal.steps[index].isReadOnly,
                      (goal.steps[index].toolName == "look" || goal.steps[index].toolName == "read_screen"),
                      update?.hasUsableEvidence == true {
                goal.needsFreshEvidence = false
            }
        }
        return outcome
    }

    mutating func recordStepCancelled(callID: String) {
        guard let goalID = goalIDByCall[callID] else { return }
        mutateGoal(id: goalID) { goal in
            guard let index = goal.steps.firstIndex(where: { $0.callID == callID }),
                  goal.steps[index].outcome == .running else { return }
            goal.steps[index].outcome = .blocked
        }
    }

    mutating func markActiveGoalStopped() {
        activeGoal?.stopped = true
        activeGoal?.latestRelation = .stop
    }

    func revisionNote(for record: VoiceUtteranceRecord) -> String? {
        guard record.relation == .supplementOrRevise || record.relation == .replace,
              let goalID = record.goalID, let goal = goal(for: goalID),
              goal.hasExecutedOrUnknownWork || goal.forbidsSend else { return nil }
        return formatGoalNote(prefix: "Goal update", goal: goal)
    }

    mutating func recoveryNote(forSession session: Int) -> String? {
        guard let goal = activeGoal, !goal.stopped,
              goal.revision > 1 || goal.hasUnknownStep || goal.forbidsSend else { return nil }
        if let sent = recoverySent, sent.goalID == goal.id, sent.revision == goal.revision, sent.session == session {
            return nil
        }
        recoverySent = RecoveryReceipt(goalID: goal.id, revision: goal.revision, session: session)
        return formatGoalNote(prefix: "Reconnect goal recovery", goal: goal)
    }

    mutating func sessionEnded() {
        bindingByDelegation.removeAll()
        bindingByResponse.removeAll()
        itemByResponse.removeAll()
        pendingResponsesByItem.removeAll()
        pendingUtteranceItems.removeAll()
        resolvedTranscriptItems.removeAll()
        latestCommittedItemID = nil
        latestBinding = nil
    }

    mutating func conversationStopped() {
        sessionEnded()
        bindingByItem.removeAll()
        provisionalGoalByItem.removeAll()
        if let active = activeGoal, !active.hasRunningStep, !active.hasUnknownStep {
            history.append(active)
            activeGoal = nil
        }
    }

    func goal(for id: VoiceGoalID) -> VoiceGoal? {
        if activeGoal?.id == id { return activeGoal }
        return history.last { $0.id == id }
    }

    private mutating func createNewGoal(
        utteranceID: String,
        text: String,
        source: VoiceUtteranceSource,
        forbidsSend: Bool,
        itemID: String?,
        delegationID: String?,
        at date: Date
    ) -> VoiceUtteranceRecord {
        if let active = activeGoal { history.append(active) }
        let id = nextGoalID()
        let goal = VoiceGoal(
            id: id,
            revision: 1,
            minimumAllowedRevision: 1,
            baseRevision: nil,
            originalUtterance: text,
            latestUtterance: text,
            source: source,
            latestRelation: .independentNewTask,
            replacementScope: .none,
            targetApp: VoiceAppIdentity.detectApp(in: VoiceTaskRelationClassifier.stripQuotedSpans(text)),
            forbidsSend: forbidsSend,
            needsFreshEvidence: false,
            stopped: false,
            observedScreen: VoiceObservedScreen(),
            steps: []
        )
        activeGoal = goal
        let binding = UtteranceBinding(goalID: id, revision: 1, source: source)
        recordBinding(binding, itemID: itemID, delegationID: delegationID)
        return VoiceUtteranceRecord(
            id: utteranceID, source: source, text: text, relation: .independentNewTask,
            goalID: id, revision: 1, baseRevision: nil, replacementScope: .none,
            needsFreshEvidence: false, receivedAt: date
        )
    }

    private mutating func makeProvisionalGoal(itemID: String?, source: VoiceUtteranceSource) -> VoiceGoal {
        if let active = activeGoal { history.append(active) }
        let id = nextGoalID()
        let goal = VoiceGoal(
            id: id,
            revision: 1,
            minimumAllowedRevision: 1,
            baseRevision: nil,
            originalUtterance: "",
            latestUtterance: "",
            source: source,
            latestRelation: .independentNewTask,
            replacementScope: .none,
            targetApp: nil,
            forbidsSend: false,
            needsFreshEvidence: false,
            stopped: false,
            observedScreen: VoiceObservedScreen(),
            steps: []
        )
        activeGoal = goal
        if let itemID { provisionalGoalByItem[itemID] = id }
        return goal
    }

    private mutating func recordBinding(_ binding: UtteranceBinding, itemID: String?, delegationID: String?) {
        if let itemID {
            bindingByItem[itemID] = binding
            if let pending = pendingResponsesByItem.removeValue(forKey: itemID) {
                for responseID in pending { bindingByResponse[responseID] = binding }
            }
        }
        if let delegationID { bindingByDelegation[delegationID] = binding }
        latestBinding = binding
    }

    private mutating func mutateGoal(id: VoiceGoalID, _ body: (inout VoiceGoal) -> Void) {
        if var active = activeGoal, active.id == id {
            body(&active)
            activeGoal = active
            return
        }
        if let index = history.lastIndex(where: { $0.id == id }) {
            body(&history[index])
        }
    }

    private mutating func nextGoalID() -> VoiceGoalID {
        let id = VoiceGoalID(rawValue: "g\(nextGoalNumber)")
        nextGoalNumber += 1
        return id
    }

    private mutating func nextUtteranceID() -> String {
        let id = "u\(nextUtteranceNumber)"
        nextUtteranceNumber += 1
        return id
    }

    private func formatGoalNote(prefix: String, goal: VoiceGoal) -> String {
        var required = [
            "\(prefix) \(goal.id) r\(goal.revision) (\(goal.latestRelation.rawValue), scope=\(goal.replacementScope.rawValue))",
        ]
        if goal.forbidsSend { required.append("do not send") }
        if goal.needsFreshEvidence { required.append("call look first") }
        if goal.hasActiveDraft && goal.replacementScope != .wholeGoal { required.append("edit existing draft (clear:true)") }
        let suffix = ". Do not repeat succeeded or unknown steps."
        var base = required.joined(separator: "; ")

        let candidates = goal.steps.filter { !$0.isReadOnly && $0.outcome.blocksRepeat }.suffix(4)
        var keptEntries: [String] = []
        for step in candidates.reversed() {
            let shortID = step.callID.count > 24 ? String(step.callID.prefix(16)) + ".." + String(step.callID.suffix(6)) : step.callID
            let entry = "\(shortID):\(step.toolName):\(step.outcome.rawValue)"
            let trial = (([entry] + keptEntries)).joined(separator: ",")
            let projected = base + "; keep[\(trial)]" + suffix
            if projected.utf8.count <= Self.noteByteLimit {
                keptEntries.insert(entry, at: 0)
            }
        }
        if !keptEntries.isEmpty {
            base += "; keep[\(keptEntries.joined(separator: ","))]"
        }

        if !goal.latestUtterance.isEmpty {
            let overhead = "; latest=\"\"".utf8.count + suffix.utf8.count
            let remaining = Self.noteByteLimit - base.utf8.count - overhead
            if remaining >= 12 {
                let snippet = Self.utf8Prefix(goal.latestUtterance, bytes: remaining)
                if !snippet.isEmpty { base += "; latest=\"\(snippet)\"" }
            }
        }

        return Self.utf8Prefix(base + suffix, bytes: Self.noteByteLimit)
    }

    private static func utf8Prefix(_ text: String, bytes limit: Int) -> String {
        guard limit > 0 else { return "" }
        let utf8 = text.utf8
        guard let end = utf8.index(utf8.startIndex, offsetBy: limit, limitedBy: utf8.endIndex) else { return text }
        var boundary = end
        while boundary != utf8.endIndex, utf8[boundary] & 0xC0 == 0x80 {
            utf8.formIndex(before: &boundary)
        }
        return String(decoding: bytesPrefix(utf8, upTo: boundary), as: UTF8.self)
    }

    private static func bytesPrefix(_ utf8: String.UTF8View, upTo end: String.UTF8View.Index) -> Substring.UTF8View {
        utf8[..<end]
    }
}
