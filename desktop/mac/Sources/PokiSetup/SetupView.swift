import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var handOff = false
    @State private var wizard: USBSetupSnapshot?
    @State private var wizardSelection: String?
    @State private var changingWizardSelection = false
    @State private var probeError: String?
    @State private var wizardError: String?
    @State private var wizardAction: String?
    @State private var automaticActions: Set<String> = []
    @State private var showInstallOptions = false
    @State private var result: InstallAnswer?
    @State private var failed: String?
    /// Set when the Apple Account is at its certificate limit: the question to put to the person.
    @State private var certificateQuestion: String?
    @State private var checking = false
    @State private var channelError: String?

    private var installing: Bool { model.busyJobs.contains("install") }

    var body: some View {
        Form {
            HeroSection {
                PageHero(symbol: nil, title: localized("Set Up Poki"), subtitle: localized("Poki Setup signs Poki with your Apple Account, installs it on your iPhone or iPad and keeps it signed."))
            }
            if showInstallOptions {
                phoneSection
                accountSection
                appSection
                if let result { resultSection(result) }
            } else {
                wizardSection
                if !changingWizardSelection, wizard?.state == .accountSignedOut { AccountView(embedded: true) }
                if let s = model.steps["install"], !s.isEmpty, installing {
                    Section { JobProgress(steps: s, running: true, weights: JobProgress.install) }
                }
            }
            Section {
                Button(showInstallOptions ? localized("Back to USB Setup") : localized("More Install Options")) {
                    showInstallOptions.toggle()
                }
            }
        }
        .pokiPage()
        .task { await model.refreshChannels() }
        .task(id: wizardSelection) {
            while !Task.isCancelled {
                if !showInstallOptions, !installing {
                    await refreshWizard()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .alert(localized("Replace the Certificate?"), isPresented: Binding(get: { certificateQuestion != nil }, set: { if !$0 { certificateQuestion = nil } })) {
            Button(localized("Replace Certificate"), role: .destructive) {
                Task {
                    do {
                        try await model.approveCertificateReplacement()
                        await install()
                    } catch { model.report(error) }
                }
            }
            Button(localized("Cancel"), role: .cancel) {}
        } message: {
            Text(certificateQuestion ?? "")
        }
        .toolbar {
            if showInstallOptions { ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await install() }
                } label: {
                    Label(localized("Install Poki"), systemImage: "arrow.down.app")
                }
                .disabled(!canInstall)
                .help(localized("Sign Poki with your Apple Account and install it on the device"))
            } }
        }
    }

    @ViewBuilder private var wizardSection: some View {
        Section {
            if let wizard, wizard.usbPhones.count > 1 || wizard.state == .chooseDevice {
                Picker(localized("Device"), selection: Binding(
                    get: { changingWizardSelection ? wizardSelection : wizard.selectedUdid },
                    set: {
                        changingWizardSelection = true
                        wizardSelection = $0
                        wizardError = nil
                    }
                )) {
                    Text(localized("Choose a device")).tag(String?.none)
                    ForEach(wizard.usbPhones) { phone in
                        Text("\(phone.name.isEmpty ? localized("Device") : phone.name) · \(phone.udid.suffix(6))").tag(Optional(phone.udid))
                    }
                }
                .disabled(wizardAction != nil || installing || certificateQuestion != nil)
            }
            if let probeError {
                Label(probeError, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else if let wizard, !changingWizardSelection {
                Text(wizardTitle(wizard.state)).font(.headline)
                Text(wizardInstruction(wizard.state)).foregroundStyle(.secondary)
                if let failure = wizard.failure, wizard.state == .signingFailed || wizard.state == .installFailed {
                    Text(failure.message).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let wizardError { Text(wizardError).foregroundStyle(.red).textSelection(.enabled) }
                wizardButtons(wizard)
                if wizardAction != nil { ProgressView().controlSize(.small) }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func wizardTitle(_ step: USBSetupStep) -> String {
        switch step {
        case .deviceDisconnected: localized("Connect your iPhone or iPad")
        case .chooseDevice: localized("Choose a device")
        case .deviceUntrusted: localized("Trust This Computer")
        case .developerModeOff: localized("Turn on Developer Mode")
        case .accountSignedOut: localized("Sign in with your Apple Account")
        case .readyToInstall: localized("Ready to install")
        case .signingFailed: localized("Poki could not be signed")
        case .installFailed: localized("Poki could not be installed")
        case .ddiUnmounted: localized("Restore the developer disk image")
        case .appUntrusted: localized("Trust the app developer")
        case .pokiNotStarted: localized("Open Poki on your iPhone")
        case .pokiUpdateRequired: localized("Update Poki to finish setup")
        case .automationPending: localized("Enable UI Automation")
        case .completed: localized("Poki is ready")
        }
    }

    private func wizardInstruction(_ step: USBSetupStep) -> String {
        switch step {
        case .deviceDisconnected: localized("Use a USB data cable and unlock the device.")
        case .chooseDevice: localized("Select the iPhone or iPad you want to set up. You can also unplug the other devices.")
        case .deviceUntrusted: localized("On the unlocked iPhone, tap Trust and enter its passcode.")
        case .developerModeOff: localized("Developer Mode lets iOS run Poki. On your iPhone, open Settings › Privacy & Security › Developer Mode. Turn it on and restart. After the restart, unlock the iPhone, tap Turn On and enter its passcode.")
        case .accountSignedOut: localized("A free Apple Account can sign Poki for this device.")
        case .readyToInstall: localized("Keep the iPhone connected and unlocked while Poki Setup signs and installs Poki.")
        case .signingFailed: localized("Check your Apple Account and try again.")
        case .installFailed: localized("Reconnect and unlock the iPhone, then try again.")
        case .ddiUnmounted: localized("Keep the iPhone connected and unlocked. Poki Setup can restore the image without reinstalling Poki.")
        case .appUntrusted: localized("On your iPhone, open Settings › General › VPN & Device Management. Select the developer for your Apple Account and tap Trust. Follow any restart prompt, then open Poki.")
        case .pokiNotStarted: localized("Tap Poki on the iPhone Home Screen.")
        case .pokiUpdateRequired: localized("Keep Poki installed to preserve its data. Update it with the Apple Account and tool you used to install it, then open it again.")
        case .automationPending: localized("On your iPhone, open Settings › Developer and turn on Enable UI Automation. Return to Poki, start automation and enter the iPhone passcode when iOS asks.")
        case .completed: localized("You can unplug the USB cable and use Poki on your iPhone.")
        }
    }

    @ViewBuilder private func wizardButtons(_ snapshot: USBSetupSnapshot) -> some View {
        if let udid = snapshot.selectedUdid {
            switch snapshot.state {
            case .deviceUntrusted:
                Button(localized("Request Trust Again")) { Task { await runWizard("wizard_pair", udid: udid) } }.disabled(wizardAction != nil)
            case .developerModeOff:
                Button(localized("Show Developer Mode in Settings")) { Task { await runWizard("wizard_reveal", udid: udid) } }.disabled(wizardAction != nil)
            case .ddiUnmounted:
                Button(localized("Restore the developer disk image")) { Task { await runWizard("wizard_mount", udid: udid) } }.disabled(wizardAction != nil)
            case .readyToInstall, .signingFailed, .installFailed:
                Button(localized(snapshot.state == .readyToInstall ? "Install Poki" : "Try Again")) {
                    Task { await install() }
                }.pokiProminentButton().disabled(installing)
            default: EmptyView()
            }
        }
    }

    private func refreshWizard() async {
        let selection = wizardSelection
        do {
            let snapshot: USBSetupSnapshot = try await model.bridge.call("wizard_state", ["udid": selection])
            guard !Task.isCancelled, selection == wizardSelection else { return }
            if wizard?.state != snapshot.state || wizard?.selectedUdid != snapshot.selectedUdid { wizardError = nil }
            wizard = snapshot
            changingWizardSelection = false
            probeError = nil
            guard let udid = snapshot.selectedUdid else { automaticActions.removeAll(); return }
            let action: String
            switch snapshot.state {
            case .deviceUntrusted: action = "wizard_pair"
            case .developerModeOff: action = "wizard_reveal"
            case .ddiUnmounted: action = "wizard_mount"
            default: return
            }
            if automaticActions.insert("\(udid)-\(action)").inserted {
                Task { await runWizard(action, udid: udid) }
            }
        } catch {
            if !Task.isCancelled, selection == wizardSelection { probeError = error.localizedDescription }
        }
    }

    private func runWizard(_ action: String, udid: String) async {
        guard wizardAction == nil, !changingWizardSelection, wizard?.selectedUdid == udid else { return }
        wizardAction = action
        wizardError = nil
        defer { wizardAction = nil }
        do { try await model.bridge.run(action, ["udid": udid]) }
        catch { wizardError = error.localizedDescription }
    }

    // MARK: iPhone

    @ViewBuilder private var phoneSection: some View {
        Section {
            if let err = model.phonesError {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized("Poki Setup can't see devices right now"))
                        Text(err.message).font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cable.connector.slash").foregroundStyle(.orange)
                }
            } else if model.phones.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color.pokiBlue)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("Connect your iPhone or iPad")).font(.headline)
                        Text(localized("Use a cable, unlock the device and tap Trust when it asks."))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressView().controlSize(.small)
                }
                .padding(.vertical, 4)
            } else {
                if model.phones.count > 1 {
                    Picker(localized("Device"), selection: Binding(get: { model.selectedPhone?.id ?? "" }, set: { model.selectedUDID = $0 })) {
                        ForEach(model.phones) { Text($0.title).tag($0.id) }
                    }
                }
                if let row = model.selectedPhone { phoneRows(row) }
            }
        } header: {
            Text(localized("Device"))
        }
    }

    @ViewBuilder private func phoneRows(_ row: PhoneRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: deviceSymbol(row.facts?.productType, name: row.title))
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Color.pokiBlue)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                if let f = row.facts {
                    Text("iOS \(f.ios) · \(f.productType)").font(.callout).foregroundStyle(.secondary)
                } else if let e = row.error {
                    Text(e).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        if let f = row.facts {
            LabeledContent(localized("Trusts This Mac")) {
                if f.pairedWithThisComputer {
                    statusText(localized("Yes"), .green)
                } else {
                    Button(localized("Pair")) { Task { await run { try await model.pair(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("pair"))
                }
            }
            LabeledContent(localized("Developer Mode")) {
                switch f.developerMode {
                case .some(true): statusText(localized("On"), .green)
                case .some(false):
                    Button(localized("Turn On…")) { Task { await run { try await model.enableDeveloperMode(udid: f.udid) } } }
                        .disabled(model.busyJobs.contains("devmode"))
                case .none: Text(localized("Checked during setup")).foregroundStyle(.secondary)
                }
            }
            if let s = model.steps["devmode"], !s.isEmpty, model.busyJobs.contains("devmode") { StepsView(steps: s) }
            if let s = model.steps["pair"], !s.isEmpty, model.busyJobs.contains("pair") { StepsView(steps: s) }
            if let r = row.record {
                LabeledContent("Poki") {
                    statusText("\(r.version) · \(relativeDays(r))", r.daysLeft <= 2 ? .orange : .green)
                }
            }
        }
    }

    private func statusText(_ s: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(s).foregroundStyle(.secondary)
        }
    }

    // MARK: Account

    @ViewBuilder private var accountSection: some View {
        Section(localized("Apple Account")) {
            if let a = model.account, a.signedIn {
                LabeledContent(localized("Signed In As")) { Text(a.name ?? a.appleId ?? "").foregroundStyle(.secondary) }
                if model.teams.count > 1 {
                    Picker(localized("Team"), selection: Binding(get: { a.teamId ?? model.teams.first?.teamId ?? "" }, set: { id in
                        if let t = model.teams.first(where: { $0.teamId == id }) { Task { await model.chooseTeam(t) } }
                    })) {
                        ForEach(model.teams) { t in Text(t.isFree ? localized("\(t.name) (free)") : t.name).tag(t.teamId) }
                    }
                } else if let t = model.teams.first {
                    LabeledContent(localized("Team")) { Text(t.isFree ? localized("\(t.name), free (7-day apps)") : t.name).foregroundStyle(.secondary) }
                }
                if model.account?.pendingFactor != nil {
                    Button(localized("Enter 6-Digit Verification Code…")) { model.needsCode = true }
                }
            } else if let err = model.accountError {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localized("Could not read your saved Apple Account"))
                            Text(localized("When macOS asks for keychain access, enter your Mac login password and choose “Always Allow”, then retry."))
                                .font(.callout).foregroundStyle(.secondary)
                            Text(err.message)
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } icon: {
                        Image(systemName: "key.slash").foregroundStyle(.orange)
                    }
                    HStack {
                        Spacer()
                        Button(localized("Retry")) { Task { await model.refreshAccount() } }
                    }
                }
            } else {
                LabeledContent(localized("Sign in with the Apple Account Poki is signed for")) {
                    Button(localized("Sign In…")) { model.page = .account }
                }
            }
        }
    }

    // MARK: Channel and updates

    private var channelChoice: Binding<String> {
        Binding(
            get: { model.channel?.id ?? "stable" },
            set: { id in
                Task {
                    do {
                        try await model.setChannel(id)
                        model.update = nil
                        channelError = nil
                    } catch { channelError = error.localizedDescription }
                }
            }
        )
    }

    /// Downloads the newer Poki Setup, puts it in place of this one and restarts.
    private func installUpdate() async {
        do { try await model.installUpdate() } catch { channelError = error.localizedDescription }
    }

    private func checkForUpdates() async {
        checking = true
        defer { checking = false }
        await model.refreshChannels()
        await model.refreshLatest()
        do {
            model.update = try await model.bridge.call("check_update")
            channelError = nil
        } catch { channelError = error.localizedDescription }
    }

    // MARK: App

    @ViewBuilder private var appSection: some View {
        Section {
            // What gets installed: the channel, with the release under it. Test builds and IPA
            // files are under Developer.
            Picker(selection: channelChoice) {
                ForEach(model.channels) { c in Text(c.displayTitle).tag(c.id) }
            } label: {
                Text("Poki")
                Text(installLine)
            }
            // Poki Setup itself.
            LabeledContent {
                if let u = model.update, u.newer {
                    Button(model.installingUpdate ? localized("Updating…") : localized("Restart to Update")) { Task { await installUpdate() } }
                        .disabled(model.installingUpdate)
                } else {
                    Button(checking ? localized("Checking…") : localized("Check for Updates")) { Task { await checkForUpdates() } }
                        .disabled(checking)
                }
            } label: {
                Text("Poki Setup")
                Text(setupLine)
            }
            HStack {
                Menu {
                    Toggle(localized("Also Show a QR Code for Wi-Fi Pairing"), isOn: $handOff)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(localized("More install options"))
                Spacer()
                Button {
                    Task { await install() }
                } label: {
                    Text(installing ? localized("Installing…") : localized("Install Poki")).frame(minWidth: 140)
                }
                .pokiProminentButton()
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canInstall)
            }
            if let steps = model.steps["install"], !steps.isEmpty {
                JobProgress(steps: steps, running: installing, weights: JobProgress.install, doneTitle: localized("Poki is installed"))
            }
            // A failure shows on the bar; one from before the first step shows here.
            if let message = (model.steps["install"]?.isEmpty ?? true) ? (failed ?? channelError) : channelError {
                Text(message).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        } header: {
            Text("Poki")
        } footer: {
            if let f = footer { Text(f).font(.footnote).foregroundStyle(.secondary) }
        }
    }

    /// The line under "Poki": what Install will put on the device.
    private var installLine: String {
        if let latest = model.latest { return buildLine(latest) }
        return localized("No release published yet")
    }

    /// The line under "Poki Setup": its version, or what the last check found.
    private var setupLine: String {
        let version = displayVersion(model.info?.version ?? "")
        guard let update = model.update else { return version }
        return update.newer ? localized("\(version), \(displayVersion(update.latest ?? "")) is available") : localized("\(version), up to date")
    }

    /// The release Install will use; says so when the chosen channel has none and a less stable one stands in.
    private func buildLine(_ r: Release) -> String {
        let id = r.channel ?? model.channel?.id ?? ""
        let title = model.channels.first(where: { $0.id == id })?.displayTitle ?? id.capitalized
        if let chosen = model.channel, !id.isEmpty, chosen.id != id {
            return localized("\(title) \(r.version) (\(r.build)), no \(chosen.displayTitle) release yet")
        }
        return "\(r.version) (\(r.build))"
    }

    /// Why Install is not available yet, if it is not.
    private var footer: String? {
        if model.accountError != nil { return localized("Unlock your keychain and choose “Always Allow”, then tap Retry above.") }
        if model.account?.signedIn != true { return localized("Sign in first. Your Apple Account password goes to Apple only.") }
        if model.latest == nil { return localized("No Poki release is published yet. To install an IPA file, use Developer › Test Builds.") }
        return nil
    }

    private var canInstall: Bool {
        !installing && model.selectedPhone?.facts != nil && model.account?.signedIn == true && model.latest != nil
    }

    @ViewBuilder private func resultSection(_ r: InstallAnswer) -> some View {
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(SetupLocalization.shared.locale)
        let expiry = r.record.expires.formatted(style)
        Section(localized("Done")) {
            Label(localized("Poki \(r.record.version) is on \(r.record.phoneName). It stays signed until \(expiry)."), systemImage: "checkmark.seal.fill")
                .foregroundStyle(.primary)
            ForEach(Array(r.notes.enumerated()), id: \.offset) { _, n in
                Text(n).font(.callout).foregroundStyle(.secondary)
            }
            Text(localized("On the device, open Settings › General › VPN & Device Management, trust your Apple Account, then open Poki."))
                .font(.callout)
            if let h = r.handoff {
                HStack(alignment: .top, spacing: 16) {
                    QRCode(text: h.link, size: 150)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("Scan with the device's Camera")).font(.headline)
                        Text(localized("Keep the device on the same Wi-Fi as this Mac. Poki opens and saves its pairing file."))
                            .font(.callout).foregroundStyle(.secondary)
                        Button(localized("Copy Link")) { copyToPasteboard(h.link) }
                    }
                }
            }
        }
    }

    private func install() async {
        guard showInstallOptions || !changingWizardSelection,
              let udid = showInstallOptions ? model.selectedPhone?.id : wizard?.selectedUdid else { return }
        failed = nil
        wizardError = nil
        result = nil
        do {
            result = try await model.install(udid: udid, ipa: nil, handOff: showInstallOptions && handOff, usbOnly: !showInstallOptions)
            if !showInstallOptions { await refreshWizard() }
        } catch let e as CoreError where e.kind == "certificate_limit" {
            failed = e.message
            certificateQuestion = e.message
        } catch {
            failed = error.localizedDescription
            if !showInstallOptions { wizardError = error.localizedDescription }
        }
    }

    private func run(_ body: () async throws -> Void) async {
        do { try await body() } catch { model.report(error) }
    }
}
