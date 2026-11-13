import PokiCore
import SwiftUI

/// The two pages of the iPhone front.
enum FrontPage: Hashable { case newChat, chats }

/// iPhone's front: a new chat and, one swipe to the left, the chats. Poki's window belongs to both. As
/// the pages turn it draws in from the new chat's window to the New chat button on the chats page, and
/// it opens out again on the way back, following the finger.
struct FrontPager<New: View, Chats: View>: View {
    @Binding var page: FrontPage?
    /// Poki's pose in the window.
    var pose: String
    @ViewBuilder var newChat: New
    @ViewBuilder var chats: Chats
    /// 0 with the new chat in front, 1 with the chats.
    @State private var turned: CGFloat = 0
    @State private var slots: [WindowSlot: CGRect] = [:]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                newChat.coordinateSpace(.named(WindowSlot.space)).containerRelativeFrame(.horizontal).id(FrontPage.newChat)
                chats.coordinateSpace(.named(WindowSlot.space)).containerRelativeFrame(.horizontal).id(FrontPage.chats)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $page)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x / max(1, $0.containerSize.width) } action: { _, now in
            turned = min(1, max(0, now))
        }
        .onPreferenceChange(WindowSlot.Key.self) { slots = $0 }
        .environment(\.frontTurned, turned)
        .overlay(alignment: .topLeading) {
            if let from = slots[.window], let to = slots[.button] {
                // Smooth at both ends, so the window leaves and lands gently under a steady finger.
                let t = turned * turned * (3 - 2 * turned)
                let rect = CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
                                  width: from.width + (to.width - from.width) * t, height: from.height + (to.height - from.height) * t)
                SkyWindow(pose: pose, bear: 0.36 + 0.56 * t, radius: 44 + (rect.height / 2 - 44) * t)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    // The sky gives way to the black button at the end; Poki stays (the button draws it).
                    .opacity(1 - max(0, (turned - 0.82) / 0.18))
                    .allowsHitTesting(false)
            }
        }
        .background(Paper.page)
    }
}

/// Where Poki's window is on a page: the new chat's window, and Poki's place on the New chat button.
enum WindowSlot: Hashable {
    case window, button
    static let space = "front page"

    struct Key: PreferenceKey {
        static let defaultValue: [WindowSlot: CGRect] = [:]
        static func reduce(value: inout [WindowSlot: CGRect], nextValue: () -> [WindowSlot: CGRect]) { value.merge(nextValue()) { $1 } }
    }
}

extension View {
    func windowSlot(_ slot: WindowSlot) -> some View {
        background(GeometryReader { geo in Color.clear.preference(key: WindowSlot.Key.self, value: [slot: geo.frame(in: .named(WindowSlot.space))]) })
    }
}

extension EnvironmentValues {
    /// How far the front has turned from the new chat (0) to the chats (1). 1 where there is no pager.
    @Entry var frontTurned: CGFloat = 1
}

/// Poki's first page: a new chat. Poki in its window, a greeting, two things to ask, and the message
/// field. The chats are one swipe to the left on iPhone, and beside this page in a wide window.
struct NewChatPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    /// Starts a new chat with this message and these pictures, and opens it.
    var start: (String, [Data]) -> Void
    /// The way to the chats: the next page on iPhone, the sidebar in a wide window.
    var openChats: () -> Void
    var chatsSymbol = "text.alignright"
    /// In the pager the window is the pager's, shared with the chats page; alone, the page draws its own.
    var paged = true
    var openVoice: () -> Void
    var openModel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: openChats) {
                Image(systemName: chatsSymbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Paper.ink2).frame(width: 44, height: 44).contentShape(.rect)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .accessibilityLabel(Text("Chats"))
            // The window gives way first when the keyboard needs the room.
            Group {
                if paged { Color.clear.windowSlot(.window) } else { SkyWindow(pose: model.voice.isLive ? TalkWords.pose(model.voice) : chat.running ? "phone" : "rest") }
            }
            .aspectRatio(1, contentMode: .fit).frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .layoutPriority(-1)
            if model.voice.isLive {
                // A talk: who has the word and what is said, where the greeting was.
                TalkWords(voice: model.voice).padding(.horizontal, 24).padding(.top, 26).transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.greeting(at: Date())).foregroundStyle(Paper.ink)
                    Text("What should Poki do?").foregroundStyle(Paper.ink2)
                }
                .font(Paper.title).tracking(Paper.titleTracking)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 30)
                .transition(.opacity)
            }
            Spacer(minLength: 12)
            if !chat.running, !model.voice.isLive {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(suggestions, id: \.self) { text in
                        Button { start(text, []) } label: {
                            Text(verbatim: text).font(.system(size: 15)).foregroundStyle(Paper.chipInk).lineLimit(1)
                                .padding(.horizontal, 16).frame(height: 40)
                                .background(Paper.chip, in: Capsule())
                                .overlay(Capsule().strokeBorder(Paper.chipInk.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 6)
            }
            ComposerInputView(running: chat.running, send: { start($0, []) }, sendPictures: start, stop: chat.stop, openVoice: openVoice,
                              openModel: openModel, newConversation: chat.newConversation)
        }
        // A column in a wide window, not a page stretched across it.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Paper.page)
        .animation(.snappy, value: model.voice.isLive)
        .hidesKeyboardOnTap()
    }

    /// Two things to ask: the owner's saved routines first, since those are what Poki already knows how to do.
    private var suggestions: [String] {
        let saved = RoutineStore.shared.routines.prefix(2).map(\.name)
        let starters = [String(localized: "Reorder my usual lunch"), String(localized: "What’s on this afternoon?")]
        return Array((saved + starters).prefix(2))
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: String(localized: "Good morning.")
        case 12..<18: String(localized: "Good afternoon.")
        default: String(localized: "Good evening.")
        }
    }
}

/// Every chat, one swipe from the first page (a sidebar in a wide window): Poki's own conversations and
/// the sessions of outside agents, by day. Settings is behind the gear; the button with Poki on it goes
/// back to a new chat.
struct ChatsPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    @Environment(\.frontTurned) private var turned
    var open: (SavedSession) -> Void
    var newChat: () -> Void
    var openSettings: () -> Void
    var openSetup: () -> Void
    var openModel: () -> Void
    var openAgents: () -> Void
    @State private var query = ""
    @State private var renaming: SavedSession?
    @State private var newName = ""

    private var store: SessionStore { SessionStore.shared }

    private var shown: [SavedSession] {
        let words = query.trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? store.ordered : store.ordered.filter { [$0.name, $0.title, $0.lastLine, $0.client ?? ""].contains { $0.localizedCaseInsensitiveContains(words) } }
    }

    /// The chats by day, newest day first.
    private var days: [(day: Date, sessions: [SavedSession])] {
        Dictionary(grouping: shown) { Calendar.current.startOfDay(for: $0.updated) }
            .map { (day: $0.key, sessions: $0.value) }
            .sorted { $0.day > $1.day }
    }

    /// The first setup item still open, named on the card that leads to it.
    private var openStep: SetupStep? { SetupStep.shown.first { !model.isDone($0) } }

    /// What keeps Poki from working fully, most urgent first, and the page that fixes it: setup, then
    /// no account to think with, then a relay agents can't reach.
    private var trouble: (title: String, detail: String, fix: () -> Void)? {
        if !model.setupLooksComplete {
            let detail = openStep.map { String(localized: "\(ActivityWords.local($0.activityTitle)) is still to do. Fix it") } ?? String(localized: "Setup isn’t finished. Fix it")
            return (String(localized: "Poki can’t use this iPhone"), detail, openSetup)
        }
        if !ModelKeys.hasUsableKey {
            return (String(localized: "Poki has nothing to think with"), String(localized: "Add an account in Model"), openModel)
        }
        if case .offline = model.relayStatus {
            return (String(localized: "Agents can’t reach this iPhone"), String(localized: "The relay is offline. Check it"), openAgents)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: openSettings) {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Paper.ink2).frame(width: 44, height: 44).contentShape(.rect)
                    .overlay(alignment: .topTrailing) {
                        // Something in Settings needs a look: the same test as the card below.
                        if trouble != nil { Circle().fill(Paper.ink).frame(width: 7, height: 7).offset(x: -9, y: 10) }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .accessibilityLabel(Text("Settings"))
            Text("Chats").font(.system(size: 34, weight: .bold)).tracking(-0.75).foregroundStyle(Paper.ink)
                .padding(.horizontal, 24).padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Paper.ink2)
                TextField("Search chats", text: $query).font(.system(size: 17)).submitLabel(.search).autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(Paper.fill, in: Capsule())
            .padding(.horizontal, 16)
            List {
                if let trouble {
                    Button(action: trouble.fix) {
                        HStack(spacing: 12) {
                            PaperMark(kind: .warn)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: trouble.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink)
                                Text(verbatim: trouble.detail).font(Paper.note).foregroundStyle(Paper.ink2).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Paper.ink)
                        }
                        .padding(.horizontal, 14).frame(minHeight: 63)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Paper.ink, lineWidth: 1.5))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .plainRow(top: 24)
                }
                if let warning = ExpiryWarning(expiry: model.signer.expiry) { ExpiryWarningSection(warning: warning) }
                ForEach(days, id: \.day) { day in
                    Text(verbatim: Self.title(for: day.day)).font(Paper.header).foregroundStyle(Paper.ink2)
                        .plainRow(top: 30)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(day.sessions.enumerated()), id: \.element.id) { i, session in
                        Button { open(session) } label: { ChatRow(session: session) }
                            .buttonStyle(.plain)
                            .plainRow(top: i == 0 ? 12 : 20)
                            .swipeActions {
                                if !session.live {
                                    Button(role: .destructive) { store.delete(session.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                                Button { newName = session.name; renaming = session } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(Paper.ink2)
                            }
                            .contextMenu {
                                Button { newName = session.name; renaming = session } label: { Label("Rename", systemImage: "pencil") }
                                if !session.live {
                                    Button(role: .destructive) { store.delete(session.id) } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
                if store.ordered.isEmpty {
                    Text("No chats yet. Write or talk to start one.").font(.system(size: 15)).foregroundStyle(Paper.ink2)
                        .plainRow(top: 30)
                } else if shown.isEmpty {
                    Text("No chat has “\(query)” in it.").font(.system(size: 15)).foregroundStyle(Paper.ink2)
                        .plainRow(top: 30)
                }
                // Room for the button, so the last chat is never under it.
                Color.clear.frame(height: 96).plainRow(top: 0)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .environment(\.defaultMinListRowHeight, 1)
        }
        .background(Paper.page)
        .overlay(alignment: .bottomTrailing) {
            Button(action: newChat) {
                HStack(spacing: 8) {
                    // Poki's place on the button: the window lands here as the pages turn.
                    PokiBear(pose: "phone").frame(width: 56, height: 56)
                        .opacity(Double(max(0, (turned - 0.82) / 0.18)))
                        .windowSlot(.button)
                    Text("New chat").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Paper.page)
                .padding(.leading, 8).padding(.trailing, 24).frame(height: 64)
                .background(Paper.ink, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(.trailing, 20).padding(.bottom, 12)
            .accessibilityLabel(Text("New chat"))
        }
        .alert("Rename session", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let session = renaming { store.rename(session.id, to: newName) }
                renaming = nil
            }
        }
    }

    /// "Today", "Yesterday", "Monday", then the date.
    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

/// One chat in the list: its name and its last line. A session an outside agent is running shows that
/// agent's mark in front of the line, and a dot while it is live.
private struct ChatRow: View {
    var session: SavedSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(verbatim: session.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Paper.ink).lineLimit(1).frame(height: 24)
                if session.live { Circle().fill(Paper.ink).frame(width: 6, height: 6).accessibilityLabel(Text("Live")) }
            }
            HStack(spacing: 6) {
                if session.kind != .poki, let client = session.client { AgentBadge(name: client, size: 16) }
                Text(verbatim: session.lastLine).font(.system(size: 15)).foregroundStyle(Paper.ink2).lineLimit(1).frame(height: 21)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

private extension View {
    /// A row of the chats list as the page lays it out itself: no separators, the page's own margins.
    func plainRow(top: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 24, bottom: 0, trailing: 24))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
