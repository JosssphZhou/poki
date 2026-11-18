import SwiftUI
import UserNotifications

@MainActor
struct DailyTaskSettings: View {
    private let tasks = DailyTask.shared

    var body: some View {
        List {
            Section {
                NavigationLink {
                    DailyTaskEditor(plan: nil).settingsPage()
                } label: {
                    Label("Add Daily Task", systemImage: "plus")
                }
                .disabled(tasks.plans.count >= DailyTask.capacity)
                .accessibilityIdentifier("dailyTask.add")
            } footer: {
                if tasks.plans.count >= DailyTask.capacity {
                    Text("Delete a daily task before adding another.")
                }
            }

            Section {
                if tasks.plans.isEmpty {
                    Text("No daily tasks yet.").foregroundStyle(.secondary)
                }
                ForEach(tasks.plans.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { plan in
                    NavigationLink {
                        DailyTaskEditor(plan: plan).settingsPage()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: plan.name ?? plan.prompt)
                                .lineLimit(2)
                            Text(Self.time(for: plan), format: .dateTime.hour().minute())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } footer: {
                if !tasks.pending.isEmpty {
                    Text("Tasks are waiting. Turn on Poki and make sure it has a model and is idle.")
                } else {
                    Text("Poki runs at that time if it’s open and idle. Otherwise, tap the reminder to run the task.")
                }
            }
        }
        .navigationTitle(AppLocalization.text("Daily Tasks"))
        .navigationBarTitleDisplayMode(.inline)
    }

    fileprivate static func time(for plan: DailyTask.Plan?) -> Date {
        DailyTask.localCalendar.date(bySettingHour: plan?.hour ?? 9, minute: plan?.minute ?? 0,
                                     second: 0, of: .now) ?? .now
    }
}

@MainActor
private struct DailyTaskEditor: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var prompt: String
    @State private var time: Date
    @State private var saving = false
    @State private var notificationsOff = false
    @State private var saveFailed = false
    @State private var confirmingRemoval = false

    private let plan: DailyTask.Plan?

    init(plan: DailyTask.Plan?) {
        self.plan = plan
        _name = State(initialValue: plan?.name ?? "")
        _prompt = State(initialValue: plan?.prompt ?? "")
        _time = State(initialValue: DailyTaskSettings.time(for: plan))
    }

    var body: some View {
        Form {
            Section {
                TextField("What should Poki do?", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("dailyTask.prompt")
                DatePicker("Every day at", selection: $time, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("dailyTask.time")
            }
            .disabled(saving)

            Section {
                TextField("Reminder name (optional)", text: $name)
                    .accessibilityIdentifier("dailyTask.name")
            } footer: {
                Text("The name can appear on the Lock Screen. The instructions stay private.")
            }
            .disabled(saving)

            Section {
                Button("Save Schedule", action: save)
                    .disabled(saving || trimmedPrompt.isEmpty || notificationsOff)
                    .accessibilityIdentifier("dailyTask.save")
                if plan != nil {
                    Button("Delete Schedule", role: .destructive) { confirmingRemoval = true }
                        .disabled(saving)
                        .accessibilityIdentifier("dailyTask.cancel")
                }
            }

            if notificationsOff {
                Section {
                    Button("Open Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                } footer: {
                    Text("Allow notifications so Poki can remind you when it isn’t open.")
                }
            }
        }
        .navigationTitle(plan == nil ? AppLocalization.text("Add Daily Task") : AppLocalization.text("Edit Daily Task"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshPermission()
        }
        .alert("Couldn’t update the schedule", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again from Daily Tasks.")
        }
        .confirmationDialog("Delete this daily task?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Delete Schedule", role: .destructive, action: cancel)
        }
    }

    private var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        let parts = DailyTask.localCalendar.dateComponents([.hour, .minute], from: time)
        guard let hour = parts.hour, let minute = parts.minute, !trimmedPrompt.isEmpty else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = DailyTask.Plan(id: plan?.id ?? UUID(), name: title.isEmpty ? nil : title,
                                     prompt: trimmedPrompt, hour: hour, minute: minute)
        saving = true
        Task {
            defer { saving = false }
            do {
                if try await DailyTaskNotice.save(updated, replacing: plan?.noticeID) {
                    dismiss()
                } else {
                    notificationsOff = true
                }
            } catch {
                saveFailed = true
            }
        }
    }

    private func cancel() {
        guard let plan else { return }
        do {
            try DailyTaskNotice.cancel(plan.id)
            dismiss()
        }
        catch { saveFailed = true }
    }

    private func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus == .denied
    }
}
