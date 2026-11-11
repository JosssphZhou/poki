import SwiftUI

struct GrokSignIn: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code: GrokOAuth.DeviceCode?
    @State private var task: Task<Void, Never>?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let code {
                        LabeledContent("Verification Code", value: code.userCode)
                            .textSelection(.enabled)
                        Link("Open xAI Sign-in", destination: code.signInURL)
                        LabeledContent("Or sign in on another device", value: code.verificationUri.host ?? "accounts.x.ai")
                        Text(code.verificationUri.absoluteString)
                            .font(.footnote)
                            .textSelection(.enabled)
                    } else {
                        Button("Continue with Grok", action: start).disabled(task != nil)
                    }
                    if task != nil { ProgressView("Waiting for xAI authorization…") }
                } footer: {
                    Text("Open xAI in your browser and approve the code to use your eligible Grok subscription for text chat. Poki keeps the tokens in this iPhone’s Keychain.")
                }
                if let problem { Text(problem).foregroundStyle(.red) }
            }
            .navigationTitle("Grok")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onDisappear { task?.cancel() }
        }
    }

    private func start() {
        problem = nil
        task = Task {
            defer { task = nil; code = nil }
            do {
                let grant = try await GrokOAuth.begin()
                try Task.checkCancellation()
                code = grant
                let tokens = try await GrokOAuth.complete(grant)
                try Task.checkCancellation()
                try GrokAccount.save(tokens)
                ModelKeys.selectedProvider = .grok
                dismiss()
            } catch is CancellationError {
                // The owner closed the sheet.
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
