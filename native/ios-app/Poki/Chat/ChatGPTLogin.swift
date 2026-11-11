import AuthenticationServices
import Foundation
import Network
import SwiftUI

@MainActor
final class ChatGPTBrowserLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<URL, Error>?
    private var connection: NWConnection?
    private static var active = false

    private static var hostID: String {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: "chat.installationID").flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(id.uuidString.lowercased(), forKey: "chat.installationID")
        return "urn:uuid:\(id.uuidString.lowercased())"
    }

    func signIn(_ profile: ChatGPTProfile?) async throws -> ChatGPTOAuth.Authorization {
        guard !Self.active else { throw ChatGPTOAuth.Failure.accountBusy }
        Self.active = true
        defer { finish(); Self.active = false }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let port = try await listen()
            try Task.checkCancellation()
            let attempt = ChatGPTOAuth.Attempt(redirect: "http://127.0.0.1:\(port)\(ChatGPTOAuth.redirectPath)", profile: profile)
            let url = try await withCheckedThrowingContinuation { continuation in
                callback = continuation
                listener?.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in self?.receive(connection, attempt: attempt, port: port) }
                }
                let browser = ASWebAuthenticationSession(url: attempt.url(hostID: Self.hostID), callback: .customScheme("poki")) { [weak self] _, _ in
                    Task { @MainActor in self?.cancelBrowser() }
                }
                browser.presentationContextProvider = self
                session = browser
                if !browser.start() { fail(ChatGPTOAuth.Failure.browser) }
            }
            closeBrowser()
            return try await ChatGPTOAuth.exchange(attempt, callback: url)
        } onCancel: {
            Task { @MainActor in self.fail(CancellationError()) }
        }
    }

    private func listen() async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: params)
        listener = server
        server.newConnectionHandler = { $0.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            ready = continuation
            server.stateUpdateHandler = { [weak self, weak server] state in
                Task { @MainActor in
                    guard let self, self.listener === server else { return }
                    switch state {
                    case .ready:
                        guard let port = server?.port?.rawValue else { self.fail(ChatGPTOAuth.Failure.browser); return }
                        self.ready?.resume(returning: port)
                        self.ready = nil
                    case .failed, .cancelled: self.fail(ChatGPTOAuth.Failure.browser)
                    default: break
                    }
                }
            }
            server.start(queue: .main)
        }
    }

    private func receive(_ incoming: NWConnection, attempt: ChatGPTOAuth.Attempt, port: UInt16) {
        guard callback != nil else { incoming.cancel(); return }
        // The system browser may preconnect. Keep the listener available for the actual redirect.
        incoming.start(queue: .main)
        readRequest(incoming, bytes: Data(), attempt: attempt, port: port)
    }

    private func readRequest(_ incoming: NWConnection, bytes: Data, attempt: ChatGPTOAuth.Attempt, port: UInt16) {
        incoming.receive(minimumIncompleteLength: 1, maximumLength: 8192 - bytes.count) { [weak self] data, _, ended, error in
            Task { @MainActor in
                guard let self, self.callback != nil, error == nil else { incoming.cancel(); return }
                let buffer = bytes + (data ?? Data())
                guard let lineEnd = buffer.range(of: Data("\r\n".utf8)) else {
                    if ended || buffer.count >= 8192 { incoming.cancel() }
                    else { self.readRequest(incoming, bytes: buffer, attempt: attempt, port: port) }
                    return
                }
                let request = String(decoding: buffer[..<lineEnd.lowerBound], as: UTF8.self).split(separator: " ")
                guard request.count == 3, request[0] == "GET", request[1].hasPrefix("/auth/callback?"),
                      let url = URL(string: "http://127.0.0.1:\(port)\(request[1])") else {
                    incoming.cancel()
                    return
                }
                do {
                    _ = try attempt.code(from: url)
                } catch ChatGPTOAuth.Failure.cancelled {
                    self.fail(ChatGPTOAuth.Failure.cancelled)
                    incoming.cancel()
                    return
                } catch {
                    incoming.cancel()
                    return
                }
                self.connection = incoming
                let reply = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
                incoming.send(content: reply, completion: .contentProcessed { _ in incoming.cancel() })
                self.callback?.resume(returning: url)
                self.callback = nil
            }
        }
    }

    private func cancelBrowser() {
        guard callback != nil else { return }
        fail(ChatGPTOAuth.Failure.cancelled)
    }

    private func fail(_ error: Error) {
        ready?.resume(throwing: error)
        callback?.resume(throwing: error)
        ready = nil
        callback = nil
    }

    private func closeBrowser() {
        listener?.cancel()
        listener = nil
        session?.cancel()
        session = nil
    }

    private func finish() {
        closeBrowser()
        connection?.cancel()
        connection = nil
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

struct ChatGPTSignIn: View {
    @Environment(\.dismiss) private var dismiss
    var profileID: UUID? = nil
    var onAuthorized: () -> Void = {}
    @State private var work: Task<Void, Never>?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Continue with ChatGPT", action: signIn).disabled(work != nil)
                    if work != nil { ProgressView() }
                } footer: {
                    Text("Poki uses your ChatGPT plan through Sign in with ChatGPT. Each sign-in stays in this device’s Keychain.")
                }
                if let problem { Text(verbatim: problem).foregroundStyle(.red) }
            }
            .navigationTitle(profileID.flatMap(ChatGPTProfiles.shared.profile)?.title ?? "ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { work?.cancel() }
        }
    }

    private func signIn() {
        problem = nil
        work = Task {
            defer { work = nil }
            do {
                let browser = ChatGPTBrowserLogin()
                let profile = try await ChatGPTProfiles.shared.authorize(profileID, using: browser.signIn)
                if profileID == nil { ModelKeys.useChatGPT(profile.id) }
                onAuthorized()
                dismiss()
            } catch is CancellationError {
                return
            } catch let error as ChatGPTOAuth.Failure {
                problem = error.localizedDescription
            } catch {
                problem = String(localized: "Poki could not save the ChatGPT sign-in. Try again.")
            }
        }
    }
}
#if DEBUG && targetEnvironment(simulator)
/// Simulator test runs only: `SIMCTL_CHILD_POKI_TEST_CREDENTIAL=<file>` names a JSON file on the Mac,
/// `{"provider": "chatgpt"|"anthropic"|…, "model"?: id, "secret": key or credential JSON}`. It is read
/// once at launch into the keychain and the provider is selected. Nothing is printed.
enum TestCredential {
    static func importIfGiven() {
        guard let path = ProcessInfo.processInfo.environment["POKI_TEST_CREDENTIAL"],
              let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let provider = (json["provider"] as? String).flatMap(ModelProvider.init(rawValue:)),
              let secret = json["secret"] as? String else { return }
        try? ModelKeys.save(secret, for: provider)
        ModelKeys.selectedProvider = provider
        if let model = json["model"] as? String { ModelKeys.selectedModel = model }
    }
}
#endif
