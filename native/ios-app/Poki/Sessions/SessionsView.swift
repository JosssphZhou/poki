import SwiftUI

extension View {
    /// The line under the title (iOS 26's navigation subtitle); nothing before iOS 26.
    @ViewBuilder func sessionSubtitle(_ text: String) -> some View {
        if #available(iOS 26.0, *), !text.isEmpty { navigationSubtitle(Text(verbatim: text)) } else { self }
    }
}

/// An outside agent's badge: its provider's logo, or its initials (see `CallerBadge`).
struct AgentBadge: View {
    var name: String
    var size: CGFloat
    var body: some View { CallerBadge(name: name, size: size).accessibilityHidden(true) }
}

/// An outside agent's session or hand-off as a conversation: the agent's own steps as grey lines, its
/// request and Poki's answer as bubbles. Live while the session runs.
struct SessionView: View {
    @Environment(AppModel.self) private var model
    var id: String
    var back: () -> Void

    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let session = SessionStore.shared.session(id)
        ChatTranscript(entries: (AskPoki.live(id)?.entries ?? session?.entries) ?? [], typing: AskPoki.live(id)?.awaitingModel ?? false, canRetry: false, retry: {}, sessionID: id) {
            if session?.live == true, let approval = model.approvals.first {
                ApprovalCard(approval: approval) { approved in model.resolve(approval, approved: approved) }
            }
        }
        // Stop sits on the bottom edge as an inset, so the bubbles scroll under it and the bars keep
        // their scroll-edge behaviour (as in the chat).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if AskPoki.live(id) != nil {
                Button { AskPoki.live(id)?.stop() } label: {
                    Text("Stop Poki").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink)
                        .padding(.horizontal, 20).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Paper.ink, lineWidth: 1.5))
                        .contentShape(.capsule)
                }
                .buttonStyle(PressStyle())
                .padding(.vertical, 10)
            }
        }
        .background(Paper.page)
        .toolbarBackground(Paper.page, for: .navigationBar)
        // The session's name is the title; its menu renames it (the system title menu).
        .navigationTitle(Text(verbatim: session?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .sessionSubtitle(caption(session))
        .toolbarTitleMenu {
            Button("Rename", systemImage: "pencil") { newName = session?.name ?? ""; renaming = true }
        }
        .alert("Rename session", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { SessionStore.shared.rename(id, to: newName) }
        }
    }

    private func caption(_ session: SavedSession?) -> String {
        guard let session else { return "" }
        switch session.kind {
        case .agent: return String(localized: "Over MCP · \(ChatTime.row(session.started))")
        case .handoff: return String(localized: "Handed to Poki · \(ChatTime.row(session.started))")
        case .voice: return String(localized: "Voice · \(ChatTime.row(session.started))")
        case .poki: return ""
        }
    }
}

/// An approval waiting for the owner, in the chat and in the session that asked for it (also in the
/// Dynamic Island, which iOS hides while Poki is in front).
struct ApprovalCard: View {
    var approval: PendingApproval
    var answer: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow this step?").font(.system(size: 17, weight: .semibold)).foregroundStyle(Paper.ink)
                Text(verbatim: approval.summary).font(.system(size: 15)).foregroundStyle(Paper.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { answer(false) } label: {
                    Text("Don’t allow").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.ink)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Paper.line, lineWidth: 1.5))
                        .contentShape(.capsule)
                }
                Button { answer(true) } label: {
                    Text("Allow").font(.system(size: 15, weight: .semibold)).foregroundStyle(Paper.page)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Paper.ink, in: Capsule())
                        .contentShape(.capsule)
                }
            }
            .buttonStyle(PressStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Paper.line, lineWidth: 1.5))
        .padding(.top, 8)
    }
}
