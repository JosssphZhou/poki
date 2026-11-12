// The model page combines two files from lhuanyu/OllamaMessage (commit c857a02), Copyright (c) 2023
// Huanyu Luo, MIT License; see THIRD_PARTY_NOTICES.md:
// - OllamaMessage/Class/View/MessageList/DialogueSettingsView.swift: the "Model" row with its label and a hidden-label
//   Picker on the right;
// - OllamaMessage/Class/View/DialogueList/OllamaModelSelectionView.swift: one row per provider with its 30 pt icon, the
//   whole row tappable, and the footer under the list.
// Changed: the ESP-171 board "M Model" (the grouped rows, the provider tiles, "Add Key"), keys entered
// into the keychain instead of a server's model list, and the agents on a computer below.
import SwiftUI

/// Accounts, as the Mail app lists mail accounts: every model account on this iPhone whatever its
/// provider, each with what it is used for (the text chat, live voice) switched on or off inside it.
/// What an account can power is worked out from its type: any wired provider can run the text chat;
/// live voice needs OpenAI's Realtime API, so only an OpenAI API key can run it.
struct ModelSettingsView: View {
    @AppStorage(ChatModelSwitcherPlacement.preferenceKey) private var switcherPlacement = ChatModelSwitcherPlacement.more
    @State private var adding = false
    @State private var changing = false
    @State private var problem: String?
    @State private var version = ModelKeys.saved

    var body: some View {
        let profiles = ModelProfiles.shared.all
        let registrations = ChatGPTProfiles.shared.all
        let selection = AskPoki.chat?.selection ?? ModelKeys.defaultSelection
        List {
            // ESP-469 board "02 模型": what runs now, on a card on top, with the way to change the chat's model.
            Section {
                InUseCard(selection: selection, hasAccounts: !profiles.isEmpty || !registrations.isEmpty, add: { adding = true }, change: { changing = true })
            } header: {
                Text("In Use").textCase(nil)
            } footer: {
                Text("Open an account to choose what it is used for. Dictation in the message field needs no account.")
            }

            Section {
                ForEach(ChatModelSwitcherPlacement.allCases) { placement in
                    let selected = switcherPlacement == placement
                    Button { switcherPlacement = placement } label: {
                        HStack {
                            Text(placement.title)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark").foregroundStyle(Tint.blue)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("model.switcher.\(placement.rawValue)")
                }
            } header: {
                Text("Chat Model Switcher")
            } footer: {
                Text("Choose where to switch models in the chat.")
            }
            ForEach(ModelProvider.allCases.filter { provider in provider == .chatgpt ? !registrations.isEmpty : profiles.contains { $0.provider == provider } }) { provider in
                Section(provider.name) {
                    if provider == .chatgpt {
                        ForEach(registrations) { profile in
                            NavigationLink { ChatGPTProfileDetail(profileID: profile.id) } label: {
                                VStack(alignment: .leading) {
                                    HStack(spacing: 12) { ProviderTile(provider: provider); Text(profile.title) }
                                    Text(profile.isSignedIn ? String(localized: "Signed In") : String(localized: "Sign In Again")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityLabel("\(provider.name), \(profile.title)")
                            .accessibilityIdentifier("model.profile.\(profile.id.uuidString)")
                        }
                    } else {
                        ForEach(profiles.filter { $0.provider == provider }) { profile in
                            NavigationLink { ModelProfileDetail(profileID: profile.id) } label: {
                                HStack(spacing: 12) { ProviderTile(provider: provider); Text(profile.title) }
                            }
                            .accessibilityLabel("\(provider.name), \(profile.title)")
                            .accessibilityIdentifier("model.profile.\(profile.id.uuidString)")
                        }
                    }
                }
            }

            if !profiles.isEmpty || !registrations.isEmpty {
                Section { Button("Add Account", systemImage: "plus") { adding = true }.accessibilityIdentifier("model.addAccount") }
            }
            if let problem { Text(problem).foregroundStyle(.red) }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $changing) { ProfileModelSelection() }
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $adding) { AddAccount() }
        .task {
            do { _ = try ModelProfiles.shared.load() } catch { problem = error.localizedDescription }
            for profile in ChatGPTProfiles.shared.all where profile.isSignedIn && profile.models == nil {
                _ = await ChatGPTProfiles.shared.reloadModels(profile.id)
            }
        }
    }
}

/// What runs now: the chat's model and its account, what the text chat, live voice and dictation each
/// use (main's In Use rows), and Change Chat Model (or Add Account while there is none).
private struct InUseCard: View {
    var selection: ModelSelection
    var hasAccounts: Bool
    var add: () -> Void
    var change: () -> Void

    var body: some View {
        let has = selection.route != nil
        let provider = selection.provider
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if has { ProviderTile(provider: provider, size: 44) } else { SettingsIcon(symbol: "sparkles", warns: true, size: 44) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: has ? (selection.route?.model.name ?? selection.modelID) : String(localized: hasAccounts ? "Unavailable" : "No Account"))
                        .font(.title3.weight(.semibold)).foregroundStyle(Color(.label))
                    if hasAccounts { Text(verbatim: "\(provider.name) · \(selection.profileID.flatMap { ModelProfiles.shared.profile($0)?.title ?? ChatGPTProfiles.shared.profile($0)?.title } ?? String(localized: "Unavailable"))").font(.subheadline).foregroundStyle(Color(.secondaryLabel)) }
                }
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { uses(has: has, provider: provider) }
                VStack(alignment: .leading, spacing: 6) { uses(has: has, provider: provider) }
            }
            SettingsPill(title: hasAccounts ? "Change Chat Model" : "Add Account", symbol: hasAccounts ? "arrow.triangle.2.circlepath" : "plus",
                         prominent: true, action: hasAccounts ? change : add)
                .accessibilityIdentifier("model.inUse.action")
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder private func uses(has: Bool, provider: ModelProvider) -> some View {
        chip("Text Chat", has ? provider.name : String(localized: "No Account"))
        chip("Live Voice", VoiceDirect.apiKey != nil ? String(localized: "OpenAI") : String(localized: "No Account"))
        chip("Dictation", String(localized: "On This iPhone"))
    }

    private func chip(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(Color(.secondaryLabel))
            Text(verbatim: value).font(.footnote.weight(.semibold)).foregroundStyle(Color(.label))
        }
        .lineLimit(1)
        // A chip never gets less than its words need: the row gives a long value (Dictation's
        // "On This iPhone") its width from the shorter ones, and stacks the chips when they can't all fit.
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Tint.blueSoft.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Used by setup and account summaries. An API key represents a connection, not a verified identity.
enum ModelAccounts {
    @MainActor static func isSetUp(_ provider: ModelProvider) -> Bool {
        provider == .chatgpt ? !ChatGPTProfiles.shared.all.isEmpty : ModelProfiles.shared.all.contains { $0.provider == provider }
    }
    static func canChat(_ provider: ModelProvider) -> Bool { provider.wired }
    static func canTalkLive(_ provider: ModelProvider) -> Bool { provider == .openai }
    static func method(_ provider: ModelProvider) -> String {
        provider == .chatgpt ? String(localized: "Sign in with ChatGPT") : provider == .custom ? String(localized: "OpenAI-compatible address") : String(localized: "API key")
    }
}

private struct ModelProfileDetail: View {
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID
    @State private var version = ModelKeys.saved
    @State private var editing = false
    @State private var loading = false
    @State private var problem: String?
    private var profile: ModelProfile? { ModelProfiles.shared.profile(profileID) }

    var body: some View {
        Form {
            if let p = profile {
                Section {
                    LabeledContent("Provider", value: p.provider.name)
                    if let endpoint = p.endpoint { LabeledContent("Address", value: endpoint) }
                    Button("Edit Profile") { editing = true }
                } footer: { Text("API keys are stored securely. The profile name is your label for this connection.") }
                Section("Models to Choose From") {
                    ForEach(ModelProfiles.shared.models(profileID)) { model in
                        Toggle(model.name, isOn: Binding(get: { profile?.enabled.contains(model.id) == true }, set: { enabled in
                            perform { try ModelProfiles.shared.setModel(model.id, enabled: enabled, profileID: profileID) }
                        }))
                    }
                    Button(loading ? "Reading the Model List…" : "Refresh Model List") {
                        loading = true
                        Task {
                            do { try await ModelProfiles.shared.refresh(profileID); problem = nil }
                            catch { problem = error.localizedDescription }
                            loading = false
                        }
                    }.disabled(loading)
                }
                if p.provider == .openai {
                    Section {
                        Button("Use This Profile for Live Voice") { UserDefaults.standard.set(profileID.uuidString, forKey: "voice.profile"); VoiceDirect.enabled = true }
                        NavigationLink("Live Voice") { LiveVoiceFeature() }
                    }
                }
                Section {
                    Button("Delete Profile", role: .destructive) { perform { try ModelProfiles.shared.remove(profileID); dismiss() } }
                }
            } else { Text("This account profile is unavailable. Choose another in Accounts.") }
            if let problem { Text(problem).foregroundStyle(.red) }
        }
        .navigationTitle(profile?.title ?? String(localized: "Unavailable"))
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $editing) { if let p = profile { ProfileEditor(provider: p.provider, profileID: profileID) } }
    }
    private func perform(_ action: () throws -> Void) { do { try action(); problem = nil } catch { problem = error.localizedDescription } }
}

private struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    let provider: ModelProvider
    var profileID: UUID?
    var onSaved: (() -> Void)?
    @State private var label = ""
    @State private var key = ""
    @State private var address = ""
    @State private var model = ""
    @State private var removeKey = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Profile Name", text: $label).accessibilityIdentifier("profile.name")
                SecureField(profileID == nil ? provider.keyPrompt : String(localized: "Replace Key"), text: $key)
                    .accessibilityIdentifier("profile.key").textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(removeKey)
                if provider == .custom, let profileID, ModelProfiles.shared.profile(profileID)?.key != nil {
                    Toggle("Remove Key", isOn: $removeKey)
                }
                if provider == .custom {
                    TextField("Address", text: $address).accessibilityIdentifier("profile.address").keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Model", text: $model).accessibilityIdentifier("profile.model").textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .navigationTitle(provider.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let id = profileID, let p = ModelProfiles.shared.profile(id) {
                    label = p.label; address = p.endpoint ?? ""; model = p.customModel ?? ""
                }
            }
        }
    }
    private func save() {
        do {
            let previous = profileID.flatMap(ModelProfiles.shared.profile)
            let secret = removeKey ? nil : (key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? previous?.key : key)
            let p = try ModelProfiles.shared.save(profileID, provider: provider, label: label, key: secret, endpoint: address, model: model)
            if profileID == nil { ModelProfiles.shared.choose(p.id) }
            key = ""; dismiss(); onSaved?()
        } catch { problem = error.localizedDescription }
    }
}

private struct ChatGPTProfileDetail: View {
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID
    @State private var signingIn = false
    @State private var label = ""
    @State private var version = ModelKeys.saved
    @State private var problem: String?
    private var profile: ChatGPTProfile? { ChatGPTProfiles.shared.profile(profileID) }
    var body: some View {
        Form {
            if let p = profile {
                TextField("Profile Name", text: $label).accessibilityIdentifier("profile.name")
                Button("Save Name") { do { try ChatGPTProfiles.shared.rename(profileID, to: label) } catch { problem = error.localizedDescription } }
                Button("Sign In Again") { signingIn = true }
                Button("Refresh Model List") { Task { if await ChatGPTProfiles.shared.reloadModels(profileID) == false { problem = String(localized: "The model list could not be refreshed.") } } }
                ForEach(p.models ?? []) { Text($0.name) }
                Button("Sign Out", role: .destructive) { signOut(remove: false) }
                Button("Remove Account", role: .destructive) { signOut(remove: true) }
            } else { Text("This account profile is unavailable. Choose another in Accounts.") }
            if let problem { Text(problem).foregroundStyle(.red) }
        }
        .navigationTitle(profile?.title ?? String(localized: "Unavailable"))
        .onAppear { label = profile?.label ?? "" }
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $signingIn) { ChatGPTSignIn(profileID: profileID) }
    }
    private func signOut(remove: Bool) {
        Task {
            do {
                let revoked = try await ChatGPTProfiles.shared.signOut(profileID, remove: remove)
                if !revoked { problem = String(localized: "Signed out locally. Server revocation could not be confirmed.") }
                else if remove { dismiss() }
            } catch { problem = error.localizedDescription }
        }
    }
}
private struct LiveVoiceFeature: View {
    @State private var version = ModelKeys.saved

    var body: some View {
        Form {
            Section {
                Toggle("Use for Live Voice", isOn: Binding(get: { VoiceDirect.enabled }, set: { VoiceDirect.enabled = $0 }))
                if VoiceDirect.enabled {
                    Picker("Voice Model", selection: Binding(get: { ModelCatalog.voiceModel }, set: { ModelCatalog.voiceModel = $0 })) {
                        ForEach(ModelCatalog.voiceAvailable) { Text($0.name).tag($0.id) }
                    }
                }
            } footer: {
                Text("Live voice is a spoken conversation with OpenAI’s Realtime model: it listens, taps and types, and answers out loud.")
            }
            Section {
                ForEach(ModelCatalog.voiceAll) { choice in
                    Toggle(choice.name, isOn: Binding(get: { ModelCatalog.voiceEnabled.contains(choice.id) }, set: { ModelCatalog.setVoice(choice.id, on: $0) }))
                }
            } header: {
                Text("Voice Models to Choose From")
            } footer: {
                Text("Refresh the model list under Text Chat to add the other Realtime models your key can use.")
            }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .navigationTitle("Live Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
    }
}

/// Settings and composer both select the same profile route, including the open conversation.
private struct ProfileModelSelection: View {
    @State private var version = ModelKeys.saved
    var body: some View {
        let connections = ModelProfiles.shared.all
        let registrations = ChatGPTProfiles.shared.all
        let current = AskPoki.chat?.selection ?? ModelKeys.defaultSelection
        List {
            ForEach(ModelProvider.allCases.filter(ModelAccounts.isSetUp)) { provider in
                Section(provider.name) {
                    let profiles: [(UUID, String)] = provider == .chatgpt
                        ? registrations.map { ($0.id, $0.title) }
                        : connections.filter { $0.provider == provider }.map { ($0.id, $0.title) }
                    ForEach(profiles, id: \.0) { id, title in
                        NavigationLink(title) {
                            List {
                                ForEach(ModelProfiles.shared.available(id)) { model in
                                    let selection = ModelSelection(provider: provider, modelID: model.id, profileID: id)
                                    Button {
                                        if let chat = AskPoki.chat { chat.selectModel(selection) }
                                        else { try? ModelProfiles.shared.select(selection) }
                                    } label: {
                                        HStack {
                                            Text(model.name)
                                            Spacer()
                                            if current == selection { Image(systemName: "checkmark") }
                                        }
                                    }
                                    .disabled(AskPoki.chat?.running == true)
                                }
                                if ModelProfiles.shared.available(id).isEmpty { Text("No available models. Check this profile in Accounts.") }
                            }
                            .navigationTitle(title)
                        }
                    }
                }
            }
        }
        .navigationTitle("Change Chat Model")
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
    }
}

private struct AddAccount: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ModelProvider?
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ModelProvider.allCases) { provider in
                        Button { if provider.signsIn { signingIn = true } else { editing = provider } } label: {
                            HStack(spacing: 12) {
                                ProviderTile(provider: provider)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: provider.name).foregroundStyle(Color(.label))
                                    Text(capabilities(provider)).font(.footnote).foregroundStyle(Color(.secondaryLabel))
                                }
                                Spacer()
                                if ModelAccounts.isSetUp(provider) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .accessibilityIdentifier("model.addProvider.\(provider.rawValue)")
                    }
                } footer: {
                    Text("Text chat works with every account. Live voice needs an OpenAI API key.")
                }
            }
            .navigationTitle("Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $editing) { provider in ProfileEditor(provider: provider, onSaved: { dismiss() }) }
            .sheet(isPresented: $signingIn, onDismiss: { if ChatGPTProfiles.shared.all.contains(where: { $0.isSignedIn }) { dismiss() } }) { ChatGPTSignIn() }
        }
    }

    private func capabilities(_ provider: ModelProvider) -> String {
        let how = ModelAccounts.method(provider)
        if ModelAccounts.canTalkLive(provider) { return String(localized: "\(how) · Text chat and live voice") }
        if ModelAccounts.canChat(provider) { return String(localized: "\(how) · Text chat") }
        return String(localized: "\(how) · Coming in an update")
    }
}
