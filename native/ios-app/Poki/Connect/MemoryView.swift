import PokiCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Memory: the routines agents saved on this iPhone (each repeats a task in one call) and
/// the owner's notes, both shared by Poki's own chat and every connected agent. Export and Import move
/// them between iPhones as one file; Poki Setup on the computer keeps the same file as a backup.
/// The maintainers' log bundle sits under Advanced, at the bottom.
struct MemoryView: View {
    var back: () -> Void
    @State private var routines: [Routine] = []
    @State private var notes: [MemoryNote] = []
    @State private var newNote = ""
    @State private var importing = false
    @State private var message: String?
    @State private var exportURL: URL?
    @State private var bundleURL: URL?
    @State private var confirmClear = false
    private let store = RoutineStore.shared

    /// The routine or note the owner tapped, to forget it.
    @State private var forgetting: Forget?
    private enum Forget: Identifiable {
        case routine(String), note(MemoryNote)
        var id: String { switch self { case .routine(let name): "r" + name; case .note(let note): "n\(note.id)" } }
    }

    var body: some View {
        PaperScroll {
            PaperHeader(text: String(localized: "Routines"))
            PaperRows {
                if routines.isEmpty { PaperRow(String(localized: "None yet"), chevron: false).opacity(0.55) }
                ForEach(routines, id: \.name) { r in
                    Button { forgetting = .routine(r.name) } label: { RoutineRow(routine: r) }
                }
            }
            PaperFoot(text: String(localized: "An agent saves a routine after a task that worked. Next time it repeats the task in one step and stops where the screen differs."))
            PaperHeader(text: String(localized: "Notes"))
            PaperRows {
                ForEach(notes, id: \.id) { n in
                    Button { forgetting = .note(n) } label: {
                        PaperRow(n.text, detail: String(localized: "Added by \(n.by == "owner" ? String(localized: "you") : n.by)"), chevron: false)
                    }
                }
                HStack(spacing: 12) {
                    TextField("Add a note, e.g. Mom is “Mama” in Contacts", text: $newNote).font(.system(size: 17)).submitLabel(.done).onSubmit(addNote)
                    Button(action: addNote) {
                        Text("Add").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.page)
                            .padding(.horizontal, 14).frame(height: 34).background(Paper.ink, in: Capsule())
                    }
                    .disabled(!canAdd).opacity(canAdd ? 1 : 0.3)
                }
                .frame(minHeight: 54)
            }
            PaperFoot(text: String(localized: "Every agent sees these notes before a task. They stay on this iPhone."))
            PaperHeader(text: String(localized: "Move or back up"))
            PaperRows {
                if let exportURL { ShareLink(item: exportURL) { PaperRow(String(localized: "Export memory")) } }
                Button { importing = true } label: { PaperRow(String(localized: "Import memory")) }
            }
            PaperFoot(text: message ?? String(localized: "One file with every routine and note. Importing merges it in; the newer copy of a routine wins. Poki Setup on your computer can back it up and put it back."))
            PaperHeader(text: String(localized: "Advanced"))
            PaperRows {
                if let bundleURL {
                    ShareLink(item: bundleURL) {
                        PaperRow(String(localized: "Share the run log"), detail: String(localized: "For the Poki maintainers. No typed text"))
                    }
                }
                Button { confirmClear = true } label: { PaperRow(String(localized: "Clear memory"), chevron: false) }
            }
        }
        .confirmationDialog(forgetTitle, isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                switch forgetting {
                case .routine(let name): _ = store.forget(name)
                case .note(let note): _ = store.forgetNote(note.id)
                case nil: break
                }
                forgetting = nil
                reload()
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .paperPage()
        .onAppear(perform: reload)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    message = try store.importData(data, by: "import")
                } catch {
                    message = String(localized: "That file could not be imported: \(String(describing: error))")
                }
                reload()
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .confirmationDialog("Clear all routines and notes on this iPhone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear memory", role: .destructive) { store.clearAll(); reload() }
        }
    }

    private var forgetTitle: String {
        switch forgetting {
        case .routine(let name): String(localized: "Forget “\(name)”?")
        case .note(let note): String(localized: "Forget “\(note.text)”?")
        case nil: ""
        }
    }

    private var canAdd: Bool { !newNote.trimmingCharacters(in: .whitespaces).isEmpty }

    private func addNote() {
        guard canAdd else { return }
        _ = store.remember(newNote.trimmingCharacters(in: .whitespaces), by: "owner")
        newNote = ""
        reload()
    }

    /// Reads the store again and writes the two share files (the export and the log bundle) to tmp.
    private func reload() {
        routines = store.routines.sorted { $0.updated > $1.updated }
        notes = store.notes
        let tmp = FileManager.default.temporaryDirectory
        let export = tmp.appendingPathComponent(RoutineStore.backupName)
        if let data = try? store.exportData(), (try? data.write(to: export, options: .atomic)) != nil { exportURL = export }
        let bundle = tmp.appendingPathComponent("poki-agent-debug.json")
        if (try? store.debugBundle().write(to: bundle, options: .atomic)) != nil { bundleURL = bundle }
    }
}

/// A routine: its name, how many steps, how often it worked, and a flag when it stopped twice in a row.
private struct RoutineRow: View {
    var routine: Routine
    var body: some View {
        PaperRow(routine.name, detail: detail, value: routine.lastMs.map { String(format: "%.1f s", Double($0) / 1000) }, chevron: false)
    }

    private var detail: String {
        let steps = String(localized: "\(routine.steps.count) steps")
        let runs = routine.runs == 0 ? String(localized: "not run yet") : String(localized: "worked \(routine.ok) of \(routine.runs)")
        let base = "\(steps) · \(runs) · \(routine.savedBy)"
        return routine.stale ? String(localized: "Needs redoing: stopped twice in a row") + " · " + base : base
    }
}
