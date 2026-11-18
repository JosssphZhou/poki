import Foundation

/// Habits Poki learns from Screen History. Today there is one: the music app the owner uses most.
///
/// This file sums up the owner's own use of music apps (which app was in front, and when; no screen
/// text or title). An app used `minUses` times in the past `lookBack` can be a habit; the model reads
/// the summary of those apps with a description of what a habit is and decides (`MusicHabitJudgment`).

// MARK: Types

/// What the model decided: the owner's usual music app and, in its own words, what it rests on.
public struct LearnedMusicHabit: Codable, Equatable, Sendable {
    public var bundleID: String
    /// The model's evidence, in the owner's language ("过去一周用了 4 次，多在晚上").
    public var evidence: String
    public var learnedAt: Date

    public init(bundleID: String, evidence: String, learnedAt: Date) {
        self.bundleID = bundleID
        self.evidence = evidence
        self.learnedAt = learnedAt
    }
}

public struct ScreenHabitRawObservation: Equatable, Sendable {
    public var id: Int64
    public var at: Date
    public var bundleID: String
    public var isAgentInitiated: Bool

    public init(id: Int64 = 0, at: Date, bundleID: String, isAgentInitiated: Bool = false) {
        self.id = id
        self.at = at
        self.bundleID = bundleID
        self.isAgentInitiated = isAgentInitiated
    }
}

/// A time an agent had an app open: reads of that app then are the agent's, not the owner's.
public struct AgentAppSpan: Codable, Equatable, Sendable {
    public var bundleID: String
    public var startAt: Date
    public var endAt: Date

    public init(bundleID: String, startAt: Date, endAt: Date) {
        self.bundleID = bundleID
        self.startAt = startAt
        self.endAt = endAt
    }
}

// MARK: Music App Catalog

public enum MusicAppCatalog {
    public static let allCanonicalIDs: [String] = [
        "com.apple.Music",
        "com.netease.cloudmusic",
        "com.tencent.QQMusic",
        "com.spotify.client",
        "com.kugou.kugou1002",
        "com.yeelion.kwplayer",
        "com.luna.music",
        "com.google.ios.youtubemusic",
        "com.apple.Classical",
        "cmccwm.mobilemusic",
    ]

    private static let aliasToCanonical: [String: String] = {
        var map: [String: String] = [:]
        for id in allCanonicalIDs {
            map[id.lowercased()] = id
        }
        map["com.netease.cloudmusic.ipad"] = "com.netease.cloudmusic"
        map["com.tencent.qqmusichd"] = "com.tencent.QQMusic"
        map["com.kugou.kugou"] = "com.kugou.kugou1002"
        map["cn.kuwo.player"] = "com.yeelion.kwplayer"
        return map
    }()

    public static func isValidBundleID(_ rawBundleID: String) -> Bool {
        rawBundleID.range(of: #"\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z"#, options: .regularExpression) != nil
    }

    public static func canonicalBundleID(for rawBundleID: String) -> String? {
        guard isValidBundleID(rawBundleID) else { return nil }
        return aliasToCanonical[rawBundleID.lowercased()]
    }

    public static func isMusicApp(_ rawBundleID: String) -> Bool {
        canonicalBundleID(for: rawBundleID) != nil
    }
}

// MARK: Summary

/// The owner's own uses of one music app.
public struct MusicAppUsage: Equatable, Sendable {
    public var bundleID: String
    /// When each use started, oldest first.
    public var uses: [Date]
}

public enum MusicUsageSummary {
    /// Reads of the same app this close together are one use: a page read a hundred times is still
    /// one time the owner opened the app.
    public static let sameUseGap: TimeInterval = 30 * 60
    /// How far back the summary looks: one week.
    public static let lookBack: TimeInterval = 7 * 86_400
    /// The fewest uses in `lookBack` that can make an app a habit. Fewer is never offered to the model.
    public static let minUses = 3

    /// The apps that can be a habit: those used at least `minUses` times.
    public static func candidates(_ usages: [MusicAppUsage]) -> [MusicAppUsage] {
        usages.filter { $0.uses.count >= minUses }
    }

    /// The owner's uses of each music app since `lookBack` (and after `watermarkAt`), from which app
    /// was in front and when. Uses while an agent had the app open are left out, and so are apps the
    /// owner leaves out of Screen History.
    public static func usages(
        observations: [ScreenHabitRawObservation],
        agentSpans: [AgentAppSpan] = [],
        watermarkAt: Date? = nil,
        keepsApp: (String) -> Bool = { _ in true },
        now: Date = Date()
    ) -> [MusicAppUsage] {
        let floor = max(now.addingTimeInterval(-lookBack), watermarkAt ?? .distantPast)
        let spans = agentSpans.compactMap { span -> (String, Date, Date)? in
            guard let app = MusicAppCatalog.canonicalBundleID(for: span.bundleID) else { return nil }
            return (app, span.startAt, max(span.startAt, span.endAt))
        }
        var reads: [String: [Date]] = [:]
        for item in observations {
            guard item.at > floor, item.at <= now, !item.isAgentInitiated,
                  let app = MusicAppCatalog.canonicalBundleID(for: item.bundleID),
                  keepsApp(item.bundleID), keepsApp(app),
                  !spans.contains(where: { $0.0 == app && item.at >= $0.1 && item.at <= $0.2 }) else { continue }
            reads[app, default: []].append(item.at)
        }
        return reads.map { app, times in
            var uses: [Date] = []
            var last: Date?
            for at in times.sorted() {
                if let last, at.timeIntervalSince(last) <= sameUseGap {} else { uses.append(at) }
                last = at
            }
            return MusicAppUsage(bundleID: app, uses: uses)
        }.sorted { $0.uses.count == $1.uses.count ? $0.bundleID < $1.bundleID : $0.uses.count > $1.uses.count }
    }

    /// The summary as the model reads it: for each app, how many uses, on which days, at what times
    /// of day, and the last one.
    public static func text(_ usages: [MusicAppUsage], name: (String) -> String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let day = DateFormatter()
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd (EEE)"
        var lines = ["Today is \(day.string(from: now)). The owner's own uses of music apps on this iPhone in the last \(Int(lookBack / 86_400)) days (Poki's own launches are left out; reads within \(Int(sameUseGap / 60)) minutes count as one use):"]
        for usage in usages {
            let days = Dictionary(grouping: usage.uses) { calendar.startOfDay(for: $0) }
            let dayList = days.keys.sorted().map { "\(day.string(from: $0)) ×\(days[$0]?.count ?? 0)" }.joined(separator: ", ")
            var parts: [String: Int] = [:]
            for use in usage.uses { parts[partOfDay(calendar.component(.hour, from: use)), default: 0] += 1 }
            let times = ["morning", "afternoon", "evening", "night"].compactMap { part in parts[part].map { "\(part) \($0)" } }.joined(separator: ", ")
            lines.append("- \(name(usage.bundleID)) (bundle id \(usage.bundleID)): \(usage.uses.count) uses on \(days.count) days: \(dayList). Times of day: \(times).")
        }
        if usages.isEmpty { lines.append("- none") }
        return lines.joined(separator: "\n")
    }

    static func partOfDay(_ hour: Int) -> String {
        switch hour {
        case 5..<12: return "morning"
        case 12..<18: return "afternoon"
        case 18..<23: return "evening"
        default: return "night"
        }
    }
}

// MARK: The model's judgment

public enum MusicHabitJudgment {
    /// What the model is told: what counts as a habit, what to look at, how to write the evidence.
    public static func instructions(language: String) -> String {
        """
        You decide whether the owner has a usual music app: one they choose again and again, so that \
        when they ask Poki to play music without naming an app, opening that app is what they would expect.
        You get a summary of the owner's own use of music apps on this iPhone: how many times they used \
        each app, on which days and at what times. Look at how often and how regularly they come back to \
        an app, whether it is recent, and how it compares with the other music apps, and decide from the \
        whole picture. When two apps are used about as much, or the use looks like a one-off, there is no habit.
        Reply with JSON only, no other text: {"habit": true, "bundle_id": "<the app's bundle id>", \
        "evidence": "<one short sentence for the owner, in the language with code \(language), saying \
        what you saw, such as how many times, on how many days and at what time of day>"} \
        or {"habit": false}.
        """
    }

    /// The model's reply read as a habit, `.some(nil)` for "no habit", or nil when it cannot be read.
    /// Only a bundle id from the summary is taken.
    public static func parse(_ reply: String, offered: [MusicAppUsage], now: Date = Date()) -> LearnedMusicHabit?? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"),
              let object = try? JSONSerialization.jsonObject(with: Data(reply[start...end].utf8)) as? [String: Any],
              let habit = object["habit"] as? Bool else { return nil }
        guard habit else { return .some(nil) }
        guard let raw = object["bundle_id"] as? String, let app = MusicAppCatalog.canonicalBundleID(for: raw),
              offered.contains(where: { $0.bundleID == app }) else { return nil }
        let evidence = (object["evidence"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .some(LearnedMusicHabit(bundleID: app, evidence: String(evidence.prefix(200)), learnedAt: now))
    }
}
