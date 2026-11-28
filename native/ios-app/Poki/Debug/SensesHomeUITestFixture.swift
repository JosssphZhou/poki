#if DEBUG
import SwiftUI

@MainActor
enum SensesHomeUITestFixture {
    static var active: Bool { ProcessInfo.processInfo.arguments.contains("-pokiUITestSensesHome") }
    static var pending: CheckedContinuation<[HomeShortcut], Never>?
    static var requests = 0
    static func suggestions() -> SensesSuggestions {
        SensesSuggestions(enabled: { true }, produce: {
            requests += 1
            if requests == 1 { return await withCheckedContinuation { pending = $0 } }
            // Keep the independent test Home deterministic without unrelated example pills.
            for existing in HomeShortcutStore.shared.shortcuts { HomeShortcutStore.shared.forget(existing) }
            return [pill("Fresh suggestion")]
        })
    }
    static func pill(_ text: String) -> HomeShortcut {
        HomeShortcut(key: text, app: "com.apple.mobilenotes", appName: "Notes", text: text, prompt: text)
    }
}

struct SensesHomeUITestControls: View {
    @State private var clearing = false
    @State private var released = false
    var body: some View {
        HStack {
            Button("Clear seeded history") {
                HistoryStore.shared.add(at: Date(), app: "com.apple.mobilenotes", title: "Old", text: "Old evidence")
                clearing = true
            }.accessibilityIdentifier("fixture.history.clear")
            Button(released ? "Old result released" : "Release old result") {
                SensesHomeUITestFixture.pending?.resume(returning: [SensesHomeUITestFixture.pill("Old suggestion")])
                SensesHomeUITestFixture.pending = nil
                released = true
            }.accessibilityIdentifier("fixture.history.release")
        }
        .font(.caption)
        .sheet(isPresented: $clearing) {
            Button("Clear and return Home") {
                Task {
                    await HistoryCapture.shared.clearEverything()
                    clearing = false
                    await SensesSuggestions.shared.refresh()
                }
            }.accessibilityIdentifier("fixture.history.confirm")
        }
    }
}
#endif
