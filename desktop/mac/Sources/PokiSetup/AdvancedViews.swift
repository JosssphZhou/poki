import AppKit
import SwiftUI

// MARK: Relay

@MainActor
struct RelayView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var onboarding = RelayOnboarding()
    @State private var relayUp: Bool?
    @State private var worker: WorkerStatus?

    var body: some View {
        Form {
            HeroSection {
                PageHero(symbol: "point.3.connected.trianglepath.dotted", title: localized("Relay"), subtitle: localized("Lets AI apps reach your device from anywhere. A small Cloudflare Worker in your own account that passes messages along and stores nothing. The free plan is enough."))
            }
            if let d = model.relay {
                Section(localized("Your Relay")) {
                    LabeledContent(localized("Address")) { Text(d.address).foregroundStyle(.secondary).textSelection(.enabled) }
                    LabeledContent(localized("Cloudflare Account")) { Text(d.accountName).foregroundStyle(.secondary) }
                    LabeledContent(localized("Status")) {
                        HStack(spacing: 8) {
                            switch relayUp {
                            case .some(true): Label(localized("Answering"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            case .some(false): Label(localized("Not answering"), systemImage: "xmark.circle.fill").foregroundStyle(.red)
                            case .none: EmptyView()
                            }
                            Button(localized("Check")) { Task { await check(d.address) } }
                        }
                    }
                    HStack(alignment: .top, spacing: 16) {
                        QRCode(text: d.phoneLink, size: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localized("Give the address to Poki")).font(.headline)
                            Text(localized("Scan this with the device's Camera. Poki opens and starts using this relay."))
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button(localized("Copy Link")) { copyToPasteboard(d.phoneLink) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            if let w = worker {
                Section {
                    LabeledContent(localized("Relay Code")) {
                        Text(w.source == "built in" ? localized("Built into Poki Setup") : localized("From release \(w.source)")).foregroundStyle(.secondary)
                    }
                    if w.updateAvailable {
                        Label(localized("Relay update available. Update Relay below to match your Poki."), systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(Color.pokiBlue)
                    }
                    HStack {
                        if let u = URL(string: w.downloadUrl) { Link(localized("Download worker.js"), destination: u) }
                        Spacer()
                        if let u = URL(string: w.guideUrl) { Link(localized("Deploy It Yourself…"), destination: u) }
                    }
                } footer: {
                    Text(localized("Poki Setup deploys the relay from the same release as the Poki on your device, checked against that release's SHA256SUMS."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                let isDeploying = model.busyJobs.contains("relay")
                let steps = model.steps["relay"] ?? []
                onboardingControls
                    .disabled(onboarding.working || isDeploying)
                if !steps.isEmpty {
                    JobProgress(steps: steps, running: isDeploying, doneTitle: localized("Relay deployed"))
                }
                if (onboarding.working || isDeploying) && (!isDeploying || steps.isEmpty) {
                    ProgressView().controlSize(.small)
                }
                if let status = onboarding.status { guidance(status.text) }
                if let error = onboarding.error, !steps.contains(where: { $0.state == .failed && $0.detail == error.text }) {
                    Text(error.text).foregroundStyle(.red).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(model.relay == nil ? localized("Deploy") : localized("Redeploy"))
            } footer: {
                Text(localized("If your account doesn't have a workers.dev address yet, Poki Setup can register one when you deploy."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .pokiPage()
        .task {
            if !model.demo {
                await onboarding.readSavedToken(using: model.bridge)
                worker = try? await model.bridge.call("relay_worker")
            }
        }
        .task(id: model.relay?.address) {
            if let d = model.relay { await check(d.address) }
        }
    }

    @ViewBuilder private var onboardingControls: some View {
        if let account = onboarding.accounts.first {
            if onboarding.accounts.count == 1 {
                LabeledContent(localized("Cloudflare Account")) { Text(account.name) }
            } else {
                Picker(localized("Cloudflare Account"), selection: $onboarding.accountID) {
                    Text(localized("Choose an account")).tag("")
                    ForEach(onboarding.accounts) { Text($0.name).tag($0.id) }
                }
            }
            HStack {
                Button(localized("Cancel")) { cancelOnboarding() }
                Spacer()
                Button(model.relay == nil ? localized("Deploy Relay") : localized("Update Relay")) {
                    Task {
                        if await onboarding.deploy(using: model) != nil {
                            relayUp = true
                            worker = try? await model.bridge.call("relay_worker")
                        }
                    }
                }
                .pokiProminentButton()
                .disabled(!onboarding.canDeploy)
            }
        } else if onboarding.entry == .browser {
            guidance(localized("Create the API token in Cloudflare and restrict it to the account you want to use. Copy the token, then return here to import it."))
            HStack {
                Button(localized("Cancel")) { cancelOnboarding() }
                Button(localized("Enter Token Manually…")) { onboarding.enterManually() }
                Spacer()
                Button(localized("Import Copied Token")) {
                    Task {
                        await onboarding.importCopiedToken(using: model) {
                            NSPasteboard.general.string(forType: .string)
                        }
                    }
                }
                .pokiProminentButton()
            }
        } else if onboarding.entry == .manual {
            SecureField(localized("Cloudflare API Token"), text: $onboarding.manualToken, prompt: Text(localized("Paste the token")))
            HStack {
                Button(localized("Cancel")) { cancelOnboarding() }
                Spacer()
                Button(localized("Continue")) { Task { await onboarding.useManualToken(using: model) } }
                    .pokiProminentButton()
                    .disabled(onboarding.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else {
            if onboarding.tokenSaved == true {
                LabeledContent(localized("Cloudflare API Token")) {
                    HStack {
                        Text(localized("Saved in Keychain")).foregroundStyle(.secondary)
                        Button(localized("Forget")) { Task { await onboarding.forgetToken(using: model.bridge) } }
                    }
                }
            }
            HStack {
                Button(localized("Enter Token Manually…")) { onboarding.enterManually() }
                Spacer()
                if onboarding.tokenSaved == true {
                    connectButton
                    Button(localized("Continue with Saved Token")) { Task { await onboarding.useSavedToken(using: model) } }
                        .pokiProminentButton()
                } else {
                    connectButton.pokiProminentButton()
                }
            }
        }
    }

    private var connectButton: some View {
        Button {
            Task { await onboarding.connect(using: model.bridge) { NSWorkspace.shared.open($0) } }
        } label: {
            Label(localized("Connect Cloudflare"), systemImage: "arrow.up.right")
        }
    }

    private func cancelOnboarding() {
        onboarding.cancel()
        if model.steps["relay"]?.contains(where: { $0.state == .failed }) == true {
            model.steps["relay"] = []
        }
    }

    private func guidance(_ text: String) -> some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func check(_ address: String) async {
        let answering: Bool? = model.demo ? true : (try? await model.bridge.call("relay_check", ["address": address]))
        if model.relay?.address == address, !Task.isCancelled { relayUp = answering }
    }
}

// MARK: Connectors

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var filter = ""
    @State private var streaming = false
    @State private var showHelperLog = false
    @State private var message: SetupMessage?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(localized("Device Log")) {
                    HStack {
                        TextField(localized("Filter"), text: $filter, prompt: Text("Poki"))
                            .frame(maxWidth: 220)
                        Spacer()
                        Button(streaming ? localized("Stop") : localized("Start")) { Task { await toggle() } }
                            .disabled(model.selectedPhone == nil && !streaming)
                        Button(localized("Clear")) { model.logLines.removeAll() }
                        Button(localized("Copy")) { copyToPasteboard(model.logLines.joined(separator: "\n")) }
                    }
                }
                Section(localized("Tools")) {
                    LabeledContent(localized("Developer Disk Image")) {
                        Button(localized("Mount")) { Task { await mount() } }.disabled(model.selectedPhone == nil)
                    }
                    LabeledContent(localized("Support Bundle")) {
                        Button(localized("Save…")) { Task { await saveBundle() } }
                    }
                    LabeledContent(localized("Helper Log")) {
                        Button(showHelperLog ? localized("Hide") : localized("Show")) { showHelperLog.toggle() }
                    }
                    if let message { Text(message.text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                }
            }
            .pokiPage()
            .scrollDisabled(true)
            .frame(height: message == nil ? 318 : 350)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    let lines = showHelperLog ? model.bridge.helperLog : model.logLines
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines.suffix(2000).enumerated()), id: \.offset) { i, l in
                            Text(l).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).id(i)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .overlay {
                    if (showHelperLog ? model.bridge.helperLog : model.logLines).isEmpty {
                        Text(showHelperLog ? localized("The helper has not logged anything yet.") : (model.selectedPhone == nil ? localized("Connect a device to see its log here.") : localized("Press Start to see the device's log here.")))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: model.logLines.count) { _, _ in proxy.scrollTo(min(model.logLines.count, 2000) - 1, anchor: .bottom) }
            }
        }
    }

    private func toggle() async {
        do {
            if streaming {
                try await model.bridge.run("logs_stop")
                streaming = false
            } else if let p = model.selectedPhone {
                try await model.bridge.run("logs_start", ["udid": p.id, "filter": filter.isEmpty ? nil : filter])
                streaming = true
            }
        } catch { model.report(error) }
    }

    private func mount() async {
        guard let p = model.selectedPhone else { return }
        do {
            try await model.job("ddi") { try await model.bridge.run("mount_ddi", ["udid": p.id]) }
            message = .copy("The Developer Disk Image is mounted.")
        } catch { model.report(error) }
    }

    private func saveBundle() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = localized("Save Here")
        panel.message = localized("Support bundles can contain device identifiers, local paths and raw logs. Review the archive before sharing.")
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        do {
            let path: String = try await model.bridge.call("support_bundle", ["udid": model.selectedPhone?.id, "out_dir": dir.path])
            message = .copy("Saved \(path). Review the archive before sharing.")
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } catch { model.report(error) }
    }
}

// MARK: Settings

struct SettingsView: View {
    @Bindable private var localization = SetupLocalization.shared
    @EnvironmentObject var model: AppModel
    @State private var choice = ""
    @State private var custom = ""
    @State private var message: SetupMessage?

    private let customTag = "custom"
    private let systemTag = "system"

    var body: some View {
        Form {
            Section {
                Picker(localized("Language"), selection: $localization.language) {
                    Text(localized("Follow System")).tag(SetupLanguage.system)
                    Text(verbatim: "English").tag(SetupLanguage.english)
                    Text(verbatim: "简体中文").tag(SetupLanguage.simplifiedChinese)
                }
            }
            Section {
                Picker(localized("Identity Server"), selection: $choice) {
                    ForEach(model.info?.anisetteServers ?? [], id: \.self) { u in
                        Text(URL(string: u)?.host ?? u).tag(u)
                    }
                    if model.info?.canUseSystemAnisette == true { Text(localized("This Mac (macOS 26 and earlier)")).tag(systemTag) }
                    Text(localized("Other…")).tag(customTag)
                }
                if choice == customTag {
                    TextField(localized("Server Address"), text: $custom, prompt: Text("https://"))
                }
                HStack {
                    if let message { Text(message.text).font(.callout).foregroundStyle(.secondary) }
                    Spacer()
                    Button(localized("Apply")) { Task { await apply() } }
                }
            } header: {
                Text(localized("Sign-In"))
            } footer: {
                Text(localized("Apple's sign-in wants proof that it talks to a Mac or PC (“anisette”). A server provides it; it never sees your Apple Account or password. If sign-in fails, try another one."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(localized("About")) {
                LabeledContent(localized("Version")) { Text(displayVersion(model.info?.version ?? "")).foregroundStyle(.secondary) }
            }
            Section(localized("Data")) {
                LabeledContent(localized("Folder")) {
                    Button(localized("Show in Finder")) {
                        if let d = model.info?.dataDir { NSWorkspace.shared.open(URL(fileURLWithPath: d)) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 560)
        .onAppear(perform: load)
    }

    private func load() {
        guard let src = model.account?.anisette else { choice = model.info?.defaultAnisette ?? ""; return }
        if src.kind == "system" {
            choice = systemTag
        } else if let u = src.url, (model.info?.anisetteServers ?? []).contains(u) {
            choice = u
        } else {
            choice = customTag
            custom = src.url ?? ""
        }
    }

    private func apply() async {
        let src: AnisetteSource = choice == systemTag ? .system : .remote(choice == customTag ? custom : choice)
        do {
            try await model.setAnisette(src)
            message = .copy("Saved.")
        } catch { message = .verbatim(error.localizedDescription) }
    }
}
