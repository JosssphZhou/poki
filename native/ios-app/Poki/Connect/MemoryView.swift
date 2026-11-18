import PokiCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Memory: the routines agents saved on this iPhone (each repeats a task in one call) and
/// the owner's notes, both shared by Poki's own chat and every connected agent. Export and Import move
/// them between iPhones as one file; Poki Setup on the computer keeps the same file as a backup.
/// The maintainers' run log is on Settings › Advanced; the archived conversations have their own row on
/// the settings home.
struct MemoryView: View {
    var back: () -> Void
    @State private var routines: [Routine] = []
    @State private var notes: [MemoryNote] = []
    @State private var newNote = ""
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var confirmClear = false
    private let store = RoutineStore.shared
    @ObservedObject private var capture = HistoryCapture.shared
    @ObservedObject private var lock = HistoryLock.shared
    @State private var habit: LearnedMusicHabit?
    private var learning: Bool { capture.enabled && capture.learnHabits }

    var body: some View {
        Form {
            Section {
                if routines.isEmpty { Text("None yet").foregroundStyle(Color(.secondaryLabel)) }
                ForEach(routines, id: \.name) { r in
                    RoutineRow(routine: r)
                        .swipeActions { Button("Forget", role: .destructive) { _ = store.forget(r.name); reload() } }
                }
            } header: {
                SettingsHeader("Routines")
            } footer: {
                Text("An agent saves a routine after a task that worked; the next time it repeats the task in one step and stops where the screen differs. Swipe a routine to forget it.")
            }

            if learning {
                Section {
                    if lock.unlocked || lock.needsSetup {
                        LearnedHabitRows(habit: habit, forget: forgetHabit)
                    } else {
                        NavigationLink {
                            HistoryGate {
                                Form { LearnedHabitRows(habit: habit, forget: forgetHabit) }
                                    .navigationTitle(AppLocalization.text("Learned from Screen History"))
                                    .navigationBarTitleDisplayMode(.inline)
                            }
                        } label: {
                            SettingsRow(title: "Unlock to View", symbol: "lock")
                        }
                        .accessibilityIdentifier("memory.habits.unlock")
                    }
                } header: {
                    SettingsHeader("Learned from Screen History")
                } footer: {
                    Text("Inferred on this iPhone from which apps you used and when. It is not a note: it is not exported, backed up or shown to connected agents. Turning off Screen History or Learn Habits forgets it.")
                }
            }

            Section {
                ForEach(notes, id: \.id) { n in
                    LabeledContent(n.text, value: n.by)
                        .swipeActions { Button("Forget", role: .destructive) { _ = store.forgetNote(n.id); reload() } }
                }
                HStack {
                    TextField("e.g., Mom is “Mama” in Contacts", text: $newNote).submitLabel(.done).onSubmit(addNote)
                    Button("Add", action: addNote).disabled(!canAdd)
                }
            } header: {
                SettingsHeader("Notes")
            } footer: {
                Text("Every agent sees these notes before a task. They stay on this iPhone.")
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { SettingsRow(title: "Export Memory", symbol: "square.and.arrow.up") }
                }
                Button { importing = true } label: { SettingsRow(title: "Import Memory", symbol: "square.and.arrow.down") }
            } header: {
                SettingsHeader("Move or Back Up")
            } footer: {
                Text(message ?? AppLocalization.text(LocalizedStringResource("One file with every routine and note. Importing merges it in; the newer copy of a routine wins. Poki Setup on your computer can back it up and put it back.")))
            }

            Section {
                Button(role: .destructive) { confirmClear = true } label: {
                    Text("Clear Memory").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .accessibilityIdentifier("memory.clear")
            }
        }
        .navigationTitle(AppLocalization.text("Memory"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        // The model is asked when what it would read changed since it was last asked.
        .task { await ScreenHabits.judge(); reload() }
        .onChange(of: lock.unlocked) { _, _ in reload() }
        .onChange(of: capture.learnHabits) { _, _ in reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    message = try store.importData(data, by: "import")
                } catch {
                    message = AppLocalization.text(LocalizedStringResource("That file could not be imported: \(String(describing: error))"))
                }
                reload()
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Clear all routines and notes on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Memory", role: .destructive) { store.clearAll(); reload() }
        }
    }

    private var canAdd: Bool { !newNote.trimmingCharacters(in: .whitespaces).isEmpty }

    private func addNote() {
        guard canAdd else { return }
        _ = store.remember(newNote.trimmingCharacters(in: .whitespaces), by: "owner")
        newNote = ""
        reload()
    }

    /// Forget the learned habit: uses kept so far never count again (delete and stop learning it;
    /// learning starts over from new uses).
    private func forgetHabit() {
        ScreenHabits.forget()
        reload()
    }

    /// Reads the store again and writes the export to tmp for the share sheet.
    private func reload() {
        habit = ScreenHabits.musicApp()
        routines = store.routines.sorted { $0.updated > $1.updated }
        notes = store.notes
        let tmp = FileManager.default.temporaryDirectory
        let export = tmp.appendingPathComponent(RoutineStore.backupName)
        if let data = try? store.exportData(), (try? data.write(to: export, options: .atomic)) != nil { exportURL = export }
    }
}

/// A routine: its name, how many steps, how often it worked, and a flag when it stopped twice in a row.
private struct RoutineRow: View {
    var routine: Routine
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: routine.name).fontWeight(.semibold)
                Text(detail).font(.footnote).foregroundStyle(routine.stale ? Color.red : Color.secondary)
            }
            Spacer()
            if let ms = routine.lastMs {
                Text(verbatim: String(format: "%.1f s", Double(ms) / 1000)).font(.subheadline).foregroundStyle(Color(.secondaryLabel))
            }
        }
    }

    private var detail: String {
        let steps = AppLocalization.text(LocalizedStringResource("\(routine.steps.count) steps"))
        let runs = routine.runs == 0 ? AppLocalization.text(LocalizedStringResource("not run yet")) : AppLocalization.text(LocalizedStringResource("worked \(routine.ok) of \(routine.runs)"))
        let base = "\(steps) · \(runs) · \(routine.savedBy)"
        return routine.stale ? AppLocalization.text(LocalizedStringResource("Needs redoing: stopped twice in a row")) + " · " + base : base
    }
}

/// The habit Screen History taught Poki, marked as inferred, with what it rests on and Forget.
private struct LearnedHabitRows: View {
    var habit: LearnedMusicHabit?
    var forget: () -> Void

    var body: some View {
        if let habit {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text(LocalizedStringResource("Usual music app: \(appName(habit.bundleID))"))).fontWeight(.semibold)
                Text(detail(habit)).font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("memory.habits.music")
            .swipeActions { Button("Forget", role: .destructive, action: forget) }
            Button("Forget", role: .destructive, action: forget)
                .accessibilityIdentifier("memory.habits.forget")
        } else {
            Text("Nothing learned yet").foregroundStyle(Color(.secondaryLabel))
        }
    }

    private func appName(_ id: String) -> String {
        AppIconStore.name(id) ?? id
    }

    /// "Inferred automatically · <the model's evidence> · 11月18日": the day it was learned, as month and day
    /// in the app's language with the system region.
    private func detail(_ habit: LearnedMusicHabit) -> String {
        let day = DateFormatter()
        day.locale = AppLocalization.locale
        day.setLocalizedDateFormatFromTemplate("MMMd")
        let learned = day.string(from: habit.learnedAt)
        return AppLocalization.text(LocalizedStringResource("Inferred automatically · \(habit.evidence) · \(learned)"))
    }
}
