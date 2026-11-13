import PokiCore
import SwiftUI

// The pages behind Settings on the front (Poki/Front): Agents, the agents that drive this iPhone (their MCP
// addresses and the relay) and the Activity Log; and Connection › Advanced, the preferences and debugging
// tools.

/// Agents › a page.
enum AgentsRoute: Hashable { case accounts, voice, activityLog }

/// Settings › Agents: the outside agents that may use this iPhone. Poki's own model, memory and approvals
/// have their own rows in Settings.
struct AgentsList: View {
    /// The line under MCP Relay: the address to set, Poki being off, or the relay's live state.
    private var relayLine: String {
        if model.relayAddress == nil { return String(localized: "Set an address first") }
        if !model.relayEnabled { return String(localized: "Off: agents can’t reach this iPhone") }
        if !model.sessionOn { return String(localized: "Waiting for Poki: turn Poki on and agents can connect") }
        return Health.relay(model).word
    }

    @Environment(AppModel.self) private var model
    var push: (SettingsRoute) -> Void

    var body: some View {
        PaperScroll {
            Text("Other agents, such as Claude Code or Codex on your Mac, can use this iPhone through Poki.")
                .font(.system(size: 15)).foregroundStyle(Paper.ink2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
            PaperHeader(text: String(localized: "MCP relay"))
            PaperRows {
                // On or off; it can't be turned on before an address is set, and is on once one is.
                Toggle(isOn: Binding(get: { model.relayEnabled && model.relayAddress != nil }, set: { model.setRelayEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MCP relay").font(Paper.row).foregroundStyle(Paper.ink)
                        Text(relayLine).font(Paper.note).foregroundStyle(Paper.ink2)
                    }
                }
                .frame(minHeight: 60)
                // Poki stopped: the switch keeps the owner's choice but is greyed, since nothing
                // connects until Poki is on; the line under it says so.
                .disabled(model.relayAddress == nil || !model.sessionOn)
                NavigationLink(value: SettingsRoute.relay) {
                    PaperRow(String(localized: "Address"), value: model.relayAddress.map { $0.origin.host() ?? $0.origin.absoluteString } ?? String(localized: "Not set"))
                }
            }
            PaperFoot(text: String(localized: "The relay forwards agents’ requests to this iPhone while Poki is open or in the background. It stores nothing."))
            PaperHeader(text: String(localized: "Agents"))
            PaperRows {
                ForEach(model.identity.secrets) { secret in
                    let last = SessionStore.shared.sessions(for: secret, among: model.identity.secrets).first
                    NavigationLink(value: SettingsRoute.connector(secret)) {
                        PaperRow(title: secret.name, detail: nil, value: last.map { ChatTime.row($0.updated) } ?? String(localized: "Not used yet")) {
                            // The agent that connected through it (or used it last).
                            if let client = secret.agent ?? last?.client { AgentBadge(name: client, size: 26) }
                        }
                    }
                    .contextMenu { Button("Revoke", systemImage: "xmark.circle", role: .destructive) { model.revoke(secret) } }
                }
                // A new connector is "Connector N" until an agent connects through it (or you name
                // it on its page).
                Button(action: add) { PaperRow(String(localized: "Add an agent")) }
                    .disabled(model.relayAddress == nil)
                    .opacity(model.relayAddress == nil ? 0.4 : 1)
            }
            PaperFoot(text: model.relayAddress == nil ? String(localized: "Set your relay address first. Each agent gets its own MCP address on it.")
                                                      : String(localized: "Each agent gets its own MCP address. Press and hold an agent to revoke it."))
            PaperRows {
                NavigationLink(value: AgentsRoute.activityLog) {
                    PaperRow(String(localized: "Activity"), detail: String(localized: "Every action an agent took here"))
                }
            }
            .padding(.top, 24)
            PaperFoot(text: String(localized: "It can’t be deleted."))
        }
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func add() {
        guard model.relayAddress != nil else { return }
        push(.connector(model.addConnector(name: "")))
    }
}

enum SetupRoute: Hashable { case advanced }

/// Setup › Advanced: preferences and debugging tools.
struct AdvancedView: View {
    @Environment(AppModel.self) private var model
    var push: (SettingsRoute) -> Void

    var body: some View {
        @Bindable var model = model
        List {
            if model.automationPath == .runner {
                PaperSection {
                    LabeledContent("Runner", value: Health.runner(model).word)
                    Picker("Stop when idle for", selection: $model.idleStopSeconds) {
                        ForEach(SettingsHome.idleChoices, id: \.0) { Text($0.1).tag($0.0) }
                    }
                } header: { Text("Poki Runner") }
            }
            PaperSection {
                Button("Notifications") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                NavigationLink("Diagnostics", value: SettingsRoute.diagnostics)
                NavigationLink("Log", value: SettingsRoute.log)
                NavigationLink("Live Activity preview", value: SettingsRoute.activityPreview)
            } footer: {
                Text("Diagnostics: connection checks, the background hold, this iPhone’s addresses and the in-process automation switch.")
            }
        }
        .paperList()
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}
