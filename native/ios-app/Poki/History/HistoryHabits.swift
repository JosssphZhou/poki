import Foundation
import PokiCore

/// Habits Poki learns from Screen History: today only the owner's usual music app.
///
/// Poki sums up the owner's own use of music apps from which app was in front and when
/// (`MusicUsageSummary`, no screen text). An app used three times in the past week can be a habit, and
/// the chat's model reads the summary of those apps with a description of what a habit is and decides
/// (`MusicHabitJudgment`). What it decides is kept here, with the
/// model's evidence, and the Memory page shows it as inferred. The model is asked again only when the
/// summary changes. The owner's own words come first: a music app named in the request, or a saved
/// note saying which app to use, leaves the learned app out.
@MainActor
enum ScreenHabits {
    private static let forgottenKey = "history.habitsForgottenAt"
    private static let learnedKey = "history.learnedMusicHabit"
    /// The summary the model last judged, so an unchanged one is not asked about again.
    private static let judgedKey = "history.habitJudged"

    /// Both switches are on: Screen History, and Learn Habits from Screen History.
    static var isOn: Bool {
        let capture = HistoryCapture.shared
        return capture.enabled && capture.learnHabits
    }

    /// Reads kept before this never count again (turning a switch off, deleting history, or Forget).
    static var forgottenAt: Date? {
        UserDefaults.standard.object(forKey: forgottenKey) as? Date
    }

    /// The owner's usual music app as the model decided it, or nil while learning is off or nothing is learned.
    static func musicApp() -> LearnedMusicHabit? {
        guard isOn, let data = UserDefaults.standard.data(forKey: learnedKey),
              let habit = try? JSONDecoder().decode(LearnedMusicHabit.self, from: data) else { return nil }
        if let forgottenAt, habit.learnedAt <= forgottenAt { return nil }
        return habit
    }

    /// Keeps what the model decided: a habit, or none.
    static func learn(_ habit: LearnedMusicHabit?) {
        if let habit, let data = try? JSONEncoder().encode(habit) {
            UserDefaults.standard.set(data, forKey: learnedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: learnedKey)
        }
    }

    /// Forgets what was learned. Uses kept so far are never counted again, after a restart too.
    static func forget(at now: Date = Date()) {
        let at = max(now, forgottenAt ?? now)
        UserDefaults.standard.set(at, forKey: forgottenKey)
        UserDefaults.standard.removeObject(forKey: learnedKey)
        UserDefaults.standard.removeObject(forKey: judgedKey)
    }

    /// The owner's uses of each music app, from Screen History.
    static func usages(now: Date = Date()) -> [MusicAppUsage] {
        let capture = HistoryCapture.shared
        let inputs = HistoryStore.shared.habitInputs(since: now.addingTimeInterval(-MusicUsageSummary.lookBack))
        return MusicUsageSummary.usages(observations: inputs.observations, agentSpans: inputs.spans,
                                        watermarkAt: forgottenAt, keepsApp: { capture.keeps($0) }, now: now)
    }

    /// Asks the chat's model whether the owner has a usual music app, when learning is on and the
    /// summary changed since it was last asked. What it says replaces what was learned before.
    static func judge(provider: ModelProvider = ModelKeys.selectedProvider, model: String = ModelKeys.selectedModel) async {
        guard isOn, let piModel = provider.piModel(model) else { return }
        let usages = MusicUsageSummary.candidates(usages())
        // No app used often enough this week: there is no habit, and nothing to ask.
        guard !usages.isEmpty else {
            learn(nil)
            UserDefaults.standard.removeObject(forKey: judgedKey)
            return
        }
        let summary = MusicUsageSummary.text(usages, name: { KnownApps.find($0)?.names.first ?? $0 })
        // The summary names days and counts, not exact times: a new use changes it, a re-read does not.
        guard UserDefaults.standard.string(forKey: judgedKey) != summary else { return }
        let forgottenBefore = forgottenAt
        let loop = PiLoop(provider: provider, model: piModel, tools: []) { _ in .init(text: "No tools.", jpeg: nil, isError: true) }
        let reply = Reply()
        let outcome = await loop.run(summary, instructions: MusicHabitJudgment.instructions(language: AppLocalization.language), maxTurns: 1) { text in
            if reply.text == nil { reply.text = text }
        }
        guard outcome == .done, let text = reply.text, let decided = MusicHabitJudgment.parse(text, offered: usages) else {
            AppLog.shared.add("history", "habit judgment unreadable")
            return
        }
        // Switched off, or forgotten, while the model was answering: what it said is not kept.
        guard isOn, forgottenAt == forgottenBefore else { return }
        learn(decided)
        UserDefaults.standard.set(summary, forKey: judgedKey)
    }

    // MARK: Agents' own launches

    /// A use of a music app that starts within this long after an agent opened or used it is the
    /// agent's, not the owner's.
    nonisolated static let agentShadow: TimeInterval = 30 * 60

    /// From the phone core: an agent launched, used or left `bundleID`. Only music apps are noted.
    nonisolated static func agentActivity(_ bundleID: String, _ phase: AgentAppActivityPhase, _ at: Date) {
        guard HistoryCapture.isEnabled, let app = MusicAppCatalog.canonicalBundleID(for: bundleID) else { return }
        HistoryStore.shared.markAgent(app: app, from: at.addingTimeInterval(-5), to: at.addingTimeInterval(agentShadow))
    }

    // MARK: The chat

    /// Words that make a request about music, in the languages Poki speaks.
    private static let musicWords = ["歌", "音乐", "音樂", "曲", "专辑", "專輯", "听", "聽", "music", "song", "track", "album", "playlist", "tune"]

    static func isAboutMusic(_ task: String) -> Bool {
        let lower = task.lowercased()
        return musicWords.contains { lower.contains($0) }
    }

    /// Names that mean one music app. Plain "Music" and 音乐 are left out: they ask for music, not for
    /// Apple's app.
    private static let musicAppNames: [String] = {
        let generic: Set<String> = ["music", "音乐", "音樂"]
        let known = MusicAppCatalog.allCanonicalIDs.flatMap { KnownApps.find($0)?.names ?? [] }
        let more = ["Apple Music", "Apple 音乐", "Apple 音樂", "网易云", "網易雲", "QQ Music", "酷狗", "Kugou", "酷我", "Kuwo",
                    "汽水音乐", "汽水音樂", "Spotify", "YouTube Music", "Apple Music Classical",
                    "苹果音乐", "蘋果音樂", "咪咕音乐", "咪咕音樂", "咪咕", "Migu"]
        return Array(Set((known + more).map { $0.lowercased() }).subtracting(generic))
    }()

    /// The owner's saved notes, as the app's own copy of PokiCore holds them.
    static var memory: RoutineStore { RoutineStore.shared }

    /// Whether `text` names a music app.
    static func namesMusicApp(_ text: String) -> Bool {
        let lower = text.lowercased()
        return musicAppNames.contains { lower.contains($0) }
    }

    /// Whether a saved note says which app plays the owner's music: it names a music app, or it is
    /// about music and says which app to use ("以后都用某某放歌", "always use X for songs"), even an
    /// app Poki has no name for.
    static func choosesMusicApp(_ note: String) -> Bool {
        let lower = note.lowercased()
        return namesMusicApp(note) || (isAboutMusic(note) && ["用", "app", "use"].contains { lower.contains($0) })
    }

    /// Whether the learned app has a say in `task`: a request about music that names no app, with no
    /// saved note saying which app to use.
    static func applies(to task: String) -> Bool {
        isAboutMusic(task) && !namesMusicApp(task) && !memory.notes.contains(where: { choosesMusicApp($0.text) })
    }

    /// Asks the model about the habit when `task` could use it, then gives the line its instructions carry.
    static func prepareInstructions(for task: String) async -> String? {
        guard isOn, applies(to: task) else { return nil }
        await judge()
        return instructions(for: task)
    }

    /// The line a music request's instructions carry, or nil. The owner's own choice comes first: a
    /// music app named in the request, then a saved note naming one. Either way the learned app is
    /// left out, so it cannot win over them, and a "from now on" request can be saved.
    static func instructions(for task: String) -> String? {
        guard applies(to: task), let habit = musicApp() else { return nil }
        let id = habit.bundleID
        let names = KnownApps.find(id).map { $0.names.joined(separator: " / ") } ?? id
        let evidence = habit.evidence.isEmpty ? "" : " (\(habit.evidence))"
        return """
        The owner's usual music app, learned on this iPhone from Screen History because the owner turned on Learn Habits: \(names), bundle id \(id)\(evidence). \
        When the owner asks to play music, a song, a singer or a playlist and names no app, play it in this app: start with do {launch: "\(id)"}. \
        A music app the owner names in this message comes first, and that choice is for this time only. \
        If this app is not installed, needs sign-in or cannot play, say so and ask which app to use; do not switch on your own. \
        This is inferred, not something the owner said: do not save it as a note, or a routine for this task. When the owner says which music app to use from now on, save their words with routines remember.
        """
    }
}

@MainActor
private final class Reply { var text: String? }
