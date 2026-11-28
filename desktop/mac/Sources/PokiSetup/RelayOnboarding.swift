import Foundation
import SwiftUI

@MainActor
final class RelayOnboarding: ObservableObject {
    enum Entry { case browser, manual }
    @Published private(set) var entry: Entry?
    @Published private(set) var accounts: [CloudflareAccount] = []
    @Published var accountID = ""
    @Published var manualToken = ""
    @Published private(set) var tokenSaved: Bool?
    @Published private(set) var status: SetupMessage?
    @Published private(set) var error: RelayFailure?
    @Published private(set) var working = false

    private var token: String?

    var canDeploy: Bool { !working && accounts.contains { $0.id == accountID } }

    func readSavedToken(using bridge: Bridge) async {
        tokenSaved = try? await bridge.call("relay_token_saved")
    }

    func connect(using bridge: Bridge, open: (URL) -> Bool) async {
        guard !working, entry == nil, accounts.isEmpty else { return }
        status = nil
        error = nil
        working = true
        defer { working = false }
        if let raw: String = try? await bridge.call("relay_token_setup_url"),
           let parts = URLComponents(string: raw), parts.scheme == "https",
           parts.host == "dash.cloudflare.com", parts.user == nil, parts.password == nil,
           parts.port == nil || parts.port == 443,
           let url = parts.url, open(url) {
            entry = .browser
        } else {
            error = .copy("Could not open Cloudflare. Try again or enter a token manually.")
        }
    }

    func enterManually() {
        guard !working, accounts.isEmpty else { return }
        status = nil
        error = nil
        entry = .manual
    }

    func cancel() {
        guard !working else { return }
        resetEntry()
        error = nil
        status = .copy("Cloudflare setup canceled in Poki Setup.")
    }

    func importCopiedToken(using model: AppModel, readClipboard: () -> String?) async {
        guard !working, entry == .browser, accounts.isEmpty else { return }
        guard let copied = readClipboard()?.trimmingCharacters(in: .whitespacesAndNewlines), !copied.isEmpty else {
            error = .copy("No token could be read from the clipboard. Copy the token in Cloudflare and try again, or enter it manually.")
            return
        }
        await loadAccounts(using: model, token: copied)
    }

    func useManualToken(using model: AppModel) async {
        guard !working, entry == .manual, accounts.isEmpty else { return }
        await loadAccounts(using: model, token: manualToken.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func useSavedToken(using model: AppModel) async {
        guard !working, entry == nil, accounts.isEmpty, tokenSaved == true else { return }
        await loadAccounts(using: model, token: nil)
    }

    func forgetToken(using bridge: Bridge) async {
        guard !working, entry == nil, accounts.isEmpty, tokenSaved == true else { return }
        status = nil
        error = nil
        working = true
        defer { working = false }
        do {
            try await bridge.run("relay_forget_token")
            await readSavedToken(using: bridge)
        } catch {
            self.error = .copy("Could not remove the saved token from Keychain. Try again.")
        }
    }

    func deploy(using model: AppModel) async -> Deployed? {
        guard canDeploy, !model.busyJobs.contains("relay") else { return nil }
        status = nil
        error = nil
        working = true
        defer { working = false }
        do {
            let deployed: Deployed = try await model.job("relay") {
                do {
                    return try await model.bridge.call("relay_deploy", ["account_id": accountID, "token": token])
                } catch {
                    throw RelayFailure(error)
                }
            }
            model.relay = deployed
            resetEntry()
            await readSavedToken(using: model.bridge)
            if tokenSaved == false {
                status = .copy("The relay was deployed, but no token was saved in Keychain. You'll need a token to update it.")
            } else if tokenSaved == nil {
                status = .copy("The relay was deployed, but Poki Setup couldn't verify whether a token is saved in Keychain.")
            }
            return deployed
        } catch {
            self.error = (error as? RelayFailure) ?? RelayFailure(error)
            return nil
        }
    }

    private func loadAccounts(using model: AppModel, token: String?) async {
        status = nil
        error = nil
        if let token, token.range(of: #"^[A-Za-z0-9_-]{20,256}$"#, options: .regularExpression) == nil {
            error = RelayFailure(CoreError(kind: "cloudflare_invalid_token", message: ""))
            return
        }
        working = true
        defer { working = false }
        do {
            let eligible: [CloudflareAccount] = try await model.bridge.call("relay_accounts", ["token": token])
            guard !eligible.isEmpty else {
                throw CoreError(kind: "cloudflare_no_accounts", message: "")
            }
            if eligible.count == 1 {
                accountID = eligible[0].id
            } else if let previous = model.relay?.accountId, eligible.contains(where: { $0.id == previous }) {
                accountID = previous
            } else {
                accountID = ""
            }
            self.token = token
            manualToken = ""
            accounts = eligible
        } catch {
            self.error = RelayFailure(error)
        }
    }

    private func resetEntry() {
        entry = nil
        accounts = []
        accountID = ""
        manualToken = ""
        token = nil
    }
}

struct RelayFailure: LocalizedError {
    let message: SetupMessage
    let needsManualDeploy: Bool
    var text: String { message.text }
    var errorDescription: String? { text }

    static func copy(_ text: String.LocalizationValue) -> Self {
        Self(message: .copy(text), needsManualDeploy: false)
    }

    private init(message: SetupMessage, needsManualDeploy: Bool) {
        self.message = message
        self.needsManualDeploy = needsManualDeploy
    }

    init(_ error: Error) {
        let kind = (error as? CoreError)?.kind
        needsManualDeploy = kind == "cloudflare_unsupported_migration"
        switch kind {
        case "cloudflare_permission":
            message = .copy("Check that the token is active and grants Workers Scripts Edit and Account Settings Read for your account.")
        case "cloudflare_no_accounts":
            message = .copy("This token can't see any Cloudflare account. Make sure it includes the account you want to use.")
        case "cloudflare_subdomain_taken":
            message = .copy("Cloudflare couldn't register an available workers.dev address. Try again or register one under Workers & Pages in Cloudflare.")
        case "cloudflare_free_limit":
            message = .copy("This account reached a Workers limit or its plan doesn't allow this deployment. Check your Workers usage and plan, or choose a different account.")
        case "cloudflare_network":
            message = .copy("Could not reach Cloudflare. Check your connection and try again.")
        case "cloudflare_not_ready":
            message = .copy("The relay isn't answering yet. Wait a minute and try again.")
        case "cloudflare_unsupported_migration":
            message = .copy("This version of Poki Setup can't update the existing Worker's migration. Use a compatible relay release and run deploy/cf-relay/deploy.sh to deploy manually.")
        case "cloudflare_invalid_token":
            message = .copy("Cloudflare couldn't use this token. Copy the API token again or create a new one.")
        case "cloudflare_api":
            message = .copy("Cloudflare couldn't complete the request. Try again or check your Workers & Pages dashboard.")
        default:
            message = .copy("Poki Setup couldn't complete the Cloudflare request. Try again.")
        }
    }
}
