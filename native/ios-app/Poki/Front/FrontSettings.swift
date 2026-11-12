import PokiCore
import SwiftUI

/// The pages only the front has. Everything else it pushes is a page the app already had.
enum FrontRoute: Hashable { case settings, connection, agents, appearance, signing }

/// Settings, behind the gear on the chats page: whether Poki can use this iPhone, then one row each for
/// what it thinks with, who else may use it, what it remembers and how it looks, and the one switch.
/// Every setting the app has sits behind one of them.
struct FrontSettings: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue

    private var agentsLine: String {
        if model.relayAddress == nil || !model.relayEnabled { return String(localized: "Off") }
        if case .offline = model.relayStatus { return String(localized: "Offline") }
        let count = model.identity.secrets.count
        return count == 0 ? String(localized: "None yet") : String(localized: "\(count) connected")
    }

    /// The version and build, as a bug report asks for them.
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Poki \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(spacing: 0) {
                NavigationLink(value: FrontRoute.connection) { StatusCard(chevron: true) }.buttonStyle(.plain)
                    .padding(.bottom, 20)
                PaperRows {
                    NavigationLink(value: AgentsRoute.accounts) {
                        PaperRow(String(localized: "Model"), value: ModelKeys.hasUsableKey ? ModelKeys.selectedModelName : String(localized: "Add an account"))
                    }
                    NavigationLink(value: FrontRoute.agents) { PaperRow(String(localized: "Agents"), value: agentsLine) }
                    NavigationLink(value: SettingsRoute.memory) {
                        PaperRow(String(localized: "Memory"), value: String(localized: "\(RoutineStore.shared.routines.count) routines"))
                    }
                    NavigationLink(value: FrontRoute.appearance) {
                        PaperRow(String(localized: "Appearance"), value: (PokiLight(rawValue: light) ?? .firstLight).name)
                    }
                }
                .buttonStyle(.plain)
                Toggle(isOn: $model.askBeforeSensitiveSteps) {
                    Text("Ask before sensitive steps").font(Paper.row).foregroundStyle(Paper.ink)
                }
                .frame(minHeight: 54).padding(.top, 22)
                Text("Poki asks you before it or an agent pays, deletes, sends a message, places a call, types a password or does anything in Wallet.")
                    .font(Paper.note).foregroundStyle(Paper.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                // PokiCore reads the switch when Poki starts.
                Text("Changes take effect the next time Poki opens.")
                    .font(Paper.note).foregroundStyle(Paper.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                Text(verbatim: version).font(Paper.note).monospacedDigit().foregroundStyle(Paper.ink2).padding(.top, 28)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .paperPage()
    }
}

/// Poki on its sky, saying whether it can use this iPhone: the first thing in Settings and in Connection.
private struct StatusCard: View {
    @Environment(AppModel.self) private var model
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue
    var chevron = false

    private var ready: Bool { model.setupLooksComplete && model.sessionOn }
    private var openStep: SetupStep? { SetupStep.shown.first { !model.isDone($0) } }
    private var title: String {
        ready ? String(localized: "Poki is ready") : model.setupLooksComplete ? String(localized: "Poki is off") : String(localized: "Poki needs a hand")
    }
    private var detail: String {
        if ready { return String(localized: "It can use this iPhone") }
        if model.setupLooksComplete { return String(localized: "Turn it on to give it a task") }
        return openStep.map { String(localized: "\(ActivityWords.local($0.activityTitle)) is still to do") } ?? String(localized: "Setup isn’t finished")
    }

    var body: some View {
        let colors = (PokiLight(rawValue: light) ?? .firstLight).palette
        HStack(spacing: 12) {
            PokiBear(pose: ready ? "happy" : model.setupLooksComplete ? "sleep" : "worry").frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.system(size: 17, weight: .semibold))
                Text(verbatim: detail).font(Paper.note).opacity(0.8)
            }
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).opacity(0.8) }
        }
        .foregroundStyle(.white)
        .padding(.leading, 14).padding(.trailing, 18).frame(height: 88)
        .background {
            // The top of Poki's sky, with the warm light low on the right.
            ZStack {
                LinearGradient(colors: [colors.deep, colors.sky], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 1.5))
                RadialGradient(colors: [colors.warm.opacity(0.7), colors.warm.opacity(0)], center: UnitPoint(x: 0.9, y: 1.4), startRadius: 0, endRadius: 150)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .contentShape(.rect)
    }
}

/// Settings › Connection: Poki on or off, everything it needs on this iPhone (the app's own setup items,
/// each opening its own page), signing, the advanced pages, and the first run again.
struct ConnectionPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    var setUpAgain: () -> Void

    /// Each item as a state the phone is in, not a thing to do: "Paired with Poki", "Poki keeps running".
    private static func name(_ step: SetupStep) -> String {
        switch step {
        case .runner: String(localized: "Poki Runner")
        case .developerMode: String(localized: "Developer Mode")
        case .loopback: String(localized: "Loopback")
        case .pairing: String(localized: "Paired with Poki")
        case .automation: String(localized: "UI Automation")
        case .background: String(localized: "Poki keeps running")
        }
    }

    /// What an open item needs: what is wrong when the phone can tell, otherwise that it is to turn on.
    private func need(_ step: SetupStep) -> String {
        switch step {
        case .loopback:
            if model.loopback.state == .noAnswer { return String(localized: "No answer") }
            if model.setup.loopback != .none { return String(localized: "Off") }
        case .pairing:
            if model.pairingTrouble != nil { return String(localized: "Pair again") }
            if model.pairingPath != nil, !model.diskImage.isReady { return String(localized: "Downloading") }
        default: break
        }
        return String(localized: "Turn on")
    }

    private var signingLine: String? {
        guard let expiry = model.signer.expiry else { return nil }
        let days = max(0, Int((expiry.timeIntervalSinceNow / 86400).rounded(.up)))
        return days == 1 ? String(localized: "1 day left") : String(localized: "\(days) days left")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                StatusCard().padding(.bottom, 12)
                Toggle(isOn: Binding(get: { model.sessionOn }, set: { on in
                    if on { model.startSession() } else { chat.stop(); model.stopSession() }
                })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "Poki").font(Paper.row).foregroundStyle(Paper.ink)
                        Text(model.sessionOn ? "On. Poki and your agents can use this iPhone" : "Off. Nothing can use this iPhone")
                            .font(Paper.note).foregroundStyle(Paper.ink2)
                    }
                }
                .frame(minHeight: 60)
                .disabled(!model.setupLooksComplete && !model.sessionOn)
                PaperHeader(text: String(localized: "On this iPhone"))
                PaperRows {
                    ForEach(Array(SetupStep.shown.enumerated()), id: \.element) { i, step in
                        let done = model.isDone(step)
                        NavigationLink(value: step) {
                            PaperRow(title: Self.name(step), detail: nil,
                                     value: done ? (step == .pairing || step == .runner ? String(localized: "Done") : String(localized: "On")) : need(step),
                                     chevron: !done) { PaperMark(kind: done ? .done : .warn) }
                        }
                    }
                }
                .buttonStyle(.plain)
                Text("Poki drives this iPhone through Apple’s developer tools, so all of these have to stay on.")
                    .font(Paper.note).foregroundStyle(Paper.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).padding(.bottom, 22)
                PaperRows {
                    NavigationLink(value: FrontRoute.signing) { PaperRow(String(localized: "Signing and updates"), value: signingLine) }
                    NavigationLink(value: SetupRoute.advanced) { PaperRow(String(localized: "Advanced")) }
                    Button(action: setUpAgain) { PaperRow(String(localized: "Set up again")) }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.loopback.resume() }
        .paperPage()
    }
}

/// Connection › Signing and updates: the app's own signing section, on a page of its own.
struct SigningPage: View {
    var body: some View {
        List { SigningSection() }
            .paperList()
            .navigationTitle("Signing and updates")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings › Appearance: Poki's light, and light or dark.
struct AppearancePage: View {
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue
    @AppStorage(PokiLight.schemeKey) private var scheme = ""
    @Environment(\.colorScheme) private var shown

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text("Poki’s light is the one colour in the app. It sits behind Poki in the window and when you talk.")
                    .font(.system(size: 15)).foregroundStyle(Paper.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LightSwatches(light: $light).padding(.top, 18)
                Text(verbatim: (PokiLight(rawValue: light) ?? .firstLight).name).font(Paper.note).foregroundStyle(Paper.ink2).padding(.top, 12)
                PaperRows {
                    schemeRow(String(localized: "Light"), "light", on: shown == .light)
                    schemeRow(String(localized: "Dark"), "dark", on: shown == .dark)
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .paperPage()
    }

    private func schemeRow(_ title: String, _ value: String, on: Bool) -> some View {
        Button { scheme = value } label: {
            HStack {
                Text(verbatim: title).font(Paper.row).foregroundStyle(Paper.ink)
                Spacer()
                if on { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink) }
            }
            .frame(minHeight: 54).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Poki's five lights as a row of swatches; the chosen one has a ring in ink.
struct LightSwatches: View {
    @Binding var light: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PokiLight.allCases) { choice in
                let colors = choice.palette, chosen = choice.rawValue == light
                Button { light = choice.rawValue } label: {
                    Circle().fill(RadialGradient(colors: [colors.warm, colors.mid, colors.sky], center: UnitPoint(x: 0.5, y: 0.72), startRadius: 2, endRadius: 30))
                        .frame(width: 50, height: 50)
                        .padding(5)
                        .overlay(Circle().strokeBorder(Paper.ink, lineWidth: 2).opacity(chosen ? 1 : 0))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(verbatim: choice.name))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}
