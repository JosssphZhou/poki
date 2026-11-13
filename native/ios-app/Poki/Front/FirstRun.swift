import AVFoundation
import SwiftUI

/// The first run: Poki says what it is, the owner picks its light, and then the three things it needs
/// (this iPhone, a model, the microphone), each of which can wait. It is shown once, on a phone that is
/// not set up yet, and again from Settings › Connection › Set up again. The window is the stage: it fills
/// the top of the page and draws up when a step needs the room. The setup items and the accounts are the
/// app's own pages (`SetupStepPage`, `ModelSettingsView`); this puts them in an order.
struct FirstRun: View {
    static let key = "pokiWelcomed"

    /// Whether to show it now. A phone that is already set up has been through setup before this
    /// existed, so it is marked as welcomed without the pages. A scripted run has nobody to go through
    /// them: the unit tests' host, and the probes and sample screens CI starts with launch arguments.
    static func isDue(setUp: Bool) -> Bool {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil { return false }
        if ["pokiInProcess", "pokiChat", "pokiSample", "pokiSessions", "pokiVoiceLink", "pokiActivityDemo"].contains(where: { defaults.object(forKey: $0) != nil }) { return false }
        if defaults.bool(forKey: key) { return false }
        if setUp { defaults.set(true, forKey: key); return false }
        return true
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var still
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue
    var done: () -> Void

    enum Page: Int, CaseIterable { case hello, light, phone, model, voice, ready }
    private enum Push: Hashable { case accounts }

    @State private var page = Page.hello
    @State private var path = NavigationPath()
    @State private var hasModel = ModelKeys.hasUsableKey
    @State private var micAllowed = AVAudioApplication.shared.recordPermission == .granted

    /// The first setup item still open, and its place in the list.
    private var nextStep: (number: Int, step: SetupStep)? {
        SetupStep.shown.enumerated().first { !model.isDone($0.element) }.map { ($0.offset + 1, $0.element) }
    }
    /// The pages where Poki is the subject get the large window.
    private var large: Bool { page == .hello || page == .light || page == .ready }

    private var pose: String {
        switch page {
        case .hello: "wave"
        case .light: "rest"
        case .phone: "search"
        case .model: "think"
        case .voice: "listen"
        case .ready: model.setupLooksComplete ? "happy" : "rest"
        }
    }

    private var title: String {
        switch page {
        case .hello: String(localized: "Hi, I’m Poki.")
        case .light: String(localized: "Pick my light")
        case .phone: String(localized: "Let me use this iPhone")
        case .model: String(localized: "Choose what I think with")
        case .voice: String(localized: "Talk to me")
        case .ready: model.setupLooksComplete ? String(localized: "I’m ready") : String(localized: "Almost there")
        }
    }

    private var words: String {
        switch page {
        case .hello: return String(localized: "I use your iPhone for you. Write to me or just talk, then watch me do it.")
        case .light: return String(localized: "It is the one colour in the app. You can change it later in Settings.")
        case .phone:
            let count = NumberFormatter.localizedString(from: SetupStep.shown.count as NSNumber, number: .spellOut).localizedCapitalized
            return String(localized: "\(count) things to switch on, once. I check each one as you go.")
        case .model: return String(localized: "Sign in or add a key. You can switch later.")
        case .voice: return String(localized: "You can talk to me instead of typing. I need the microphone for that.")
        case .ready:
            return model.setupLooksComplete
                ? String(localized: "Try “Reorder my usual lunch”, or tap the black button and say it.")
                : String(localized: "You can look around now. I can use this iPhone once setup is finished, in Settings › Connection.")
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geo in
                let full = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                VStack(spacing: 0) {
                    // The stage: Poki's window from edge to edge, under the status bar.
                    SkyWindow(pose: pose, bear: large ? 0.42 : 0.3, radius: 0)
                        .frame(height: full * (large ? 0.52 : 0.29))
                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 44, bottomTrailingRadius: 44, style: .continuous))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                ForEach(Page.allCases, id: \.self) { each in
                                    Capsule().fill(each == page ? Paper.ink : Paper.line).frame(width: each == page ? 18 : 6, height: 6)
                                }
                            }
                            .padding(.top, 26)
                            .accessibilityElement()
                            .accessibilityLabel(Text("Step \(page.rawValue + 1) of \(Page.allCases.count)"))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(verbatim: title).font(Paper.title).tracking(Paper.titleTracking).foregroundStyle(Paper.ink)
                                    .accessibilityAddTraits(.isHeader)
                                Text(verbatim: words).font(.system(size: 17)).foregroundStyle(Paper.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                detail.padding(.top, 10)
                            }
                            .padding(.top, 18)
                            .id(page)
                            .transition(still ? .opacity : .asymmetric(insertion: .offset(y: 10).combined(with: .opacity), removal: .opacity))
                        }
                        .padding(.horizontal, 24).padding(.bottom, 12)
                        .frame(maxWidth: 560, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    buttons
                }
                .ignoresSafeArea(edges: .top)
            }
            .background(Paper.page)
            // An empty bar in the dark scheme: the status bar reads white over the sky, and Back sits on it.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if page != .hello {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { go(Page(rawValue: page.rawValue - 1) ?? .hello) } label: { Image(systemName: "chevron.left") }
                            .tint(.white)
                            .accessibilityLabel(Text("Back"))
                    }
                }
            }
            .navigationDestination(for: SetupStep.self) { SetupStepPage(step: $0).paperPage() }
            .navigationDestination(for: Push.self) { _ in ModelSettingsView().paperPage() }
            // Back from a setup item or the accounts: what changed there shows here.
            .onChange(of: path.count) { _, _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in refresh() }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .light:
            LightSwatches(light: $light).padding(.top, 6)
        case .phone:
            PaperRows {
                ForEach(Array(SetupStep.shown.enumerated()), id: \.element) { i, step in
                    let ticked = model.isDone(step)
                    NavigationLink(value: step) {
                        HStack(spacing: 12) {
                            PaperMark(kind: ticked ? .done : .number(i + 1))
                                .accessibilityLabel(Text(ticked ? "Done" : "To do"))
                            Text(step.pageTitle).font(Paper.row).foregroundStyle(Paper.ink)
                            Spacer(minLength: 8)
                            if ticked { Text("Done").font(Paper.value).foregroundStyle(Paper.ink2) }
                            else if nextStep?.step == step { Text("Next").font(Paper.value).foregroundStyle(Paper.ink2) }
                        }
                        .frame(minHeight: 54).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .model:
            PaperRows {
                ForEach(Self.firstProviders) { provider in
                    Button { path.append(Push.accounts) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: provider.name).font(Paper.row).foregroundStyle(Paper.ink)
                                if provider.signsIn { Text("Sign in with your account").font(Paper.note).foregroundStyle(Paper.ink2) }
                            }
                            Spacer()
                            if ModelAccounts.isSetUp(provider) {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink)
                                    .accessibilityLabel(Text("Added"))
                            }
                        }
                        .frame(minHeight: 54).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Button { path.append(Push.accounts) } label: {
                    PaperRow(String(localized: "More"), value: "\(ModelProvider.allCases.count - Self.firstProviders.count)")
                }
                .buttonStyle(.plain)
            }
            // `hasModel` is read so the ticks follow the accounts page.
            .id(hasModel)
        default:
            EmptyView()
        }
    }

    /// The three named on the page; the rest are behind More.
    private static let firstProviders: [ModelProvider] = [.chatgpt, .anthropic, .openai]

    /// The one thing to press, in ink, and under it the way past when the page asks for something.
    private var buttons: some View {
        VStack(spacing: 2) {
            Button(action: primary) { Text(verbatim: primaryWord) }.buttonStyle(InkButtonStyle())
            if let later {
                Button { go(next) } label: {
                    Text(verbatim: later).font(.system(size: 16)).foregroundStyle(Paper.ink2)
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(.rect)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var primaryWord: String {
        switch page {
        case .hello: String(localized: "Get started")
        case .phone: nextStep.map { String(localized: "Continue with step \($0.number)") } ?? String(localized: "Continue")
        case .voice: micAllowed ? String(localized: "Continue") : String(localized: "Allow microphone")
        case .ready: String(localized: "Start")
        default: String(localized: "Continue")
        }
    }

    /// The words of the way past, on the pages that ask for something not yet done.
    private var later: String? {
        switch page {
        case .phone where nextStep != nil, .model where !hasModel, .voice where !micAllowed: String(localized: "Not now")
        default: nil
        }
    }

    private var next: Page { Page(rawValue: page.rawValue + 1) ?? .ready }

    private func primary() {
        switch page {
        case .phone:
            if let nextStep { path.append(nextStep.step) } else { go(next) }
        case .model:
            if hasModel { go(next) } else { path.append(Push.accounts) }
        case .voice:
            guard !micAllowed else { return go(next) }
            Task {
                micAllowed = await AVAudioApplication.requestRecordPermission()
                go(next)
            }
        case .ready: finish()
        default: go(next)
        }
    }

    private func go(_ to: Page) {
        withAnimation(still ? nil : .spring(duration: 0.5, bounce: 0.12)) { page = to }
    }

    private func refresh() {
        hasModel = ModelKeys.hasUsableKey
        micAllowed = AVAudioApplication.shared.recordPermission == .granted
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.key)
        done()
    }
}
