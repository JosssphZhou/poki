import Foundation

enum VoiceEntryRoute: String, Equatable, Sendable {
    case directEphemeralCredential = "direct_ephemeral_credential"
    case voiceBridge = "voice_bridge"
    case dictationChatTTS = "dictation_chat_tts"
    case chatgptResponses = "chatgpt_responses"
    case rehearsal = "rehearsal"

    var voiceHost: VoiceHost {
        self == .voiceBridge ? .voiceBridge : .phoneDirect
    }

    static func dictationRoute(chatProvider: ModelProvider, chatGPTSignedIn: Bool) -> VoiceEntryRoute {
        chatProvider == .chatgpt && chatGPTSignedIn ? .chatgptResponses : .dictationChatTTS
    }

    static func resolve(
        usesChatGPTSubscription: Bool = false,
        directAccount: VoiceAccount?,
        hasDirectKey: Bool,
        hasBridge: Bool,
        canDictate: Bool,
        microphone: Bool,
        hasAppAudio: Bool = false,
        chatProvider: ModelProvider,
        chatGPTSignedIn: Bool,
        rehearsing: Bool
    ) -> VoiceEntryRoute? {
        if rehearsing { return .rehearsal }
        if usesChatGPTSubscription, microphone, !hasAppAudio { return .chatgptResponses }
        if directAccount != nil, hasDirectKey { return .directEphemeralCredential }
        if hasBridge { return .voiceBridge }
        if canDictate, microphone, !hasAppAudio {
            return dictationRoute(chatProvider: chatProvider, chatGPTSignedIn: chatGPTSignedIn)
        }
        return nil
    }
}

enum VoiceHost: String, Equatable, Sendable {
    case phoneDirect = "phone_direct"
    case voiceBridge = "voice_bridge"
}

enum VoiceActionHost: String, Equatable, Sendable {
    case none
    case phoneLocal = "phone_local"
    case macTools = "mac_tools"
    case mixed
}

enum VoiceObservationSource: String, Equatable, Sendable {
    case none
    case phoneTreeAndScreenshot = "phone_tree_and_screenshot"
    case phoneTreeAndLiveVision = "phone_tree_and_live_vision"
    case phoneAccessibilityTree = "phone_accessibility_tree"
    case phoneScreenshotOCR = "phone_screenshot_ocr"
    case phoneHostScreenshot = "phone_host_screenshot"
    case phoneStaleScreenshot = "phone_stale_screenshot"
    case phoneDeviceInfo = "phone_device_info"
    case phoneToolOutput = "phone_tool_output"
    case phoneChatLoop = "phone_chat_loop"
    case macMCPAccessibility = "mac_mcp_accessibility"
    case macMCPOCR = "mac_mcp_ocr"
    case macMCPActionReadback = "mac_mcp_action_readback"
    case macMCPAction = "mac_mcp_action"
    case macMCPDeviceInfo = "mac_mcp_device_info"
}

enum VoiceSessionTransport: String, Equatable, Sendable {
    case realtime
    case live
    case codexLive = "codex_live"
    case dictation
    case responses
    case rehearsal
}

enum TurnMilestone: String, CaseIterable, Sendable {
    case said
    case heard
    case call
    case firstEffectiveAction = "first_effective_action"
    case toolDone = "tool_done"
    case targetConfirmed = "target_confirmed"
    case delivered
    case spoken
}

struct TurnMoment: Equatable, Sendable {
    let date: Date
    let uptimeMS: UInt64?

    init(date: Date, uptimeMS: UInt64? = nil) {
        self.date = date
        self.uptimeMS = uptimeMS
    }
}

struct VoiceCallTiming: Sendable {
    let actionIndex: Int
    let actionHost: VoiceActionHost
    let observationSource: VoiceObservationSource
    let dispatchMoment: TurnMoment
    let endMoment: TurnMoment
    let hostDurationMS: Int
    let bridgeMS: Int?
    let roundtripMS: Int?
    let effective: Bool
    let confirmed: Bool
}

enum VoiceTurnTarget: Equatable, Sendable {
    case screenText(expected: String, app: String?)
    case appForeground(name: String?, bundleID: String?)
    case settingsPage(page: String)
    case homeScreen
    case screenRead
    case deviceInfo

    var requiresAction: Bool {
        switch self {
        case .screenRead, .deviceInfo: false
        case .screenText, .appForeground, .settingsPage, .homeScreen: true
        }
    }

    var jsonPayload: [String: Any] {
        switch self {
        case .screenText(let expected, let app):
            var payload: [String: Any] = ["kind": "screen_text", "expected": expected]
            if let app, !app.isEmpty { payload["app"] = app }
            return payload
        case .appForeground(let name, let bundleID):
            var payload: [String: Any] = ["kind": "app_foreground"]
            if let name, !name.isEmpty { payload["name"] = name }
            if let bundleID, !bundleID.isEmpty { payload["bundle_id"] = bundleID }
            return payload
        case .settingsPage(let page):
            return ["kind": "settings_page", "page": page]
        case .homeScreen:
            return ["kind": "home_screen"]
        case .screenRead:
            return ["kind": "screen_read"]
        case .deviceInfo:
            return ["kind": "device_info"]
        }
    }

    static func fromUtterance(_ raw: String) -> VoiceTurnTarget? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = VoiceTurnTiming.normalize(trimmed)

        if matchesAny(normalized, patterns: [
            #"\bios\s*version\b"#, #"\bwhat\s+version\b"#, #"\bdevice\s+model\b"#,
            #"系统版本"#, #"ios\s*版本"#, #"什么版本"#, #"什么型号"#, #"手機型號"#, #"系統版本"#
        ]) {
            return .deviceInfo
        }

        let appMention = VoiceTurnTiming.mentionedApp(in: normalized)

        if let expected = extractExpectedScreenText(raw: trimmed, normalized: normalized) {
            return .screenText(expected: expected, app: appMention?.canonicalName)
        }

        if let page = VoiceTurnTiming.mentionedSettingsPage(in: normalized),
           appMention?.bundleID == "com.apple.Preferences"
            || normalized.contains("settings")
            || normalized.contains("设置")
            || normalized.contains("設定")
            || matchesAny(normalized, patterns: [#"\b(open|go to|show)\b"#, #"打开|打開|进入|進入|去"#]) {
            return .settingsPage(page: page)
        }

        if matchesAny(normalized, patterns: [
            #"\b(go\s+home|home\s+screen|go\s+to\s+(the\s+)?home)\b"#,
            #"回到?主屏"#, #"回到?桌面"#, #"返回主屏"#, #"回到?主畫面"#
        ]) {
            return .homeScreen
        }

        if matchesAny(normalized, patterns: [
            #"\b(open|launch|switch\s+to|go\s+to)\b"#,
            #"打开|打開|启动|啟動|切换到|切換到|进入|進入"#
        ]) {
            if let appMention {
                return .appForeground(name: appMention.canonicalName, bundleID: appMention.bundleID)
            }
            if let named = extractOpenAppName(trimmed) {
                return .appForeground(name: named, bundleID: nil)
            }
        }

        if matchesAny(normalized, patterns: [
            #"\b(what'?s|what\s+is)\s+on\s+(the\s+)?screen\b"#,
            #"\b(read|look\s+at|check|describe)\s+(the\s+)?(current\s+)?screen\b"#,
            #"屏幕上有"#, #"屏幕上是什么"#, #"屏幕上显示"#, #"屏幕上顯示"#, #"看一下屏幕"#, #"看看屏幕"#, #"读一下屏幕"#, #"现在在哪个页面"#
        ]) {
            return .screenRead
        }

        return nil
    }

    static func fromToolCall(name: String, arguments: String) -> VoiceTurnTarget? {
        let args = VoiceTurnTiming.parseJSONObject(arguments) ?? [:]
        switch name {
        case "open_app":
            if let page = (args["page"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty {
                return .settingsPage(page: page)
            }
            let appName = ((args["app"] as? String) ?? (args["name"] as? String))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundle = (args["bundle_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedBundle = bundle?.isEmpty == false ? bundle : appName.flatMap { VoiceTurnTiming.canonicalApp(for: $0)?.bundleID }
            if appName?.isEmpty == false || resolvedBundle != nil {
                return .appForeground(name: appName?.isEmpty == false ? appName : nil, bundleID: resolvedBundle)
            }
            return nil
        case "open_settings":
            if let page = (args["page"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty {
                return .settingsPage(page: page)
            }
            return .appForeground(name: "Settings", bundleID: "com.apple.Preferences")
        case "go_home":
            return .homeScreen
        case "do":
            guard let actions = args["actions"] as? [[String: Any]] else { return nil }
            var launchedApp: String?
            var resolved: VoiceTurnTarget?
            for action in actions {
                if let bundle = (action["launch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty {
                    launchedApp = bundle
                    resolved = .appForeground(name: VoiceTurnTiming.canonicalApp(for: bundle)?.canonicalName, bundleID: bundle)
                }
                if let button = action["button"] as? String, button.lowercased() == "home" {
                    launchedApp = nil
                    resolved = .homeScreen
                }
                if let text = (action["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    resolved = .screenText(expected: text, app: launchedApp)
                }
                if let text = (action["scroll_to"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    resolved = .screenText(expected: text, app: launchedApp)
                }
                if let text = (action["wait_until"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    resolved = .screenText(expected: text, app: launchedApp)
                }
            }
            return resolved
        default:
            return nil
        }
    }

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func extractExpectedScreenText(raw: String, normalized: String) -> String? {
        if let quoted = firstCapture(
            in: raw,
            pattern: #"(?:show|display|type|enter|input|press|tap|search|find|显示|顯示|输入|輸入|按(?:一下|下)?|点击?|點擊|搜索|打出)\s*["“「]([^"”」]+)["”」]"#
        ) {
            return quoted
        }
        if let number = firstCapture(
            in: normalized,
            pattern: #"(?:\b(?:show|display|press|tap|enter|type|input)\s+|(?:显示|顯示|按(?:一下|下)?|点击?|點擊|输入|輸入|打出)\s*)([+-]?\d+(?:[.,]\d+)?%?)(?=$|[\s,.!?;。！？，])"#
        ) {
            return number
        }
        if let typed = firstCapture(
            in: raw,
            pattern: #"(?:\b(?:type|enter|input)\s+|(?:输入|輸入|打出)\s*)([^\n,.!?;。！？，]{1,40})"#
        ) {
            let cleaned = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    private static func extractOpenAppName(_ raw: String) -> String? {
        guard let candidate = firstCapture(
            in: raw,
            pattern: #"(?:\b(?:open|launch|switch\s+to)\s+|(?:打开|打開|启动|啟動|切换到|切換到)\s*)([^\n,.!?;。！？，]{1,32})"#
        ) else { return nil }
        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let lowered = cleaned.lowercased()
        if ["it", "that", "this", "the screen", "screen"].contains(lowered) { return nil }
        return cleaned
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else { return nil }
        let value = text[capture].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum VoiceTurnTiming {
    static let logArea = "voice-timing"

    struct AppAlias: Sendable {
        let bundleID: String
        let canonicalName: String
        let tokens: [String]
    }

    struct ObservedElement: Sendable {
        let role: String
        let text: String
    }

    struct ObservedPhoneScreen: Sendable {
        let appHeader: String?
        let appTokens: [String]
        let headerLines: [String]
        let elements: [ObservedElement]
        let liveDescription: String?
        let hasFailureMarker: Bool
        let hasScreenChangedTrue: Bool
        let hasFoundByScrollTo: Bool

        var readable: Bool {
            !hasFailureMarker && (!elements.isEmpty || liveDescription != nil || appHeader != nil)
        }

        func appMatches(_ expected: [String]) -> Bool {
            VoiceTurnTiming.appMatches(observed: appTokens, expected: expected)
        }
    }

    private static let readOnlyTools: Set<String> = ["get_ios_version", "look", "read_screen", VoiceDirect.cancelCurrentTask]
    private static let directActionTools: Set<String> = ["open_app", "open_settings", "tap_text", "go_home"]
    private static let passiveDoKeys: Set<String> = ["wait", "wait_until", "handoff"]

    private static let failureHeaderPrefixes = [
        "not_sent:",
        "cancelled:",
        "error:",
        "unknown:",
        "read: failed",
        "poki:",
    ]

    private static let unconfirmedHeaderMarkers = [
        "touch effect: unconfirmed",
        "screen_changed: false",
        "send check: not confirmed",
        "not confirmed",
        "could not be confirmed",
        "is not in front",
        "screen: locked",
        "read: failed",
        "not_sent:",
        "approval_required",
        "nothing was sent",
        "nothing was tapped",
        "the elements of the read before keep their numbers",
    ]

    private static let appAliases: [AppAlias] = [
        AppAlias(bundleID: "com.apple.calculator", canonicalName: "Calculator", tokens: ["com.apple.calculator", "calculator", "计算器", "計算機"]),
        AppAlias(bundleID: "com.apple.Preferences", canonicalName: "Settings", tokens: ["com.apple.preferences", "settings", "preferences", "设置", "設定"]),
        AppAlias(bundleID: "com.apple.springboard", canonicalName: "SpringBoard", tokens: ["com.apple.springboard", "springboard", "home screen", "主屏幕", "主畫面"]),
        AppAlias(bundleID: "com.apple.weather", canonicalName: "Weather", tokens: ["com.apple.weather", "weather", "天气", "天氣"]),
        AppAlias(bundleID: "com.apple.mobiletimer", canonicalName: "Clock", tokens: ["com.apple.mobiletimer", "clock", "时钟", "時鐘"]),
        AppAlias(bundleID: "com.apple.mobilecal", canonicalName: "Calendar", tokens: ["com.apple.mobilecal", "calendar", "日历", "行事曆"]),
        AppAlias(bundleID: "com.apple.mobilenotes", canonicalName: "Notes", tokens: ["com.apple.mobilenotes", "notes", "备忘录", "備忘錄"]),
        AppAlias(bundleID: "com.apple.mobilesms", canonicalName: "Messages", tokens: ["com.apple.mobilesms", "messages", "信息", "訊息"]),
        AppAlias(bundleID: "com.apple.mobilesafari", canonicalName: "Safari", tokens: ["com.apple.mobilesafari", "safari"]),
        AppAlias(bundleID: "com.apple.mobileslideshow", canonicalName: "Photos", tokens: ["com.apple.mobileslideshow", "photos", "照片"]),
        AppAlias(bundleID: "com.apple.camera", canonicalName: "Camera", tokens: ["com.apple.camera", "camera", "相机", "相機"]),
        AppAlias(bundleID: "com.apple.maps", canonicalName: "Maps", tokens: ["com.apple.maps", "maps", "地图", "地圖"]),
        AppAlias(bundleID: "com.apple.music", canonicalName: "Music", tokens: ["com.apple.music", "music", "音乐", "音樂"]),
        AppAlias(bundleID: "com.apple.mobilemail", canonicalName: "Mail", tokens: ["com.apple.mobilemail", "mail", "邮件", "郵件"]),
        AppAlias(bundleID: "com.apple.reminders", canonicalName: "Reminders", tokens: ["com.apple.reminders", "reminders", "提醒事项", "提醒事項"]),
        AppAlias(bundleID: "com.apple.mobilephone", canonicalName: "Phone", tokens: ["com.apple.mobilephone", "phone", "电话", "電話"]),
        AppAlias(bundleID: "com.tencent.xin", canonicalName: "WeChat", tokens: ["com.tencent.xin", "wechat", "微信"]),
    ]

    private static let settingsPageAliases: [(page: String, titles: [String])] = [
        ("about", ["about", "关于本机", "關於本機"]),
        ("accessibility", ["accessibility", "辅助功能", "輔助使用"]),
        ("battery", ["battery", "电池", "電池"]),
        ("bluetooth", ["bluetooth", "蓝牙", "藍牙"]),
        ("camera", ["camera", "相机", "相機"]),
        ("cellular", ["cellular", "蜂窝网络", "行動服務"]),
        ("control_center", ["control center", "控制中心"]),
        ("date_time", ["date & time", "date and time", "日期与时间", "日期與時間"]),
        ("display", ["display & brightness", "display", "显示与亮度", "螢幕顯示與亮度"]),
        ("focus", ["focus", "专注模式", "專注模式"]),
        ("general", ["general", "通用", "一般"]),
        ("keyboard", ["keyboard", "键盘", "鍵盤"]),
        ("language_region", ["language & region", "语言与地区", "語言與地區"]),
        ("location", ["location services", "location", "定位服务", "定位服務"]),
        ("notifications", ["notifications", "通知"]),
        ("personal_hotspot", ["personal hotspot", "个人热点", "個人熱點"]),
        ("privacy", ["privacy & security", "privacy", "隐私与安全性", "隱私權與安全性"]),
        ("safari", ["safari"]),
        ("screen_time", ["screen time", "屏幕使用时间", "螢幕使用時間"]),
        ("siri", ["siri"]),
        ("software_update", ["software update", "软件更新", "軟體更新"]),
        ("sounds", ["sounds & haptics", "sounds", "声音与触感", "聲音與觸覺回饋"]),
        ("vpn", ["vpn"]),
        ("wallpaper", ["wallpaper", "墙纸", "背景圖片"]),
        ("wifi", ["wi-fi", "wifi", "wlan", "无线局域网"]),
    ]

    static func elapsedMS(from start: TurnMoment, to end: TurnMoment) -> Int {
        if let s = start.uptimeMS, let e = end.uptimeMS {
            return e >= s ? Int(e - s) : 0
        }
        return max(0, Int(end.date.timeIntervalSince(start.date) * 1000))
    }

    static func isActionCandidate(name: String, arguments: String) -> Bool {
        if readOnlyTools.contains(name) { return false }
        if directActionTools.contains(name) { return true }
        guard name == "do" else { return false }
        guard let object = parseJSONObject(arguments), let actions = object["actions"] as? [[String: Any]] else {
            return true
        }
        if actions.isEmpty { return object["finish"] as? Bool == true }
        return actions.contains { action in
            action.keys.contains { !passiveDoKeys.contains($0) }
        }
    }

    static func observationSource(
        name: String,
        actionHost: VoiceActionHost,
        state: VoiceCall.State,
        output: String,
        hasScreen: Bool,
        usedLiveVision: Bool,
        bridgeSource: String? = nil
    ) -> VoiceObservationSource {
        switch actionHost {
        case .none:
            return .none
        case .macTools:
            guard state == .done, let bridgeSource else { return .none }
            return VoiceObservationSource(rawValue: bridgeSource) ?? .none
        case .phoneLocal, .mixed:
            if name == "get_ios_version" { return state == .done ? .phoneDeviceInfo : .none }
            let screen = parsePhoneScreen(output)
            if screen.headerLines.contains(where: { $0.lowercased().contains("the screenshot is the one of the read before") }) {
                return .phoneStaleScreenshot
            }
            if screen.headerLines.contains(where: {
                let lower = $0.lowercased()
                return lower.hasPrefix("read: failed") || lower.hasPrefix("not_sent:") || lower.hasPrefix("error:") || lower.hasPrefix("unknown:")
            }) {
                return .none
            }
            if usedLiveVision || screen.liveDescription != nil { return .phoneTreeAndLiveVision }
            if screen.headerLines.contains(where: { $0.lowercased().contains("taken apart from the runner") }) { return .phoneHostScreenshot }
            if output.contains("read from the picture") { return .phoneScreenshotOCR }
            if hasScreen { return .phoneTreeAndScreenshot }
            if screen.appHeader != nil || !screen.elements.isEmpty || screen.hasScreenChangedTrue {
                return .phoneAccessibilityTree
            }
            if state == .done, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .phoneToolOutput
            }
            return .none
        }
    }

    static func didTakeEffect(
        name: String,
        arguments: String,
        actionHost: VoiceActionHost,
        state: VoiceCall.State,
        output: String,
        checkedTap: Bool = true,
        bridgeEffective: Bool? = nil
    ) -> Bool {
        if actionHost == .macTools {
            return bridgeEffective ?? false
        }
        guard state == .done, isActionCandidate(name: name, arguments: arguments) else { return false }
        if name == "tap_text", !checkedTap { return false }
        let screen = parsePhoneScreen(output)
        if screen.hasFailureMarker { return false }
        if screen.hasScreenChangedTrue { return true }

        let args = parseJSONObject(arguments) ?? [:]
        if name == "open_app" {
            if let page = (args["page"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !page.isEmpty {
                return screen.appMatches(["com.apple.Preferences"])
            }
            let expected = [(args["app"] as? String), (args["name"] as? String), (args["bundle_id"] as? String)]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return !expected.isEmpty && screen.appMatches(expected)
        }
        if name == "do", let actions = args["actions"] as? [[String: Any]] {
            for action in actions {
                if let bundle = (action["launch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !bundle.isEmpty,
                   screen.appMatches([bundle]) {
                    return true
                }
                if let button = action["button"] as? String, button.lowercased() == "home",
                   screen.appMatches(["com.apple.springboard"]) {
                    return true
                }
                if action["scroll_to"] != nil, screen.hasFoundByScrollTo {
                    return true
                }
                if let typed = (action["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty,
                   matchesExpectedText(in: screen, expected: typed) {
                    return true
                }
            }
        }
        return false
    }

    static func isTargetIndependentlyConfirmed(
        name: String,
        actionHost: VoiceActionHost,
        state: VoiceCall.State,
        output: String,
        observationSource: VoiceObservationSource,
        target: VoiceTurnTarget?,
        effective: Bool,
        hasPriorEffectiveAction: Bool,
        bridgeConfirmed: Bool? = nil
    ) -> Bool {
        if actionHost == .macTools {
            return bridgeConfirmed ?? false
        }
        guard state == .done, observationSource != .none, observationSource != .phoneStaleScreenshot,
              let target else { return false }
        if target.requiresAction, !(effective || hasPriorEffectiveAction) { return false }

        if case .deviceInfo = target {
            guard name == "get_ios_version", let json = parseJSONObject(output) else { return false }
            let version = (json["ios_version"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let model = (json["model"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !version.isEmpty || !model.isEmpty
        }

        let screen = parsePhoneScreen(output)
        guard screen.readable else { return false }

        switch target {
        case .deviceInfo:
            return false
        case .screenRead:
            return !screen.elements.isEmpty || screen.liveDescription != nil || screen.appHeader != nil
        case .homeScreen:
            return screen.appMatches(["com.apple.springboard"])
        case .appForeground(let expectedName, let expectedBundle):
            let expected = [expectedBundle, expectedName].compactMap { $0 }.filter { !$0.isEmpty }
            return !expected.isEmpty && screen.appMatches(expected)
        case .settingsPage(let page):
            guard screen.appMatches(["com.apple.Preferences"]) else { return false }
            let key = normalize(page).replacingOccurrences(of: " ", with: "_")
            let expectedTitles = settingsPageAliases.first(where: { $0.page == key })?.titles ?? [page]
            return expectedTitles.contains { matchesExpectedText(in: screen, expected: $0) }
        case .screenText(let expected, let app):
            if let app, !app.isEmpty, !screen.appTokens.isEmpty, !screen.appMatches([app]) {
                return false
            }
            return matchesExpectedText(in: screen, expected: expected)
        }
    }

    static func parsePhoneScreen(_ output: String) -> ObservedPhoneScreen {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        var headerLines: [String] = []
        var elements: [ObservedElement] = []
        var appHeader: String?
        var appTokens: [String] = []
        var liveDescription: String?
        var hasFailureMarker = false
        var hasScreenChangedTrue = false
        var hasFoundByScrollTo = false
        var inElements = false
        var inFooter = false

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let lowered = trimmed.lowercased()

            if trimmed.hasPrefix("Current screen description: ") {
                let desc = String(trimmed.dropFirst("Current screen description: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !desc.isEmpty { liveDescription = desc }
                inFooter = true
                continue
            }
            if trimmed.hasPrefix("Current screen description failed:")
                || trimmed.hasPrefix("Screenshot unavailable:")
                || trimmed.hasPrefix("Screenshot descriptions require")
                || trimmed.hasPrefix("gone since the last read:")
                || trimmed.hasPrefix("took:") {
                inFooter = true
                continue
            }

            if !inElements && !inFooter {
                if lowered.hasPrefix("elements") && (lowered.hasPrefix("elements (") || lowered.hasPrefix("elements:")) {
                    inElements = true
                    continue
                }
                headerLines.append(trimmed)
                if failureHeaderPrefixes.contains(where: { lowered.hasPrefix($0) })
                    || unconfirmedHeaderMarkers.contains(where: { lowered.contains($0) }) {
                    hasFailureMarker = true
                }
                if lowered.hasPrefix("screen_changed: true") {
                    hasScreenChangedTrue = true
                }
                if trimmed.hasPrefix("app: ") {
                    let head = String(trimmed.dropFirst("app: ".count))
                        .components(separatedBy: "   read:").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !head.isEmpty, head.lowercased() != "unknown" {
                        appHeader = head
                        appTokens.append(contentsOf: extractAppTokens(from: head))
                    }
                }
            } else if inElements && !inFooter {
                if trimmed.hasPrefix("found by scroll_to: ") {
                    hasFoundByScrollTo = true
                    let payload = String(trimmed.dropFirst("found by scroll_to: ".count))
                    if let parsed = parseElementLine(payload) { elements.append(parsed) }
                } else if let parsed = parseElementLine(trimmed) {
                    elements.append(parsed)
                }
            }
        }

        return ObservedPhoneScreen(
            appHeader: appHeader,
            appTokens: appTokens,
            headerLines: headerLines,
            elements: elements,
            liveDescription: liveDescription,
            hasFailureMarker: hasFailureMarker,
            hasScreenChangedTrue: hasScreenChangedTrue,
            hasFoundByScrollTo: hasFoundByScrollTo
        )
    }

    static func line(session: Int, turn: Int, at moment: TurnMoment, event: String, fields: [(String, String)]) -> String {
        let base = "session=\(session) flow=voice turn=\(turn) t_ms=\(moment.uptimeMS ?? 0) event=\(event)"
        guard !fields.isEmpty else { return base }
        return base + " " + fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }

    static func summaryFields(for clock: TurnClock) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("entry_route", clock.entryRoute?.rawValue ?? "none"),
            ("voice_host", clock.voiceHost?.rawValue ?? "none"),
            ("action_host", clock.actionHost.rawValue),
            ("observation_source", clock.observationSource.rawValue),
        ]
        for milestone in TurnMilestone.allCases {
            fields.append(("\(milestone.rawValue)_ms", clock.ms(milestone).map(String.init) ?? "none"))
        }
        fields.append(("phone_local_ms", "\(clock.phoneLocalMS)"))
        fields.append(("mac_tools_ms", "\(clock.macToolsMS)"))
        fields.append(("mac_tools_roundtrip_ms", "\(clock.macToolsRoundtripMS)"))
        fields.append(("calls", clock.callNames.isEmpty ? "none" : clock.callNames.joined(separator: ",")))
        return fields
    }

    static func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func normalize(_ value: String) -> String {
        let folded = value.precomposedStringWithCompatibilityMapping.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.replacingOccurrences(
            of: #"(?<=[\u{3400}-\u{9FFF}\u{F900}-\u{FAFF}\u{3040}-\u{30FF}])\s+(?=[\u{3400}-\u{9FFF}\u{F900}-\u{FAFF}\u{3040}-\u{30FF}])"#,
            with: "",
            options: .regularExpression
        )
    }

    static func canonicalApp(for token: String) -> AppAlias? {
        let norm = normalize(token)
        guard !norm.isEmpty else { return nil }
        return appAliases.first { $0.tokens.contains(norm) }
    }

    static func mentionedApp(in normalizedUtterance: String) -> AppAlias? {
        for alias in appAliases {
            for token in alias.tokens {
                if token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == " ") }) {
                    let escaped = NSRegularExpression.escapedPattern(for: token)
                    if normalizedUtterance.range(of: "(?:^|[^a-z0-9])\(escaped)(?:$|[^a-z0-9])", options: .regularExpression) != nil {
                        return alias
                    }
                } else if normalizedUtterance.contains(token) {
                    return alias
                }
            }
        }
        return nil
    }

    static func mentionedSettingsPage(in normalizedUtterance: String) -> String? {
        for entry in settingsPageAliases {
            for title in entry.titles {
                if title.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " " || $0 == "-" || $0 == "&") }) {
                    let escaped = NSRegularExpression.escapedPattern(for: title)
                    if normalizedUtterance.range(of: "(?:^|[^a-z0-9])\(escaped)(?:$|[^a-z0-9])", options: .regularExpression) != nil {
                        return entry.page
                    }
                } else if normalizedUtterance.contains(title) {
                    return entry.page
                }
            }
        }
        return nil
    }

    static func appMatches(observed: [String], expected: [String]) -> Bool {
        let obsList = observed.map(normalize).filter { !$0.isEmpty }
        let expList = expected.map(normalize).filter { !$0.isEmpty }
        guard !obsList.isEmpty, !expList.isEmpty else { return false }
        for exp in expList {
            let expGroup = canonicalApp(for: exp)
            for obs in obsList {
                if obs == exp { return true }
                if let expGroup, expGroup.tokens.contains(obs) { return true }
                if obs.contains("."), exp.count >= 3, obs.split(separator: ".").map(String.init).contains(exp) {
                    return true
                }
            }
        }
        return false
    }

    private static func extractAppTokens(from header: String) -> [String] {
        var tokens = [header]
        if let open = header.lastIndex(of: "("), let close = header.lastIndex(of: ")"), open < close {
            let name = header[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
            let bundle = header[header.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { tokens.append(name) }
            if !bundle.isEmpty { tokens.append(bundle) }
        }
        return tokens
    }

    private static func parseElementLine(_ line: String) -> ObservedElement? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^[+~ ]*\d+\s+([A-Za-z][A-Za-z0-9_]*)\s+"((?:\\.|[^"\\])*)"(?:\s+\[|$)"#,
            options: []
        ) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              let roleRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else { return nil }
        let role = String(line[roleRange])
        let text = String(line[textRange]).replacingOccurrences(of: #"\""#, with: "\"")
        return ObservedElement(role: role, text: text)
    }

    private static func isButtonRole(_ role: String) -> Bool {
        role.range(of: #"^(?:AX|XCUIElementType)?(?:Button|Key|KeyboardKey)$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func matchesExpectedText(in screen: ObservedPhoneScreen, expected: String) -> Bool {
        let normExpected = normalize(expected)
        guard !normExpected.isEmpty else { return false }
        let numeric = normExpected.range(of: #"^[+-]?\d+(?:[.,]\d+)?%?$"#, options: .regularExpression) != nil
        var candidates: [ObservedElement]
        if numeric {
            candidates = screen.elements.filter { !isButtonRole($0.role) }
        } else {
            candidates = screen.elements
        }
        if candidates.isEmpty, let desc = screen.liveDescription {
            candidates = [ObservedElement(role: "StaticText", text: desc)]
        }
        guard !candidates.isEmpty else { return false }

        let escaped = NSRegularExpression.escapedPattern(for: normExpected)
        let numericPattern = "(?:^|[\\s=:：])\(escaped)(?=$|[\\s.,!?;。！？])"
        let isASCIIWord = normExpected.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let asciiWordPattern = "(?:^|[^a-z0-9])\(escaped)(?:$|[^a-z0-9])"

        for element in candidates {
            let normText = normalize(element.text)
            guard !normText.isEmpty else { continue }
            if normText == normExpected { return true }
            if numeric {
                if normText.range(of: #"\b\d{4}-\d{2}-\d{2}\b|\b\d{1,2}:\d{2}(?::\d{2})?\b"#, options: .regularExpression) != nil {
                    continue
                }
                if normText.range(of: numericPattern, options: .regularExpression) != nil { return true }
            } else if normExpected.count >= 2 {
                if isASCIIWord {
                    if normText.range(of: asciiWordPattern, options: .regularExpression) != nil { return true }
                } else if normText.contains(normExpected) {
                    return true
                }
            }
        }
        return false
    }
}
