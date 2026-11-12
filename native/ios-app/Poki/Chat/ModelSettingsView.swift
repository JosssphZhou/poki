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
    /// As Settings › Model, Voice is reached from this page. The first run shows the accounts alone.
    var showsVoice = false
    @State private var adding = false
    @State private var version = ModelKeys.saved

    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var voice = app.voice
        PaperScroll {
            PaperHeader(text: String(localized: "In use"))
            PaperRows {
                // The account the chat runs on opens from here; with none, this adds one.
                if ModelKeys.hasUsableKey {
                    NavigationLink { AccountDetail(provider: ModelKeys.selectedProvider).paperPage() } label: {
                        PaperRow(String(localized: "Text chat"), value: ModelKeys.selectedModelName)
                    }
                } else {
                    Button { adding = true } label: { PaperRow(String(localized: "Text chat"), value: String(localized: "Add an account")) }
                }
                if VoiceDirect.apiKey != nil {
                    NavigationLink { AccountDetail(provider: .openai).paperPage() } label: {
                        PaperRow(String(localized: "Live voice"), value: VoiceDirect.model)
                    }
                } else {
                    PaperRow(String(localized: "Live voice"), detail: String(localized: "Talking with Poki needs an OpenAI key"),
                             value: app.voice.canTalkLive ? String(localized: "Voice bridge") : String(localized: "Not available"), chevron: false)
                }
                PaperRow(String(localized: "Dictation"), value: String(localized: "On this iPhone"), chevron: false)
            }
            PaperHeader(text: String(localized: "Accounts"))
            PaperRows {
                ForEach(ModelProvider.allCases.filter(ModelAccounts.isSetUp)) { provider in
                    NavigationLink { AccountDetail(provider: provider).paperPage() } label: {
                        PaperRow(provider.name, value: ModelAccounts.method(provider))
                    }
                }
                Button { adding = true } label: { PaperRow(String(localized: "Add an account")) }
            }
            PaperFoot(text: String(localized: "Keys and sign-ins stay in this iPhone’s Keychain. Poki sends each one only to its own provider."))
            if showsVoice {
                PaperHeader(text: String(localized: "Voice"))
                PaperRows {
                    Toggle(isOn: $voice.muted) { Text("Mute Poki’s voice").font(Paper.row).foregroundStyle(Paper.ink) }
                        .frame(minHeight: 54)
                    NavigationLink(value: AgentsRoute.voice) {
                        PaperRow(String(localized: "Mac voice bridge"), value: app.voice.bridge?.display ?? String(localized: "Not set"))
                    }
                }
            }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $adding) { AddAccount() }
    }
}

/// What a model account is and what it can power.
enum ModelAccounts {
    static func isSetUp(_ provider: ModelProvider) -> Bool {
        switch provider {
        case .custom: !ModelKeys.customURL.isEmpty
        case .chatgpt: ChatGPTAccount.signedIn
        default: ModelKeys.hasKey(provider)
        }
    }

    static func canChat(_ provider: ModelProvider) -> Bool { provider.wired }
    /// Live voice is OpenAI's Realtime API: an OpenAI API key only (a ChatGPT sign-in can't open it).
    static func canTalkLive(_ provider: ModelProvider) -> Bool { provider == .openai }

    static func method(_ provider: ModelProvider) -> String {
        switch provider {
        case .chatgpt: String(localized: "Sign in with ChatGPT")
        case .custom: String(localized: "OpenAI-compatible address")
        default: String(localized: "API key")
        }
    }
}

/// One account: its type and connection, what it is used for (switches; the ones it can't power are
/// shown greyed with why), its model, and Delete.
private struct AccountDetail: View {
    @Environment(\.dismiss) private var dismiss
    var provider: ModelProvider
    @State private var editing = false
    @State private var signingIn = false
    @State private var version = ModelKeys.saved

    var body: some View {
        List {
            PaperSection {
                LabeledContent("Type", value: provider.name)
                LabeledContent("Connection", value: ModelAccounts.method(provider))
                if provider == .custom { LabeledContent("Address", value: ModelKeys.customURL) }
                Button(provider.signsIn ? "Sign in again" : provider == .custom ? "Edit address and key" : "Replace key") {
                    if provider.signsIn { signingIn = true } else { editing = true }
                }
            }

            PaperSection {
                NavigationLink { TextChatFeature(provider: provider) } label: {
                    LabeledContent {
                        Text(ModelKeys.selectedProvider == provider ? ModelKeys.selectedModelName : ModelAccounts.canChat(provider) ? String(localized: "Off") : String(localized: "Not supported"))
                    } label: { Label("Text chat", systemImage: "bubble.left.and.text.bubble.right") }
                }
                .disabled(!ModelAccounts.canChat(provider))
                NavigationLink { LiveVoiceFeature() } label: {
                    LabeledContent {
                        Text(ModelAccounts.canTalkLive(provider) ? (VoiceDirect.enabled ? VoiceDirect.model : String(localized: "Off")) : String(localized: "Not supported"))
                    } label: { Label("Live voice", systemImage: "waveform") }
                }
                .disabled(!ModelAccounts.canTalkLive(provider))
            } header: {
                Text("Use this account for")
            } footer: {
                if !ModelAccounts.canChat(provider) {
                    Text("Poki keeps this key; chatting with \(provider.name) comes in an update.")
                } else if !ModelAccounts.canTalkLive(provider) {
                    Text("Live voice runs on OpenAI’s Realtime API, which only an OpenAI API key can open. Dictation in the message field works with this account.")
                }
            }

            PaperSection {
                Button(provider.signsIn ? "Sign out" : "Delete account") {
                    if provider == .custom { ModelKeys.customURL = ""; ModelKeys.customModel = "" }
                    ModelKeys.remove(provider)
                    if ModelKeys.selectedProvider == provider, let other = ModelProvider.allCases.first(where: { ModelAccounts.isSetUp($0) && ModelAccounts.canChat($0) }) {
                        ModelKeys.selectedProvider = other
                    }
                    dismiss()
                }
            }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .paperList()
        .navigationTitle(Text(verbatim: provider.name))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .sheet(isPresented: $editing, onDismiss: { version = ModelKeys.saved }) { KeyEntry(provider: provider) }
        .sheet(isPresented: $signingIn, onDismiss: { version = ModelKeys.saved }) { ChatGPTSignIn() }
    }
}

/// Account › Text Chat: whether this account runs the chat, its model, and which of its models the
/// chat's model menu offers.
private struct TextChatFeature: View {
    var provider: ModelProvider
    @State private var version = ModelKeys.saved
    @State private var loading = false
    @State private var problem: String?

    var body: some View {
        List {
            PaperSection {
                Toggle("Use for text chat", isOn: Binding(get: { ModelKeys.selectedProvider == provider }, set: { on in
                    if on { ModelKeys.selectedProvider = provider }
                    else if let other = ModelProvider.allCases.first(where: { $0 != provider && ModelAccounts.isSetUp($0) && ModelAccounts.canChat($0) }) {
                        ModelKeys.selectedProvider = other
                    }
                }))
                if ModelKeys.selectedProvider == provider {
                    Picker("Chat model", selection: Binding(get: { ModelKeys.selectedModel }, set: { ModelKeys.selectedModel = $0; ModelKeys.saved += 1 })) {
                        ForEach(ModelCatalog.available(provider)) { Text($0.name).tag($0.id) }
                    }
                }
            } footer: {
                Text("Only one account runs the text chat at a time.")
            }
            PaperSection {
                ForEach(ModelCatalog.all(provider)) { choice in
                    Toggle(isOn: Binding(get: { ModelCatalog.enabled(provider).contains(choice.id) }, set: { ModelCatalog.set(choice.id, on: $0, for: provider) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.name)
                            if ModelCatalog.fast(choice.id) { Text("Fast").font(.caption).foregroundStyle(Paper.ink2) }
                        }
                    }
                }
                if provider != .chatgpt {
                    Button(loading ? "Reading the model list…" : "Refresh model list") { refresh() }.disabled(loading)
                }
            } header: {
                Text("Models to choose from")
            } footer: {
                Text(problem ?? String(localized: "Fast models without long thinking answer quickest on the phone. Models from \(provider.name)’s list start switched off."))
            }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .paperList()
        .navigationTitle("Text chat")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
        .task { if ModelCatalog.listed(provider).isEmpty, provider != .chatgpt { refresh() } }
    }

    private func refresh() {
        loading = true
        problem = nil
        Task {
            do { _ = try await ModelCatalog.refresh(provider) } catch { problem = String(localized: "\(provider.name) didn’t return its model list. The built-in models still work.") }
            loading = false
        }
    }
}

/// Account › Live Voice (OpenAI only): on or off, the voice model, and which voice models to offer.
private struct LiveVoiceFeature: View {
    @State private var version = ModelKeys.saved

    var body: some View {
        List {
            PaperSection {
                Toggle("Use for live voice", isOn: Binding(get: { VoiceDirect.enabled }, set: { VoiceDirect.enabled = $0 }))
                if VoiceDirect.enabled {
                    Picker("Voice model", selection: Binding(get: { ModelCatalog.voiceModel }, set: { ModelCatalog.voiceModel = $0 })) {
                        ForEach(ModelCatalog.voiceAvailable) { Text($0.name).tag($0.id) }
                    }
                }
            } footer: {
                Text("Live voice is a spoken conversation with OpenAI’s Realtime model: it listens, taps and types, and answers out loud.")
            }
            PaperSection {
                ForEach(ModelCatalog.voiceAll) { choice in
                    Toggle(choice.name, isOn: Binding(get: { ModelCatalog.voiceEnabled.contains(choice.id) }, set: { ModelCatalog.setVoice(choice.id, on: $0) }))
                }
            } header: {
                Text("Voice models to choose from")
            } footer: {
                Text("Refresh the model list under Text chat to add the other Realtime models your key can use.")
            }
        }
        // Reads the version so the page redraws with the new keys and models, without rebuilding it
        // (a rebuild dropped taps and the sheets it was presenting).
        .background { Color.clear.accessibilityHidden(true).id(version) }
        .paperList()
        .navigationTitle("Live voice")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: ModelKeys.changed)) { _ in version = ModelKeys.saved }
    }
}

/// Add Account: the account types, each with how it connects; choosing one opens its key, address or
/// sign-in.
private struct AddAccount: View {
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ModelProvider?
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            List {
                PaperSection {
                    ForEach(ModelProvider.allCases) { provider in
                        Button { if provider.signsIn { signingIn = true } else { editing = provider } } label: {
                            HStack(spacing: 12) {
                                ProviderTile(provider: provider)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: provider.name).foregroundStyle(Paper.ink)
                                    Text(capabilities(provider)).font(.footnote).foregroundStyle(Paper.ink2)
                                }
                                Spacer()
                                if ModelAccounts.isSetUp(provider) { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                } footer: {
                    Text("Text chat works with every account. Live voice needs an OpenAI API key.")
                }
            }
            .paperList()
            .navigationTitle("Add an account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $editing, onDismiss: { if editing == nil { dismiss() } }) { provider in KeyEntry(provider: provider) }
            .sheet(isPresented: $signingIn, onDismiss: { if ChatGPTAccount.signedIn { dismiss() } }) { ChatGPTSignIn() }
        }
    }

    private func capabilities(_ provider: ModelProvider) -> String {
        let how = ModelAccounts.method(provider)
        if ModelAccounts.canTalkLive(provider) { return String(localized: "\(how) · Text chat and live voice") }
        if ModelAccounts.canChat(provider) { return String(localized: "\(how) · Text chat") }
        return String(localized: "\(how) · Coming in an update")
    }
}

/// Entering, replacing or removing one provider's key. The field is secure and the key is never shown
/// again after it is saved.
private struct KeyEntry: View {
    @Environment(\.dismiss) private var dismiss
    var provider: ModelProvider
    @State private var key = ""
    @State private var url = ModelKeys.customURL
    @State private var modelID = ModelKeys.customModel
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if provider == .custom {
                    PaperSection {
                        TextField("https://…/v1", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Model, such as llama-4-maverick", text: $modelID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } header: { Text("Address and model") }
                }
                PaperSection {
                    SecureField(provider.keyPrompt, text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text("\(provider.name) key")
                } footer: {
                    if !provider.wired {
                        Text("Poki keeps the key now; chatting with \(provider.name) comes in an update. Until then, choose Anthropic or OpenAI.")
                    } else if ModelKeys.hasKey(provider) {
                        Text("A key is saved. Enter a new one to replace it.")
                    } else {
                        Text(verbatim: provider.keyHelp)
                    }
                }
                if failed { PaperSection { Text("The keychain did not take the key. Try again.").font(Paper.value).padding(.vertical, 12) } }
                if ModelKeys.hasKey(provider) {
                    PaperSection { Button("Remove key") { ModelKeys.remove(provider); dismiss() } }
                }
            }
            .paperList()
            .navigationTitle(Text(verbatim: provider.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
    }

    private var canSave: Bool {
        provider == .custom ? URL(string: url.trimmingCharacters(in: .whitespaces))?.scheme?.hasPrefix("http") == true && !modelID.trimmingCharacters(in: .whitespaces).isEmpty : !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        do {
            if provider == .custom {
                ModelKeys.customURL = url.trimmingCharacters(in: .whitespaces)
                ModelKeys.customModel = modelID.trimmingCharacters(in: .whitespaces)
                if key.isEmpty { ModelKeys.selectedProvider = .custom }
            }
            if !key.isEmpty { try ModelKeys.save(key, for: provider) }
            // A new key picks its provider; the model page's picker switches between providers with keys.
            if provider.wired, !key.isEmpty {
                // Ready at once: chat on this account's first fast model, live voice on where it can.
                ModelKeys.selectedProvider = provider
                if let first = ModelCatalog.available(provider).first { ModelKeys.selectedModel = first.id }
                if provider == .openai { VoiceDirect.enabled = true }
                Task { _ = try? await ModelCatalog.refresh(provider) }
            }
            key = ""
            dismiss()
        } catch {
            failed = true
        }
    }
}
