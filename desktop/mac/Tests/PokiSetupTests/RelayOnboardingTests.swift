import Darwin
import Foundation
import XCTest
@testable import PokiSetup

@MainActor
final class RelayOnboardingTests: XCTestCase {
    func testBrowserHandoffOnlyReadsClipboardOnExplicitImport() async throws {
        try await withFixture("multiple") { model, commands in
            let onboarding = RelayOnboarding()
            var clipboardReads = 0
            func readClipboard() -> String? {
                clipboardReads += 1
                return nil
            }
            await onboarding.readSavedToken(using: model.bridge)
            await onboarding.importCopiedToken(using: model, readClipboard: readClipboard)
            XCTAssertEqual(clipboardReads, 0)

            var opened: [URL] = []
            await onboarding.connect(using: model.bridge) { opened.append($0); return true }
            XCTAssertEqual(opened.map(\.absoluteString), ["https://dash.cloudflare.com/profile/api-tokens?fixture=1"])
            XCTAssertEqual(onboarding.entry, .browser)
            XCTAssertEqual(clipboardReads, 0)

            await onboarding.importCopiedToken(using: model, readClipboard: readClipboard)
            XCTAssertEqual(clipboardReads, 1)
            XCTAssertNotNil(onboarding.error)
            await onboarding.importCopiedToken(using: model) { "Some unrelated clipboard text" }
            XCTAssertTrue(onboarding.accounts.isEmpty)
            await onboarding.importCopiedToken(using: model) { String(repeating: "a", count: 257) }
            XCTAssertTrue(onboarding.accounts.isEmpty)
            onboarding.cancel()
            await onboarding.importCopiedToken(using: model, readClipboard: readClipboard)
            XCTAssertEqual(clipboardReads, 1)
            XCTAssertNil(onboarding.entry)
            XCTAssertNil(onboarding.error)
            XCTAssertEqual(onboarding.status?.text, localized("Cloudflare setup canceled in Poki Setup."))
            XCTAssertEqual(commands(), ["relay_token_saved", "relay_token_setup_url"])
        }
    }

    func testBrowserRejectsURLOutsideCloudflareDashboard() async throws {
        try await withFixture("externalURL") { model, commands in
            let onboarding = RelayOnboarding()
            await onboarding.connect(using: model.bridge) { _ in
                XCTFail("The URL is not the Cloudflare dashboard")
                return true
            }
            XCTAssertNil(onboarding.entry)
            XCTAssertNotNil(onboarding.error)
            XCTAssertEqual(commands(), ["relay_token_setup_url"])
        }
    }

    func testMultipleAccountsRequireAChoiceAndDeploymentChecksKeychain() async throws {
        try await withFixture("multiple") { model, commands in
            let onboarding = RelayOnboarding()
            model.relay = deployed(accountID: "no-longer-eligible")
            await onboarding.connect(using: model.bridge) { _ in true }
            await onboarding.importCopiedToken(using: model) { " sample_fixture_token_42 \n" }
            XCTAssertEqual(onboarding.accounts.map(\.id), ["first", "second"])
            XCTAssertEqual(onboarding.accountID, "")
            XCTAssertFalse(onboarding.canDeploy)
            let premature = await onboarding.deploy(using: model)
            XCTAssertNil(premature)

            onboarding.accountID = "second"
            let deployed = await onboarding.deploy(using: model)
            XCTAssertEqual(deployed?.accountId, "second")
            XCTAssertEqual(model.relay, deployed)
            XCTAssertEqual(onboarding.tokenSaved, false)
            XCTAssertEqual(onboarding.status?.text, localized("The relay was deployed, but no token was saved in Keychain. You'll need a token to update it."))
            XCTAssertTrue(onboarding.accounts.isEmpty)
            XCTAssertNil(onboarding.entry)
            XCTAssertEqual(commands(), ["relay_token_setup_url", "relay_accounts", "relay_deploy", "relay_token_saved"])
        }
    }

    func testSavedTokenUsesPreviousAccountWhenEligible() async throws {
        try await withFixture("saved") { model, commands in
            let onboarding = RelayOnboarding()
            model.relay = deployed(accountID: "second")
            await onboarding.readSavedToken(using: model.bridge)
            XCTAssertEqual(onboarding.tokenSaved, true)
            await onboarding.useSavedToken(using: model)
            XCTAssertEqual(onboarding.accounts.count, 2)
            XCTAssertEqual(onboarding.accountID, "second")
            let updated = await onboarding.deploy(using: model)
            XCTAssertEqual(updated?.accountId, "second")
            XCTAssertTrue(onboarding.tokenSaved == true)
            XCTAssertNil(onboarding.status)
            XCTAssertEqual(commands(), ["relay_token_saved", "relay_accounts", "relay_deploy", "relay_token_saved"])
        }
    }

    func testManualTokenSelectsSingleAccountAndDoesNotEchoProviderErrors() async throws {
        try await withFixture("permission") { model, commands in
            let onboarding = RelayOnboarding()
            onboarding.enterManually()
            onboarding.manualToken = "sample_fixture_token_42"
            await onboarding.useManualToken(using: model)
            XCTAssertEqual(onboarding.accountID, "first")
            XCTAssertTrue(onboarding.canDeploy)
            XCTAssertEqual(onboarding.manualToken, "")
            let deployed = await onboarding.deploy(using: model)
            let expected = localized("Check that the token is active and grants Workers Scripts Edit and Account Settings Read for your account.")
            XCTAssertNil(deployed)
            XCTAssertEqual(onboarding.error?.text, expected)
            XCTAssertEqual(model.steps["relay"]?.last?.state, .failed)
            XCTAssertEqual(model.steps["relay"]?.last?.detail, expected)
            XCTAssertEqual(commands(), ["relay_accounts", "relay_deploy"])
        }
    }

    private func deployed(accountID: String) -> Deployed {
        Deployed(accountId: accountID, accountName: "Fixture", address: "https://poki-relay.fixture.workers.dev",
                 firstDeploy: false, deployedAt: 1, phoneLink: "poki://setup?relay=https%3A%2F%2Fpoki-relay.fixture.workers.dev")
    }

    private func withFixture(_ scenario: String, _ test: (AppModel, () -> [String]) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("poki-relay-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("bridge.py")
        let log = directory.appendingPathComponent("commands")
        let script = """
        #!/usr/bin/env python3
        import json, sys
        scenario = \(String(reflecting: scenario))
        log = \(String(reflecting: log.path))
        for line in sys.stdin:
            req = json.loads(line)
            command, args = req["cmd"], req["args"]
            with open(log, "a") as out:
                print(command, file=out)
            reply = {"id": req["id"]}
            if command == "relay_token_setup_url":
                reply["ok"] = ("https://dash.cloudflare.com.example.com/" if scenario == "externalURL"
                               else "https://dash.cloudflare.com/profile/api-tokens?fixture=1")
            elif command == "relay_token_saved":
                reply["ok"] = scenario == "saved"
            elif command in ["relay_accounts", "relay_deploy"]:
                valid = ("token" not in args if scenario == "saved"
                         else args.get("token") == "sample_fixture_token_42")
                if not valid:
                    reply["err"] = {"kind": "fixture", "message": "Unexpected argument"}
                elif command == "relay_accounts":
                    reply["ok"] = [{"id": "first", "name": "First"}]
                    if scenario != "permission":
                        reply["ok"].append({"id": "second", "name": "Second"})
                else:
                    print(json.dumps({"event": "progress", "data": {
                        "job": "relay", "kind": "step", "id": "relay", "title": "Deploying"
                    }}), flush=True)
                    if scenario == "permission":
                        reply["err"] = {"kind": "cloudflare_permission", "message": "Untrusted provider body"}
                    else:
                        reply["ok"] = {
                            "account_id": args["account_id"], "account_name": "Fixture",
                            "address": "https://poki-relay.fixture.workers.dev", "first_deploy": True,
                            "deployed_at": 1, "phone_link": "poki://setup?relay=https%3A%2F%2Fpoki-relay.fixture.workers.dev"
                        }
            else:
                reply["err"] = {"kind": "fixture", "message": "Unexpected command"}
            print(json.dumps(reply), flush=True)
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let previousHelper = ProcessInfo.processInfo.environment["POKI_SETUP_BRIDGE"]
        setenv("POKI_SETUP_BRIDGE", helper.path, 1)
        defer {
            if let previousHelper { setenv("POKI_SETUP_BRIDGE", previousHelper, 1) }
            else { unsetenv("POKI_SETUP_BRIDGE") }
        }
        try await test(AppModel(bridge: Bridge())) {
            ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
    }
}
