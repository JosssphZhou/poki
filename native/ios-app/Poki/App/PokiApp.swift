import PokiCore
import SwiftUI

@main
struct PokiApp: App {
    @State private var model: AppModel
    @State private var chat: ChatModel

    init() {
        // PokiLauncher (Rust) and the relay write to sockets the other side may have closed. In an app,
        // unlike a Rust executable, nothing ignores SIGPIPE, and it would end the whole app.
        signal(SIGPIPE, SIG_IGN)
        // iOS 26: the background task that keeps Poki up is registered before launch ends, as iOS asks.
        if #available(iOS 26.0, *) { ContinuedRun.registerAtLaunch() }
        // Settings an update, a reinstall or a re-sign lost come back from the Keychain, before anything
        // reads them; from here on every change is mirrored there.
        SettingsVault.restore()
        SettingsVault.watch()
        #if DEBUG && targetEnvironment(simulator)
        TestCredential.importIfGiven()
        #endif
        // A memory backup Poki Setup put back (Documents/AgentBackup) is merged in before any agent asks.
        _ = RoutineStore.shared.importRestoredBackup()
        let model = AppModel()
        _model = State(initialValue: model)
        let chat = ChatModel(app: model)
        _chat = State(initialValue: chat)
        AskPoki.install(app: model, chat: chat)
    }

    var body: some Scene {
        WindowGroup {
            RootView().environment(model).environment(chat)
        }
    }
}

/// Poki's front: a new chat is the first page, the chats are beside it (one swipe away on iPhone, a
/// sidebar in a wide window), and every other screen is pushed over them. Voice lives inside the chat: a
/// live conversation and dictation into the message field.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    @Environment(\.scenePhase) private var scenePhase
    /// Everything pushed over the front: a chat, an agent's session, Settings and its pages.
    @State private var home = NavigationPath()
    /// The first run's pages, until the owner has been through them once.
    @State private var welcoming = false
    /// Settings › Appearance: light, dark, or the iPhone's own when nothing is chosen.
    @AppStorage(PokiLight.schemeKey) private var scheme = ""
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue

    /// Poki's chat and an outside agent's session.
    enum HomeRoute: Hashable { case chat, session(String) }

    @Environment(\.horizontalSizeClass) private var width
    @State private var frontPage: FrontPage? = .newChat
    /// iPhone, and a narrow window on iPad: the chats are a page. Wide (iPad, the inner display of
    /// iPhone Duo, a large Stage Manager window): they are a sidebar beside the page in front.
    private var compact: Bool { width != .regular }
    /// The sidebar in a wide window. In portrait it lies over the page and leaves once a chat is chosen.
    @State private var columns = NavigationSplitViewVisibility.automatic

    private func show(_ route: HomeRoute) {
        home = NavigationPath([route])
        columns = .automatic
    }

    @ViewBuilder private func page(_ route: HomeRoute) -> some View {
        switch route {
        case .chat:
            ChatView(openDetails: { home.append(FrontRoute.settings) }, openVoice: openLiveVoice, openSetup: openSetup,
                     openModel: { openAgents(.accounts) }, back: { home = NavigationPath() })
        case .session(let id):
            SessionView(id: id, back: { home = NavigationPath() })
        }
    }

    private func newChatPage(openChats: @escaping () -> Void, symbol: String = "text.alignright", paged: Bool = true) -> some View {
        NewChatPage(start: startChat, openChats: openChats, chatsSymbol: symbol, paged: paged, openVoice: openLiveVoice,
                    openModel: { openAgents(.accounts) })
    }

    private func chatsPage(newChat: @escaping () -> Void) -> some View {
        ChatsPage(open: { openRun($0.id) }, newChat: newChat, openSettings: { home = NavigationPath([FrontRoute.settings]); columns = .automatic }, openSetup: openSetup,
                  openModel: { home = NavigationPath([AgentsRoute.accounts]); columns = .automatic },
                  openAgents: { home = NavigationPath([FrontRoute.agents]); columns = .automatic })
    }

    @ViewBuilder private var front: some View {
        if compact {
            NavigationStack(path: $home) {
                FrontPager(page: $frontPage, pose: model.voice.isLive ? TalkWords.pose(model.voice) : chat.running ? "phone" : "rest") {
                    newChatPage(openChats: { withAnimation(.snappy) { frontPage = .chats } })
                } chats: {
                    chatsPage(newChat: { withAnimation(.snappy) { frontPage = .newChat } })
                }
                .toolbar(.hidden, for: .navigationBar)
                .modifier(FrontDestinations(page: { AnyView(page($0)) }, home: $home, setUpAgain: { welcoming = true }, openRun: openRun))
            }
        } else {
            NavigationSplitView(columnVisibility: $columns) {
                chatsPage(newChat: { home = NavigationPath(); columns = .automatic })
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
            } detail: {
                NavigationStack(path: $home) {
                    newChatPage(openChats: { withAnimation { columns = columns == .all ? .detailOnly : .all } }, symbol: "sidebar.left", paged: false)
                        .toolbar(.hidden, for: .navigationBar)
                        .modifier(FrontDestinations(page: { AnyView(page($0)) }, home: $home, setUpAgain: { welcoming = true }, openRun: openRun))
                }
            }
            .navigationSplitViewStyle(.balanced)
        }
    }

    /// A message from the first page starts a new chat, unless a task is still running in the current one.
    private func startChat(_ text: String, _ pictures: [Data]) {
        if !chat.running { chat.newConversation() }
        chat.send(text, pictures: pictures)
        show(HomeRoute.chat)
    }

    var body: some View {
        front
        .fullScreenCover(isPresented: $welcoming) { FirstRun(done: { welcoming = false }) }
        .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
        // The Live Activity draws Poki's light too, and reads the choice from the App Group.
        .onChange(of: light, initial: true) { _, now in SharedContainer.defaults.set(now, forKey: PokiLight.key) }
        .task { InProcessProbe.shared.startFromLaunchArguments(model: model) }
        .alert(model.connectionAsk.map { String(localized: "Allow \($0.client) to connect?") } ?? "",
               isPresented: Binding(get: { model.connectionAsk != nil }, set: { if !$0 { model.answerConnection(false) } }),
               presenting: model.connectionAsk) { _ in
            Button("Don’t allow", role: .cancel) { model.answerConnection(false) }
            Button("Allow") { model.answerConnection(true) }
        } message: { ask in
            Text("\(ask.client) is signing in through \(ask.connector) and returns to \(ask.callback), which isn’t on Poki’s list of known agents. Allow it only if you are connecting it yourself right now. It could then see your screen and act on this iPhone.")
        }
        // The update's last step: Poki has to exit, and the owner closes it from the app switcher.
        .alert("Poki will close to finish the update", isPresented: Binding(get: { model.signer.finishNotice }, set: { if !$0 { model.signer.finishNoticeAnswered() } })) {
            Button("OK") { model.signer.finishNoticeAnswered() }
        } message: {
            Text("The update is almost in. Poki will close to finish it; open Poki again afterwards.")
        }
        // Turning on after Off: Poki exits by itself and has to be opened again.
        .alert("Poki restarts to turn on", isPresented: Binding(get: { model.relaunchNotice }, set: { if !$0 { model.relaunchNotice = false } })) {
            Button("Cancel", role: .cancel) { model.relaunchNotice = false }
            Button("Continue") { model.continueRelaunch() }
        } message: {
            Text("Poki closes by itself so agents can see the screen again. Open Poki again afterwards, from the notification or the Home Screen; it turns on when it opens.")
        }
        // Before the first automation after a restart: iOS's passcode screen is next, and expected.
        .alert("Enter your passcode next", isPresented: Binding(get: { model.passcodeHeadsUp }, set: { if !$0 { model.passcodeHeadsUp = false } })) {
            Button("Cancel", role: .cancel) { model.passcodeHeadsUp = false }
            Button("Continue") { model.continueAfterPasscodeHeadsUp() }
        } message: {
            Text("This is the first time Poki starts automation since your iPhone restarted, so iOS will ask for your passcode on the next screen. That screen belongs to iOS: Poki can’t see or read what you enter, and it asks only once until the next restart.")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { model.becameActive(); AskPoki.refresh(); model.startSigner(); model.signer.maintain(); Task { await model.verifyPairing() } } else if phase == .background { model.wentToBackground() }
        }
        // A tap on the Live Activity opens the screen its state is about (ActivityFace.link): the chat,
        // the setup step, or the Activity Log for a problem; `poki://voice` opens the chat too (it
        // never turns on the microphone).
        .onOpenURL { url in
            AppLog.shared.add("app", "opened by link poki://\(url.host() ?? "")")
            // Pairing is not interrupted: it stays on the pairing step, where the PIN is.
            guard !model.pairingUnderWay else { return }
            // A link is the owner going somewhere (a pairing file from Poki Setup, a tap on the Live
            // Activity): the first run steps aside, so what the link opens is not under it.
            welcoming = false
            // A pairing file or a setup link (from Poki Setup on a computer, AirDrop or Files) opens
            // setup at that step, where the result is shown.
            if let step = model.open(link: url) {
                home = NavigationPath([FrontRoute.connection])
                home.append(step)
            } else if url.host() == "setup", !url.absoluteString.contains("relay=") {
                // The Live Activity during setup: Settings › Connection, where the checklist is.
                home = NavigationPath([FrontRoute.connection])
            } else if url.host() == "log" {
                // The Live Activity's problem: what went wrong is in the Activity Log.
                home = NavigationPath([AgentsRoute.activityLog])
            } else {
                if url.host() == "voice" { model.voice.open(url) }
                show(HomeRoute.chat)
            }
        }
        .onAppear(perform: openLaunchScreen)
        .task {
            #if DEBUG
            // Development builds: `-pokiVoiceLink "poki://voice?…"` at launch starts a silent test run.
            if let link = UserDefaults.standard.string(forKey: "pokiVoiceLink"), let url = URL(string: link), url.host() == "voice" {
                show(HomeRoute.chat)
                model.voice.openAtLaunch(url)
            }
            #endif
        }
    }

    /// A page behind Settings › Model or Agents: accounts, voice, the Activity Log.
    private func openAgents(_ route: AgentsRoute) { home.append(route) }

    /// Starts the live voice conversation.
    private func openLiveVoice() {
        // The talk happens where it was started: under Poki on the first page, or as a card in the chat.
        if !model.voice.isOn, model.voice.canTalkLive {
            // Taps that send, pay, delete or call ask for the person's OK, also by notification.
            ApprovalNotice.requestPermission()
            Task { await model.voice.start() }
        }
    }

    /// Setup's checklist: Settings › Connection.
    private func openSetup() {
        home = NavigationPath([FrontRoute.connection])
        columns = .automatic
    }

    /// A run from the Activity Log or the chats: Poki's own chat or an outside agent's session.
    private func openRun(_ id: String) {
        if let session = SessionStore.shared.session(id), session.kind == .poki {
            if session.id != chat.sessionID { chat.restore(session) }
            show(HomeRoute.chat)
        } else {
            show(HomeRoute.session(id))
        }
    }

    /// `-pokiScreen setup` (connect, debug, activity, details, model, voice…) opens that screen at launch,
    /// for the build's screenshots; `-pokiSetupStep 3` opens setup at that step.
    private func openLaunchScreen() {
        let defaults = UserDefaults.standard
        // `-pokiVoiceBridge <address>`: the voice bridge address, from the Mac that launches the app (only a
        // developer connection can pass launch arguments). It never turns on the microphone.
        if let address = defaults.string(forKey: "pokiVoiceBridge") { _ = model.voice.setBridge(address) }
        // A sample conversation (`-pokiChat working`) opens in the chat itself.
        if defaults.string(forKey: "pokiChat") != nil { show(HomeRoute.chat) }
        let screen = defaults.string(forKey: "pokiScreen")
        // The first run, once, for a phone that is not set up yet. Not over a screenshot's screen.
        if screen == "welcome" || (screen == nil && FirstRun.isDue(setUp: model.setupLooksComplete)) { welcoming = true }
        switch screen {
        case "chat", "voice": show(HomeRoute.chat)
        case "session": if let first = SessionStore.shared.ordered.first(where: { $0.kind == .agent || $0.kind == .handoff }) { show(HomeRoute.session(first.id)) }
        case "setup":
            let step = defaults.integer(forKey: "pokiSetupStep")
            home = NavigationPath([FrontRoute.connection])
            if step > 0 { home.append(SetupStep.shown[min(step, SetupStep.shown.count) - 1]) }
        case "connect": home = NavigationPath([FrontRoute.agents])
        case "settings", "details", "status": home = NavigationPath([FrontRoute.settings])
        case "debug": home = NavigationPath([SettingsRoute.diagnostics])
        case "activity":
            home = NavigationPath([SettingsRoute.diagnostics])
            home.append(SettingsRoute.activityPreview)
        case "connector":
            if let first = model.identity.secrets.first {
                home = NavigationPath([FrontRoute.agents])
                home.append(SettingsRoute.connector(first))
            }
        case "chats": frontPage = .chats; columns = .all
        case "appearance": home = NavigationPath([FrontRoute.appearance])
        case "model": openAgents(.accounts)
        case "steps": openAgents(.activityLog)
        default: break
        }
    }
}

/// Every page the front pushes, the same on iPhone's stack and in a wide window's detail column.
private struct FrontDestinations: ViewModifier {
    var page: (RootView.HomeRoute) -> AnyView
    @Binding var home: NavigationPath
    var setUpAgain: () -> Void
    var openRun: (String) -> Void

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: RootView.HomeRoute.self) { page($0) }
            .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0).paperPage() }
            .navigationDestination(for: FrontRoute.self) { route in
                switch route {
                case .settings: FrontSettings()
                case .connection: ConnectionPage(setUpAgain: setUpAgain)
                case .agents: AgentsList(push: { home.append($0) }).paperPage()
                case .appearance: AppearancePage()
                case .signing: SigningPage()
                }
            }
            .navigationDestination(for: AgentsRoute.self) { route in
                switch route {
                case .accounts: ModelSettingsView(showsVoice: true).paperPage()
                case .voice: VoiceView(embedded: true).paperPage()
                case .activityLog: ActionLogView(openSession: openRun).paperPage()
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                SettingsDestination(route: route, push: { home.append($0) }, pop: { if !home.isEmpty { home.removeLast() } }).paperPage()
            }
            .navigationDestination(for: SetupRoute.self) { _ in AdvancedView(push: { home.append($0) }).paperPage() }
    }
}
