import SwiftUI
import UIKit

/// A conversation's picture in the list (ESP-468): the icon of the app its task worked in, as on the
/// Home Screen; the bear for a chat with no app in it; an outside agent's badge for its own session.
/// A voice conversation or a hand-over wears a small badge in the corner saying so.
struct ConversationIcon: View {
    var session: SavedSession
    /// The app the live task is in now, for the conversation that is running.
    var liveApp: String?
    var size: CGFloat

    private var app: String? { liveApp ?? session.mainApp }

    var body: some View {
        main
            .overlay(alignment: .bottomTrailing) { badge.offset(x: 4, y: 4) }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var main: some View {
        if let app {
            AppIconTile(name: app, size: size)
        } else if session.kind == .agent || session.kind == .handoff {
            AgentTile(name: session.client ?? "", size: size)
        } else {
            PokiAvatar(size: size)
        }
    }

    @ViewBuilder private var badge: some View {
        let small = size * 0.46
        switch session.kind {
        case .voice:
            Image(systemName: "waveform").font(.system(size: small * 0.5, weight: .semibold)).foregroundStyle(.white)
                .frame(width: small, height: small).background(Tint.blue, in: .circle)
                .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
        case .handoff where app != nil:
            AgentTile(name: session.client ?? "", size: small)
                .padding(2).background(Color(.systemBackground), in: .rect(cornerRadius: small * 0.3, style: .continuous))
        case .handoff:
            PokiAvatar(size: small)
                .padding(2).background(Color(.systemBackground), in: .rect(cornerRadius: small * 0.34, style: .continuous))
        default:
            EmptyView()
        }
    }
}

/// An outside agent as a tile in the app icons' shape: its provider's logo on the provider's colour.
/// In dark, a near-black colour (OpenAI, Cursor) would vanish into the page, so the tile is lifted to a
/// grey with a light edge and the logo turns white.
struct AgentTile: View {
    var name: String
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        let lifted = scheme == .dark && isDark
        Group {
            if let logo = Caller.logo(name) {
                Image(logo).resizable().renderingMode(.template).scaledToFit().frame(width: size * 0.56, height: size * 0.56)
            } else {
                Text(verbatim: Caller.initials(name)).font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(lifted ? Color.white : Caller.mark(name))
        .frame(width: size, height: size)
        .background(lifted ? Color(white: 0.22) : Caller.tint(name), in: shape)
        .overlay(shape.strokeBorder(lifted ? Color.white.opacity(0.28) : Color(.separator).opacity(Caller.isLight(name) ? 1 : 0), lineWidth: lifted ? 1 : 0.5))
    }

    private var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(Caller.tint(name)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.3
    }
}

/// An app's icon in the Home Screen's shape, or a plain app glyph when Poki cannot get it.
struct AppIconTile: View {
    var name: String
    var size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let icon = AppIcons.icon(named: name) {
                Image(uiImage: icon).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "app.dashed").font(.system(size: size * 0.5, weight: .regular)).foregroundStyle(Color(.secondaryLabel))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(.tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Tint.ring, lineWidth: 0.5))
    }
}

/// The icons of the apps Poki's tasks work in, by the name Poki saw on screen ("Notes", "备忘录").
/// First the icon installed on this iPhone, through iOS's own private calls, which a self-signed app
/// may make (they are looked up at run time, so a newer iOS that drops one only loses this source);
/// then the App Store icon Poki carries for the apps of its capsules; otherwise none.
@MainActor
enum AppIcons {
    private static var cache: [String: UIImage?] = [:]

    static func icon(named name: String) -> UIImage? {
        if let known = cache[name] { return known }
        let capsule = AppCapsule.catalog.first { $0.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let id = capsule?.id ?? appleApps[name] ?? Installed.bundleID(named: name)
        let icon = id.flatMap(Installed.icon) ?? capsule.flatMap { UIImage(named: $0.asset) }
        cache[name] = icon
        return icon
    }

    /// Apple's own apps, by their English and Chinese names, for those no capsule has.
    private static let appleApps: [String: String] = {
        let apps: [(String, [String])] = [
            ("com.apple.Preferences", ["Settings", "设置", "設定"]),
            ("com.apple.mobilesafari", ["Safari", "Safari浏览器", "Safari 瀏覽器"]),
            ("com.apple.mobileslideshow", ["Photos", "照片"]),
            ("com.apple.camera", ["Camera", "相机", "相機"]),
            ("com.apple.mobilemail", ["Mail", "邮件", "郵件"]),
            ("com.apple.Maps", ["Maps", "地图", "地圖"]),
            ("com.apple.mobilecal", ["Calendar", "日历", "行事曆"]),
            ("com.apple.reminders", ["Reminders", "提醒事项", "提醒事項"]),
            ("com.apple.mobiletimer", ["Clock", "时钟", "時鐘"]),
            ("com.apple.mobilephone", ["Phone", "电话", "電話"]),
            ("com.apple.MobileAddressBook", ["Contacts", "通讯录", "聯絡人"]),
            ("com.apple.Music", ["Music", "音乐", "音樂"]),
            ("com.apple.AppStore", ["App Store"]),
            ("com.apple.TestFlight", ["TestFlight"]),
            ("com.apple.weather", ["Weather", "天气", "天氣"]),
            ("com.apple.calculator", ["Calculator", "计算器", "計算機"]),
            ("com.apple.DocumentsApp", ["Files", "文件", "檔案"]),
            ("com.apple.Health", ["Health", "健康"]),
            ("com.apple.Passbook", ["Wallet", "钱包", "錢包"]),
            ("com.apple.shortcuts", ["Shortcuts", "快捷指令", "捷徑"]),
            ("com.apple.findmy", ["Find My", "查找", "尋找"]),
            ("com.apple.podcasts", ["Podcasts", "播客", "Podcast"]),
            ("com.apple.news", ["News"]),
            ("com.apple.tips", ["Tips", "提示", "提示"]),
            ("com.apple.Translate", ["Translate", "翻译", "翻譯"]),
            ("com.apple.VoiceMemos", ["Voice Memos", "语音备忘录", "語音備忘錄"]),
            ("com.apple.freeform", ["Freeform", "无边记", "無邊記"]),
            ("com.apple.journal", ["Journal", "手记", "手記"]),
            ("com.apple.Passwords", ["Passwords", "密码", "密碼"]),
            ("com.apple.facetime", ["FaceTime"]),
            ("com.apple.Fitness", ["Fitness", "健身"]),
            ("com.apple.stocks", ["Stocks", "股市"]),
            ("com.apple.Home", ["Home", "家庭"]),
            ("net.whatsapp.WhatsApp", ["WhatsApp"]),
        ]
        return Dictionary(apps.flatMap { id, names in names.map { ($0, id) } }, uniquingKeysWith: { first, _ in first })
    }()

    /// iOS's own record of the installed apps (LaunchServices' LSApplicationWorkspace and
    /// UIImage's `_applicationIconImageForBundleIdentifier:format:scale:`), reached by name at run time.
    private enum Installed {
        static func bundleID(named name: String) -> String? {
            guard let workspace = self.workspace,
                  let apps = workspace.perform(NSSelectorFromString("allInstalledApplications"))?.takeUnretainedValue() as? [NSObject]
            else { return nil }
            return apps.first { ($0.value(forKey: "localizedName") as? String) == name }?.value(forKey: "bundleIdentifier") as? String
        }

        static func icon(_ id: String) -> UIImage? {
            guard isInstalled(id) else { return nil }
            let selector = NSSelectorFromString("_applicationIconImageForBundleIdentifier:format:scale:")
            guard let method = class_getClassMethod(UIImage.self, selector) else { return nil }
            typealias Call = @convention(c) (AnyClass, Selector, NSString, Int32, CGFloat) -> UIImage?
            let call = unsafeBitCast(method_getImplementation(method), to: Call.self)
            // Format 2 is the Home Screen's 60-point icon.
            return call(UIImage.self, selector, id as NSString, 2, UIScreen.main.scale)
        }

        private static func isInstalled(_ id: String) -> Bool {
            let selector = NSSelectorFromString("applicationIsInstalled:")
            guard let workspace, workspace.responds(to: selector), let method = class_getInstanceMethod(type(of: workspace), selector) else { return false }
            typealias Call = @convention(c) (AnyObject, Selector, NSString) -> Bool
            return unsafeBitCast(method_getImplementation(method), to: Call.self)(workspace, selector, id as NSString)
        }

        private static var workspace: NSObject? {
            guard let type = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type else { return nil }
            return type.perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() as? NSObject
        }
    }
}

extension SavedSession {
    /// The app its tasks worked in most, the latest of them on a tie; nil for a chat with no app in it.
    /// The Home Screen and Poki itself are not apps a task is about.
    var mainApp: String? {
        var counts: [String: (count: Int, last: Int)] = [:]
        for (i, entry) in entries.enumerated() {
            guard case .plan = entry.kind, let app = entry.app, AppIcons.isTaskApp(app) else { continue }
            counts[app] = ((counts[app]?.count ?? 0) + 1, i)
        }
        return counts.max { ($0.value.count, $0.value.last) < ($1.value.count, $1.value.last) }?.key
    }
}

extension AppIcons {
    /// Not the Home Screen (as PokiCore names it), nor Poki, nor a bundle ID standing in for a name.
    nonisolated static func isTaskApp(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("Home screen") && name != "Poki" && name != "unknown"
    }
}
