import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The chat page (ESP-171 boards "M Chat empty", "M Chat working", "M Chat approved"): Poki's picture and
/// name on top, the bubbles, and the message field. Approvals happen in the Dynamic Island, which iOS
/// hides while Poki is in front, so the chat also shows the waiting approval's card.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(ChatModel.self) private var chat
    var openDetails: () -> Void
    var openVoice: () -> Void
    var openSetup: () -> Void
    var openModel: () -> Void
    /// Back to the Sessions list, when the chat was opened from it.
    var back: (() -> Void)? = nil

    private var voice: VoiceModel { model.voice }
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        ChatTranscript(entries: chat.entries, typing: chat.awaitingModel, canRetry: chat.canRetry, retry: chat.retry,
                       sessionID: chat.sessionID, working: chat.running) {
            if needsSetup { SetupBubble(paired: model.pairingPath != nil, openSetup: openSetup) }
            if !ApprovalClassifier.isOn, let approval = model.approvals.first {
                ApprovalCard(approval: approval) { approved in model.resolve(approval, approved: approved) }
            }
            LiveVoiceTranscript(voice: voice)
        }
        // The header and the message field are insets of the conversation, so the field sits right on
        // the keyboard (or the home indicator) and the bubbles scroll under both, as in Messages.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerInputView(running: chat.running, send: chat.send, sendPictures: chat.send, stop: chat.stop, openVoice: openVoice,
                              openModel: openModel, newConversation: chat.newConversation)
        }
        .background(Paper.page)
        .toolbarBackground(Paper.page, for: .navigationBar)
        // The conversation's name (the one Poki gave it, or the owner's) is the title; More renames it.
        .navigationTitle(Text(verbatim: SessionStore.shared.session(chat.sessionID)?.name ?? "Poki"))
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename conversation", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SessionStore.shared.rename(chat.sessionID, to: newName) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New conversation", systemImage: "square.and.pencil", action: chat.newConversation).disabled(chat.running)
                    if SessionStore.shared.session(chat.sessionID) != nil {
                        Button("Rename", systemImage: "pencil") { newName = SessionStore.shared.session(chat.sessionID)?.name ?? ""; renaming = true }
                    }
                    Menu("Chat model: \(ModelKeys.selectedModelName)", systemImage: "bubble.left.and.text.bubble.right") {
                        ForEach(ModelProvider.allCases.filter { ModelAccounts.isSetUp($0) && ModelAccounts.canChat($0) }) { provider in
                            Section(provider.name) {
                                ForEach(ModelCatalog.available(provider)) { choice in
                                    Button {
                                        ModelKeys.selectedProvider = provider
                                        ModelKeys.selectedModel = choice.id
                                        ModelKeys.saved += 1
                                    } label: {
                                        if ModelKeys.selectedProvider == provider && ModelKeys.selectedModel == choice.id { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                                    }
                                }
                            }
                        }
                    }
                    if VoiceDirect.apiKey != nil {
                        Menu("Voice model: \(VoiceDirect.model)", systemImage: "waveform") {
                            ForEach(ModelCatalog.voiceAvailable) { choice in
                                Button { ModelCatalog.voiceModel = choice.id } label: {
                                    if VoiceDirect.model == choice.id { Label(choice.name, systemImage: "checkmark") } else { Text(choice.name) }
                                }
                            }
                        }
                    }
                    Button("Accounts", systemImage: "person.crop.circle", action: openModel)
                    Button("Status and Settings", systemImage: "gearshape", action: openDetails)
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(Text("More"))
            }
        }
        // Full screen on iPhone; beside the chats in a wide window.
    }

    /// Setup is not finished (nothing paired yet, or a step left after pairing, such as UI Automation):
    /// the chat says so, one tap from setup, as the old Home's Setup row did.
    private var needsSetup: Bool { (model.pairingPath == nil || model.setupStepsLeft) && !model.sessionOn && !chat.running && !chat.isSample }
}

/// The bubbles of one conversation: an in-app chat, a hand-off from an outside agent, or an outside
/// agent's own steps (grey lines). Used by the chat and by a saved session.
struct ChatTranscript<Footer: View>: View {
    var entries: [ChatEntry]
    var typing = false
    var canRetry = false
    var retry: () -> Void = {}
    /// The session these entries belong to, so a phone use can list its actions from the Activity Log.
    var sessionID: String? = nil
    /// A task is under way: its record is not drawn until it has ended.
    var working = false
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    row(entry, at: i).id(entry.id)
                }
                if typing {
                    HStack { TypingBubble(); Spacer(minLength: .messageInsetPadding) }
                        .padding(.top, 4).transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomLeading)))
                }
                if canRetry {
                    Button(action: retry) {
                        Text("Try again").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink)
                            .padding(.horizontal, 18).frame(height: 40)
                            .overlay(Capsule().strokeBorder(Paper.ink, lineWidth: 1.5)).contentShape(.capsule)
                    }
                    .buttonStyle(PressStyle())
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4).padding(.top, 4).padding(.bottom, 6)
                }
                footer()
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 10)
            .frame(maxWidth: .infinity)
            .hidesKeyboardOnTap()
            .animation(PlanMotion.enter, value: entries)
            .animation(.easeOut(duration: 0.2), value: typing)
        }
        // Opens at the newest message, keeps a short chat at the bottom, and follows new lines (the
        // live voice transcript grows below the messages) while the content itself scrolls freely.
        // A frame fixed to the screen's height here cut off everything above it.
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .scrollDismissesKeyboard(.interactively)
        .onAppear { ActionLog.shared.load() }
    }

    @ViewBuilder private func row(_ entry: ChatEntry, at i: Int) -> some View {
        switch entry.kind {
        case .time:
            // A chat is a record of what was asked and done; the list of chats gives the day.
            EmptyView()
        case .pictures(let names):
            PictureBubbles(names: names)
                .padding(.top, startsRun(i) ? 10 : 0).padding(.bottom, 2)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .you(let text, let delivered):
            let last = isLast(i, poki: false)
            VStack(alignment: .trailing, spacing: 4) {
                // Pictures sent alone have no words to draw.
                if !text.isEmpty { MessageBubble(direction: .outgoing, text: text, tail: last) }
            }
            .padding(.top, startsRun(i) ? 10 : 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .request(let text, let from):
            VStack(alignment: .trailing, spacing: 2) {
                if startsRun(i) || i == 0 {
                    Text(verbatim: from).font(.system(size: 11, weight: .medium)).foregroundStyle(ChatColor.secondary).padding(.horizontal, 14)
                }
                MessageBubble(direction: .outgoing, text: text, tail: isLast(i, poki: false))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, startsRun(i) ? 10 : 0)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .poki(let text):
            MessageBubble(direction: .incoming, text: text, tail: isLast(i, poki: true))
                .padding(.top, startsRun(i) ? 10 : 0)
                .transition(PlanMotion.stepTransition)
        case .plan(let steps):
            // Nothing is drawn while Poki uses the phone: the person is in the other app. Once the
            // task has ended, the chat keeps one card of it.
            if !(working && isLastPlan(i)) {
                UseCard(steps: steps, actions: actions(for: i))
                    .padding(.top, startsRun(i) ? 12 : 6).padding(.bottom, 8)
                    .transition(.opacity)
            }
        case .note(let note):
            NoteLine(note: note)
        case .step(let text, let ok):
            StepLine(text: text, ok: ok)
        }
    }

    private func isLastPlan(_ i: Int) -> Bool {
        !entries[(i + 1)...].contains { if case .plan = $0.kind { true } else { false } }
    }

    /// The actions of the phone use whose plan is at `i`: the session's entries in the Activity Log from
    /// the owner's message before it up to their next one.
    private func actions(for i: Int) -> [ActionLog.Entry] {
        guard let sessionID else { return [] }
        func isYou(_ entry: ChatEntry) -> Bool { if case .you = entry.kind { true } else { false } }
        let start = entries[..<i].last(where: isYou)?.at ?? entries[i].at
        let end = entries[(i + 1)...].first(where: isYou)?.at ?? .distantFuture
        return ActionLog.shared.entries.filter { $0.session == sessionID && $0.at >= start && $0.at < end }
    }

    /// The last bubble from that side in the conversation has the small corner (the boards).
    private func isLast(_ i: Int, poki: Bool) -> Bool {
        !entries[(i + 1)...].contains { entry in
            switch entry.kind {
            case .poki, .plan: poki
            case .you, .request, .pictures: !poki
            default: false
            }
        }
    }

    /// A bubble after the other side's (or the time) leaves 10 pt more.
    private func startsRun(_ i: Int) -> Bool {
        guard i > 0 else { return false }
        let mine = entries[i].isPoki
        for entry in entries[..<i].reversed() {
            switch entry.kind {
            case .note: continue
            case .time, .step: return true
            default: return entry.isPoki != mine
            }
        }
        return false
    }
}

extension ChatTranscript where Footer == EmptyView {
    init(entries: [ChatEntry]) { self.init(entries: entries, footer: { EmptyView() }) }
}

/// "Today 9:41 AM", "Yesterday 6:02 PM", "Monday 8:15 AM", "Oct 3, 8:15 AM", as Messages writes them.
enum ChatTime {
    static func header(_ date: Date) -> AttributedString {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        let day: String
        if calendar.isDateInToday(date) { day = String(localized: "Today") }
        else if calendar.isDateInYesterday(date) { day = String(localized: "Yesterday") }
        else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            day = date.formatted(.dateTime.weekday(.wide))
        } else {
            day = date.formatted(.dateTime.month(.abbreviated).day())
        }
        var bold = AttributedString(day)
        bold.font = .system(size: 12, weight: .semibold)
        return bold + AttributedString(" \(time)")
    }

    /// The Sessions list's right-hand time: "9:41 AM", "Yesterday", "Monday", "10/3/26".
    static func row(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(date: .numeric, time: .omitted)
    }
}

/// Three dots that rise in turn: the model is working on its answer.
struct TypingBubble: View {
    @Environment(\.accessibilityReduceMotion) private var still
    /// Dot i's height in 0...1 at time t. Typed step by step: as one expression inside the view
    /// builder it can exceed the type checker's time limit on a busy CI runner.
    static func phase(_ t: Double, _ i: Int) -> Double {
        let angle: Double = t * 2 * Double.pi / 1.2 - Double(i) * 0.9
        let wave: Double = sin(angle)
        return (wave + 1) / 2
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    let phase = TypingBubble.phase(t, i)
                    Circle().fill(ChatColor.secondary.opacity(0.45 + 0.45 * phase)).frame(width: 8, height: 8).offset(y: still ? 0 : -3 * phase)
                }
            }
            .padding(.vertical, 13).padding(.horizontal, 15)
            .background(ChatColor.incoming, in: UnevenRoundedRectangle(topLeadingRadius: .cornerRadius, bottomLeadingRadius: .tailRadius,
                                                                       bottomTrailingRadius: .cornerRadius, topTrailingRadius: .cornerRadius, style: .continuous))
        }
        .accessibilityLabel(Text("Poki is typing"))
    }
}

/// An outside agent's own step: one grey line, centred, ticked when it went through.
private struct StepLine: View {
    var text: String
    var ok: Bool?
    var body: some View {
        HStack(spacing: 5) {
            switch ok {
            case true?: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Paper.ink2)
            case false?: Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Paper.ink)
            case nil: ProgressView().controlSize(.mini)
            }
            Text(text).lineLimit(2)
        }
        .font(.system(size: 12)).foregroundStyle(ChatColor.secondary)
        .multilineTextAlignment(.center)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

// MARK: Header


/// Poki, small and round, where a list says who did something: its resting picture on the quiet fill.
struct PokiAvatar: View {
    var size: CGFloat
    var body: some View {
        Image("Pose-rest").resizable().scaledToFit().padding(size * 0.1)
            .frame(width: size, height: size)
            .background(Paper.fill, in: .circle)
            .accessibilityHidden(true)
    }
}

// MARK: Plan

/// One grey line about an approval, centred under the steps.
private struct NoteLine: View {
    var note: ChatNote
    var body: some View {
        HStack(spacing: 6) {
            switch note {
            case .waiting:
                // The Dynamic Island, small.
                // The island, small: black in both schemes, with an edge so it shows on the dark page.
                Capsule().fill(Color(hex: 0x1C1C1E)).overlay(Capsule().strokeBorder(Paper.line, lineWidth: 1)).frame(width: 22, height: 8)
                Text("Waiting for your approval")
            case .approved(let at):
                Text("You allowed this at \(at.formatted(date: .omitted, time: .shortened))")
            case .declined:
                Text("Not allowed, so Poki skipped that step")
            case .expired:
                Text("The approval ran out, so Poki skipped that step")
            case .problem(let text):
                Text(text)
            case .modelChecking:
                ProgressView().controlSize(.mini)
                Text("The model is checking this step")
            case .modelApproved(let why):
                Text(why.isEmpty ? String(localized: "Approved by model") : String(localized: "Approved by model: \(why)"))
            case .modelDeclined(let why):
                Text(why.isEmpty ? String(localized: "Not approved by model. Say yes in the chat to let it through.") : String(localized: "Not approved by model: \(why). Say yes in the chat to let it through."))
            }
        }
        // A quiet line on Poki's side of the page, in ink like everything else.
        .font(Paper.note).foregroundStyle(Paper.ink2)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 4).padding(.top, 2).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

/// Before setup, or with a step left: Poki says so, and the bubble opens setup.
private struct SetupBubble: View {
    var paired: Bool
    var openSetup: () -> Void
    var body: some View {
        HStack {
            Button(action: openSetup) {
                HStack(spacing: 4) {
                    Text(paired ? "Finish setting up this iPhone." : "First, set up this iPhone. About 5 minutes.")
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .font(.system(size: 17, weight: .medium)).foregroundStyle(Paper.ink)
                .padding(.vertical, .messageVerticalPadding).padding(.horizontal, 14)
                .background(ChatColor.incoming, in: UnevenRoundedRectangle(topLeadingRadius: .cornerRadius, bottomLeadingRadius: .tailRadius,
                                                                            bottomTrailingRadius: .cornerRadius, topTrailingRadius: .cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: .messageInsetPadding)
        }
        .padding(.top, 4)
    }
}

// MARK: Composer

// ComposerInputView started from GetStream/swiftui-iMessage-clone (commit df114b4,
// iMessageClone/MessageList/View/Composer/ComposerInputView.swift, by Stefan Blos; no licence file in
// the repository), with the plus button in front from exyte/Chat (commit f382a14,
// Sources/ExyteChat/Views/InputView/InputView.swift, Copyright (c) 2019 exyte, MIT License). Now: a
// Liquid Glass field on iOS 26 (a bar material before it), dictation that writes into the field as you
// speak, the live voice button, and a stop button while a task runs.
struct ComposerInputView: View {
    @Environment(AppModel.self) private var model
    var running: Bool
    var send: (String) -> Void
    /// Sends words with pictures. Without it the field takes no attachments (an outside agent's session).
    var sendPictures: ((String, [Data]) -> Void)? = nil
    var stop: () -> Void
    /// Starts the live voice conversation.
    var openVoice: () -> Void
    var openModel: () -> Void
    var newConversation: () -> Void
    @State private var input = ""
    @State private var dictation = FieldDictation()
    @FocusState private var focused: Bool
    @State private var liveNote: String?
    @State private var drafts: [PictureDraft] = []
    @State private var picked: [PhotosPickerItem] = []
    @State private var pickingPhotos = false
    @State private var pickingFiles = false
    @State private var speaking = false
    @State private var talkStarted: Date?
    @AppStorage(PokiLight.key) private var lightChoice = PokiLight.firstLight.rawValue
    private var light: PokiLight { PokiLight(rawValue: lightChoice) ?? .firstLight }

    private var voice: VoiceModel { model.voice }
    private var hasText: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Something to send: words, or pictures alone.
    private var canSend: Bool { hasText || !drafts.isEmpty }
    private var room: Int { ChatPictures.limit - drafts.count }

    var body: some View {
        VStack(spacing: 4) {
            if dictation.on {
                HStack(spacing: 6) {
                    Circle().fill(Paper.ink).frame(width: 7, height: 7)
                    Text("Your words become text. Nothing is sent until you send it.")
                }
                .font(.system(size: 12)).foregroundStyle(ChatColor.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                .transition(.opacity)
            } else if let liveNote {
                // The note leads to Model: a button, with room for a finger.
                Button { self.liveNote = nil; openModel() } label: {
                    Text(liveNote).font(.system(size: 12)).foregroundStyle(Paper.ink2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 20).contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else if let problem = dictation.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(Paper.ink)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                // Pictures waiting to go, above the words, inside the same field.
                if !drafts.isEmpty { PictureDraftRow(drafts: $drafts).padding(.leading, 14).transition(.opacity) }
                if voice.isLive { talkRow } else {
                HStack(alignment: .bottom, spacing: 0) {
                    if sendPictures != nil { attach.frame(height: 62) }
                    if dictation.on {
                        Image(systemName: "waveform").font(.system(size: 17, weight: .semibold)).foregroundStyle(Paper.ink)
                            .symbolEffect(.variableColor.iterative, isActive: true).frame(height: 62).padding(.trailing, 10)
                    }
                    TextField(text: $input, prompt: Text(dictation.on ? "Listening…" : "Ask Poki").foregroundStyle(Paper.ink2), axis: .vertical) { Text("Ask Poki") }
                        .font(.system(size: 17)).foregroundStyle(Paper.ink)
                        .focused($focused)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1...6)
                        .padding(.vertical, 20)
                        .padding(.leading, sendPictures == nil && !dictation.on ? 18 : 0).padding(.trailing, 4)
                        .submitLabel(.send)
                        .onSubmit(submit)
                    trailing.frame(height: 62)
                }
                }
            }
            .padding(.leading, 6).padding(.trailing, 7)
            .frame(minHeight: 62)
            .background(alignment: .bottom) {
                // Poki's light, low in the field: the one colour, where you speak to it.
                Ellipse().fill(light.palette.warm.opacity(0.55)).frame(height: 26).padding(.horizontal, 70).offset(y: 12).blur(radius: 14)
            }
            .composerGlass(in: RoundedRectangle(cornerRadius: 31, style: .continuous), tint: Paper.field)
            .clipShape(RoundedRectangle(cornerRadius: 31, style: .continuous))
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
        }
        .photosPicker(isPresented: $pickingPhotos, selection: $picked, maxSelectionCount: max(1, room), matching: .images)
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task {
                let new = await PicturePicking.load(items, room: room)
                withAnimation(.snappy(duration: 0.2)) { drafts.append(contentsOf: new.prefix(max(0, room))) }
            }
        }
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let new = PicturePicking.load(urls, room: room)
            withAnimation(.snappy(duration: 0.2)) { drafts.append(contentsOf: new) }
        }
        .animation(.snappy, value: dictation.on)
        .animation(.snappy, value: voice.isLive)
        .onChange(of: voice.isLive, initial: true) { _, live in talkStarted = live ? Date() : nil }
        .onChange(of: dictation.text) { _, text in if dictation.on { input = dictation.base + text } }
        .onDisappear { dictation.stop(model) }
    }

    /// While you talk with Poki the field is the talk's own bar: the microphone (a tap mutes Poki's voice),
    /// who has the word, how long it has been, and End.
    private var talkRow: some View {
        HStack(spacing: 10) {
            Button { voice.muted.toggle() } label: {
                Image(systemName: voice.muted ? "speaker.slash.fill" : "mic.fill").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Paper.ink).frame(width: 44, height: 44).contentShape(.rect)
            }
            .accessibilityLabel(Text(voice.muted ? "Unmute Poki’s voice" : "Mute Poki’s voice"))
            Image(systemName: "waveform").font(.system(size: 17, weight: .semibold)).foregroundStyle(Paper.ink)
                .symbolEffect(.variableColor.iterative, isActive: voice.phase == .hearing || voice.phase == .speaking)
            Text(verbatim: talkWord).font(.system(size: 17, weight: .medium)).foregroundStyle(Paper.ink).lineLimit(1)
                .contentTransition(.interpolate)
            Spacer(minLength: 4)
            if let talkStarted {
                Text(talkStarted, style: .timer).font(.system(size: 15)).monospacedDigit().foregroundStyle(Paper.ink2)
            }
            Button { voice.stop() } label: {
                Text("End").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.page)
                    .padding(.horizontal, 22).frame(height: 48).background(Paper.ink, in: Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.leading, 2).frame(height: 62)
    }

    private var talkWord: String {
        switch voice.phase {
        case .connecting: String(localized: "Connecting")
        case .thinking: String(localized: "Working")
        case .speaking: String(localized: "Speaking")
        case .lost(let why): why
        default: String(localized: "Listening")
        }
    }

    /// In front of the words: add pictures, from Photos or from Files. Up to four go with one message.
    private var attach: some View {
        Menu {
            Button("Photos", systemImage: "photo.on.rectangle") { pickingPhotos = true }
            Button("Files", systemImage: "folder") { pickingFiles = true }
        } label: {
            Image(systemName: "plus").font(.system(size: 19, weight: .medium))
                .foregroundStyle(Paper.ink.opacity(room > 0 ? 1 : 0.3))
                .frame(width: 44, height: 44).contentShape(.rect)
        }
        .disabled(room <= 0)
        .accessibilityLabel(Text("Add pictures"))
    }

    /// What you press is black: stop while a task runs, send once there are words, and otherwise one
    /// button that offers the two ways to speak.
    @ViewBuilder private var trailing: some View {
        HStack(spacing: 4) {
            if running {
                Button(action: stop) { pill("stop.fill") }.accessibilityLabel(Text("Stop"))
            } else {
                if dictation.on {
                    // Dictation: the words appear in the field; nothing is sent until you tap Send.
                    Button { dictation.stop(model) } label: { pill("stop.fill") }
                        .accessibilityLabel(Text("Stop dictation"))
                } else if canSend {
                    Button(action: submit) { pill("arrow.up") }.accessibilityLabel(Text("Send"))
                } else if voice.isOn {
                    Button { voice.stop() } label: { pill("waveform").symbolEffect(.variableColor.iterative, isActive: true) }
                        .accessibilityLabel(Text("End live voice"))
                } else if !dictation.on {
                    // One black button for both ways to speak; it opens the two of them.
                    Button { speaking = true } label: { pill("waveform") }
                        // A tap is felt at once, before the connection is up.
                        .sensoryFeedback(.impact(weight: .medium), trigger: voice.isOn)
                        .accessibilityLabel(Text("Speak"))
                        .popover(isPresented: $speaking, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 0) {
                                speakRow("mic.fill", String(localized: "Dictate"), String(localized: "Speak, and it becomes text"), tint: .white.opacity(0.16)) {
                                    dictation.start(model, after: input)
                                }
                                // The live voice conversation: Poki listens and answers out loud.
                                speakRow("waveform", String(localized: "Talk with Poki"), String(localized: "A live conversation, out loud"), tint: light.palette.skyLight) {
                                    if !voice.canTalkLive {
                                        liveNote = String(localized: "Talking with Poki needs an OpenAI key (tap here for Model) or the voice bridge. Dictate works with any model.")
                                    } else { liveNote = nil; openVoice() }
                                }
                            }
                            .padding(8)
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(.black)
                        }
                }
            }
        }
        .buttonStyle(PressStyle())
    }

    private func speakRow(_ symbol: String, _ title: String, _ detail: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button { speaking = false; action() } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(tint, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.64))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(width: 248, height: 58).contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func pill(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .bold))
            .foregroundStyle(Paper.page)
            .frame(width: 48, height: 48).background(Paper.ink, in: Circle())
            .frame(width: 48, height: 48).contentShape(.rect)
    }

    private func submit() {
        guard !running, canSend else { return }
        dictation.stop(model)
        if let sendPictures, !drafts.isEmpty { sendPictures(input, drafts.map(\.jpeg)) } else { send(input) }
        input = ""
        drafts = []
    }
}

/// Dictation into the message field (Apple's speech recognition, on the device when it can), separate
/// from the live conversation: it only writes words, it never sends them.
@MainActor
@Observable
final class FieldDictation {
    private(set) var on = false
    private(set) var text = ""
    private(set) var base = ""
    private(set) var problem: String?
    private var engine: Dictation?
    private var mock: Task<Void, Never>?

    func start(_ model: AppModel, after current: String) {
        guard !on else { return }
        problem = nil
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        base = trimmed.isEmpty ? "" : trimmed + " "
        text = ""
        // The simulator has no microphone worth listening to: sample words arrive as speech would.
        if VoiceModel.mockAvailable {
            on = true
            mock = Task { [weak self] in
                var said = ""
                for word in "Reorder my usual lunch from Green Bowl".split(separator: " ") {
                    try? await Task.sleep(for: .milliseconds(320))
                    if Task.isCancelled { return }
                    said += (said.isEmpty ? "" : " ") + word
                    self?.text = said
                }
            }
            return
        }
        Task {
            guard await Dictation.allowed() else {
                problem = String(localized: "Poki needs the microphone and speech recognition: allow them in Settings › Poki.")
                return
            }
            let engine = Dictation()
            engine.onHeard = { [weak self] heard in self?.text = heard }
            model.background.pauseAudio()
            do {
                try engine.listen()
                self.engine = engine
                on = true
            } catch {
                model.background.resumeAudio()
                problem = error.localizedDescription
            }
        }
    }

    func stop(_ model: AppModel) {
        if let mock {
            mock.cancel()
            self.mock = nil
            on = false
            return
        }
        guard on, let engine else { return }
        on = false
        self.engine = nil
        Task {
            _ = await engine.finish()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            model.background.resumeAudio()
        }
    }
}

// MARK: Live voice

/// A live talk inside a chat: one card with Poki's sky on top, who has the word, the words, and what Poki
/// has done so far. The field under the chat carries the talk's state and End.
struct LiveVoiceTranscript: View {
    var voice: VoiceModel
    @AppStorage(PokiLight.key) private var light = PokiLight.firstLight.rawValue

    var body: some View {
        if voice.isLive {
            let colors = (PokiLight(rawValue: light) ?? .firstLight).palette
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Talking with Poki").font(.system(size: 16, weight: .semibold))
                        if let started = voice.lines.first?.at { Text(started, style: .timer).font(Paper.note).monospacedDigit().opacity(0.8) }
                    }
                    Spacer()
                    PokiBear(pose: TalkWords.pose(voice)).frame(width: 50, height: 50)
                }
                .foregroundStyle(.white)
                .padding(.leading, 16).padding(.trailing, 12).frame(height: 62)
                .background(LinearGradient(colors: [colors.deep, colors.sky], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 1.6)))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                TalkWords(voice: voice, size: 17).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 10)
            }
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Paper.line, lineWidth: 1.5))
            .padding(.top, 10)
            .transition(.opacity)
        }
    }
}

/// What a live talk shows: who has the word ("Listening" while you speak, "Poki" while it answers), the
/// words in the large size, and under them what Poki has done since you last spoke.
struct TalkWords: View {
    var voice: VoiceModel
    var size: CGFloat = 22

    /// Poki's pose for the moment of the talk.
    static func pose(_ voice: VoiceModel) -> String {
        switch voice.phase {
        case .speaking: "speak"
        case .thinking: "think"
        default: "listen"
        }
    }

    var body: some View {
        let lines = voice.lines
        // The owner has the word from their last line until Poki answers it, through whatever Poki does
        // in between.
        let you = lines.lastIndex { $0.role == .you }, poki = lines.lastIndex { $0.role == .poki }
        let yours = you.flatMap { $0 > (poki ?? -1) ? lines[$0].text : nil }
        let pokis = poki.map { lines[$0].text }
        // What Poki did after the owner's last words.
        let done = lines[((lines.lastIndex { $0.role == .you } ?? -1) + 1)...].filter { $0.role == .tool }
        VStack(alignment: .leading, spacing: 6) {
            Text(yours != nil || pokis == nil ? "Listening" : "Poki").font(Paper.header).foregroundStyle(Paper.ink2)
            Text(verbatim: yours ?? pokis ?? String(localized: "Go ahead."))
                .font(.system(size: size, weight: .semibold)).tracking(size > 20 ? -0.4 : 0)
                .foregroundStyle(yours == nil && pokis != nil ? Paper.ink : Paper.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.interpolate)
            ForEach(done) { line in
                HStack(spacing: 10) {
                    PaperMark(kind: .done, size: 20)
                    Text(verbatim: ActivityWords.label(line.text)).font(.system(size: 15)).foregroundStyle(Paper.ink)
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.25), value: lines)
    }
}

extension View {
    /// Liquid Glass on iOS 26 and later; before it, the bar material with a hairline edge. A tint colours
    /// either one, as the message field's blue does.
    @ViewBuilder func composerGlass<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            self.background(tint ?? .clear, in: shape).background(.bar, in: shape).overlay(shape.stroke(ChatColor.fieldEdge, lineWidth: 0.5))
        }
    }
}
