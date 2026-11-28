import PokiCore
import XCTest
@testable import Poki

@MainActor
final class VoiceUtteranceGoalTests: XCTestCase {
    private var storage: IsolatedTestStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storage = try IsolatedTestStorage(prefix: "voice-goal")
        VoiceDirect.setEnabled(false, in: storage.storage)
    }

    override func tearDownWithError() throws {
        if let storage {
            self.storage = nil
            try storage.tearDown()
        }
        try super.tearDownWithError()
    }

    func testClassifierDistinguishesAllSixTaskRelationsWithScopeAndFreshEvidence() {
        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 1_000)

        let chat = tracker.ingestCompleteUtterance(text: "你好", itemID: "u0", delegationID: nil, source: .ownerMicrophone, at: t0)
        XCTAssertEqual(chat.relation, .chitchat)
        XCTAssertNil(chat.goalID)
        XCTAssertEqual(chat.replacementScope, .none)
        XCTAssertFalse(chat.needsFreshEvidence)

        let start = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0.addingTimeInterval(1))
        XCTAssertEqual(start.relation, .independentNewTask)
        XCTAssertNotNil(start.goalID)
        XCTAssertEqual(start.revision, 1)
        XCTAssertEqual(start.replacementScope, .none)
        XCTAssertFalse(start.needsFreshEvidence)

        let openProposal = VoiceToolProposal(
            call: VoiceCall(id: "c1", name: "open_app", arguments: #"{"app":"备忘录"}"#, session: 1, delegation: "d1", speechItem: "u1"),
            goalID: start.goalID, goalRevision: 1, source: .ownerMicrophone
        )
        guard case .allow = tracker.admit(openProposal, session: 1) else {
            return XCTFail("Opening Notes on revision 1 must be allowed.")
        }
        tracker.recordStepFinished(
            callID: "c1",
            state: .done,
            output: "app: Notes   read: 2026-11-27T01:00:01Z (15 ms)\nelements (1):\n" + #" 1 Button "新建备忘录" [340,800,44,44]"#
        )
        XCTAssertEqual(tracker.activeGoal?.observedScreen.app, "com.apple.mobilenotes")

        let backchannel = tracker.ingestCompleteUtterance(text: "嗯。", itemID: "u1b", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(2))
        XCTAssertEqual(backchannel.relation, .chitchat)
        XCTAssertEqual(tracker.activeGoal?.revision, 1)

        let cont = tracker.ingestCompleteUtterance(text: "继续", itemID: "u1c", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(3))
        XCTAssertEqual(cont.relation, .continueTask)
        XCTAssertEqual(cont.goalID, start.goalID)
        XCTAssertEqual(cont.revision, 1)
        XCTAssertEqual(cont.replacementScope, .none)

        let revise = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u2", delegationID: "d2", source: .ownerMicrophone, at: t0.addingTimeInterval(4))
        XCTAssertEqual(revise.relation, .supplementOrRevise)
        XCTAssertEqual(revise.goalID, start.goalID)
        XCTAssertEqual(revise.revision, 2)
        XCTAssertEqual(revise.baseRevision, 1)
        XCTAssertEqual(revise.replacementScope, .contentAndConstraints)
        XCTAssertTrue(revise.needsFreshEvidence)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)

        let constraintOnly = tracker.ingestCompleteUtterance(text: "现在可以发送了", itemID: "u2b", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(5))
        XCTAssertEqual(constraintOnly.relation, .supplementOrRevise)
        XCTAssertEqual(constraintOnly.replacementScope, .constraintsOnly)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, false)

        let replaceRemaining = tracker.ingestCompleteUtterance(text: "后面的步骤改成写周日", itemID: "u3", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(6))
        XCTAssertEqual(replaceRemaining.relation, .replace)
        XCTAssertEqual(replaceRemaining.goalID, start.goalID)
        XCTAssertEqual(replaceRemaining.replacementScope, .remainingSteps)

        let replaceWhole = tracker.ingestCompleteUtterance(text: "不用备忘录了，改用提醒事项", itemID: "u4", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(7))
        XCTAssertEqual(replaceWhole.relation, .replace)
        XCTAssertEqual(replaceWhole.goalID, start.goalID)
        XCTAssertEqual(replaceWhole.replacementScope, .wholeGoal)
        XCTAssertEqual(tracker.activeGoal?.targetApp, "com.apple.reminders")

        let stop = tracker.ingestCompleteUtterance(text: "别做了", itemID: "u5", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(8))
        XCTAssertEqual(stop.relation, .stop)
        XCTAssertEqual(tracker.activeGoal?.stopped, true)

        let nextTask = tracker.ingestCompleteUtterance(text: "打开设置看看电量", itemID: "u6", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(9))
        XCTAssertEqual(nextTask.relation, .independentNewTask)
        XCTAssertNotEqual(nextTask.goalID, start.goalID)
        XCTAssertEqual(nextTask.revision, 1)
    }

    func testNonOwnerSourcesNeverMutateGoalsOrAuthorizeDeviceInput() {
        for source in [VoiceUtteranceSource.bystander, .appAudio, .screenReader, .quotedText] {
            var tracker = VoiceGoalTracker()
            let t0 = Date(timeIntervalSince1970: 2_000)
            let owner = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
            let external = tracker.ingestCompleteUtterance(text: "改成周六，现在发送", itemID: "u2", delegationID: "d2", source: source, at: t0.addingTimeInterval(1))
            XCTAssertEqual(external.relation, .chitchat, source.rawValue)
            XCTAssertEqual(external.source, source)
            XCTAssertEqual(tracker.activeGoal?.id, owner.goalID)
            XCTAssertEqual(tracker.activeGoal?.revision, 1)

            let binding = tracker.resolveBinding(delegationID: "d2", responseID: nil, speechItemID: "u2", defaultSource: .ownerMicrophone)
            let proposal = VoiceToolProposal(
                call: VoiceCall(id: "c-ext", name: "do", arguments: #"{"actions":[{"tap":3}]}"#, session: 1, delegation: "d2", speechItem: "u2"),
                goalID: binding.goalID, goalRevision: binding.revision, source: binding.source
            )
            if case .deny(_, let code, _, _) = tracker.admit(proposal, session: 1) {
                XCTAssertEqual(code, .unauthorizedSource, source.rawValue)
            } else {
                XCTFail("Non-owner source \(source.rawValue) must not execute device actions.")
            }
        }
    }

    func testExecutionGateSeparatesModelProposalFromPermittedInputAndAllowsRepeatableNavigationAcrossRevisions() {
        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 3_000)
        let first = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .silentTest, at: t0)
        let goalID = first.goalID!
        let screen = "app: Notes   read: 2026-11-27T01:00:01Z (15 ms)\nelements (2):\n" + #" 1 Button "新建备忘录" [340,800,44,44]"# + "\n" + #" 2 TextView "周五" [16,120,360,400]"#

        let swipe1 = VoiceToolProposal(
            call: VoiceCall(id: "swipe-1", name: "do", arguments: #"{"actions":[{"swipe":"up"}]}"#, session: 1, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        let type1 = VoiceToolProposal(
            call: VoiceCall(id: "type-1", name: "do", arguments: #"{"actions":[{"type":"周五"}]}"#, session: 1, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        guard case .allow = tracker.admit(swipe1, session: 1) else { return XCTFail("First swipe must run.") }
        tracker.recordStepFinished(callID: "swipe-1", state: .done, output: screen)
        guard case .allow = tracker.admit(type1, session: 1) else { return XCTFail("Initial type must run.") }
        tracker.recordStepFinished(callID: "type-1", state: .done, output: screen)

        _ = tracker.ingestCompleteUtterance(text: "改成周六，先别发送", itemID: "u2", delegationID: "d2", source: .silentTest, at: t0.addingTimeInterval(2))

        let look2 = VoiceToolProposal(
            call: VoiceCall(id: "look-2", name: "look", arguments: "{}", session: 1, delegation: "d2"),
            goalID: goalID, goalRevision: 2, source: .silentTest
        )
        guard case .allow = tracker.admit(look2, session: 1) else { return XCTFail("look must be allowed in revision 2.") }
        tracker.recordStepFinished(callID: "look-2", state: .done, output: screen)

        let swipe2 = VoiceToolProposal(
            call: VoiceCall(id: "swipe-2", name: "do", arguments: #"{"actions":[{"swipe":"up"}]}"#, session: 2, delegation: "d2"),
            goalID: goalID, goalRevision: 2, source: .silentTest
        )
        guard case .allow = tracker.admit(swipe2, session: 2) else {
            return XCTFail("Repeatable navigation across a revision/session boundary must run.")
        }

        let dupType = VoiceToolProposal(
            call: VoiceCall(id: "type-dup", name: "do", arguments: #"{"actions":[{"type":"周五"}]}"#, session: 2, delegation: "d2"),
            goalID: goalID, goalRevision: 2, source: .silentTest
        )
        if case .deny(_, let code, _, _) = tracker.admit(dupType, session: 2) {
            XCTAssertEqual(code, .duplicateStepInGoal)
        } else {
            XCTFail("Repeating an already-succeeded mutation across revision/session boundaries must be denied.")
        }

        let stale = VoiceToolProposal(
            call: VoiceCall(id: "stale-r1", name: "do", arguments: #"{"actions":[{"type":"周日"}]}"#, session: 2, delegation: "d1"),
            goalID: goalID, goalRevision: 1, source: .silentTest
        )
        if case .deny(_, let code, _, _) = tracker.admit(stale, session: 2) {
            XCTAssertEqual(code, .staleRevision)
        } else {
            XCTFail("Stale revision 1 mutation must be rejected after revision 2.")
        }
    }

    func testProductionScreenFormatsQuotedClearanceIndependentAppsAndOutOfOrderResponses() {
        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 3_500)

        let u1 = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
        _ = tracker.admit(VoiceToolProposal(call: VoiceCall(id: "c-open", name: "open_app", arguments: #"{"app":"备忘录"}"#, session: 1), goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone), session: 1)
        tracker.recordStepFinished(callID: "c-open", state: .done, output: """
        app: Notes (com.apple.mobilenotes)   read: 2026-11-27T01:00:01Z (20 ms)
        elements (3):
         1 Button "新建备忘录" [340,800,44,44]
         2 TextView "周五" [16,120,360,400]
         3 Button "发送" [330,60,50,34]
        """)
        XCTAssertEqual(tracker.activeGoal?.observedScreen.app, "com.apple.mobilenotes")

        tracker.noteCommittedUtterance(itemID: "u2")
        tracker.bindResponse("r2", itemID: "u2")
        let pendingBinding = tracker.resolveBinding(delegationID: nil, responseID: "r2", speechItemID: nil, defaultSource: .ownerMicrophone)
        XCTAssertTrue(pendingBinding.awaitingTranscript, "Pending utterance u2 must hold proposals before transcription completes.")
        let earlyDecision = tracker.admit(
            VoiceToolProposal(
                call: VoiceCall(id: "c-early", name: "do", arguments: #"{"actions":[{"type":"周五"}]}"#, session: 1),
                goalID: pendingBinding.goalID, goalRevision: pendingBinding.revision, source: pendingBinding.source,
                awaitingUtteranceTranscript: pendingBinding.awaitingTranscript
            ),
            session: 1
        )
        if case .deny(_, let code, _, _) = earlyDecision {
            XCTAssertEqual(code, .awaitingUtteranceTranscript)
        } else {
            XCTFail("Device mutation before committed utterance transcript must be denied.")
        }

        let u2 = tracker.ingestCompleteUtterance(text: "把周五改成周六，先別發送", itemID: "u2", delegationID: "d2", source: .ownerMicrophone, at: t0.addingTimeInterval(1))
        XCTAssertEqual(u2.revision, 2)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)
        let resolvedR2 = tracker.resolveBinding(delegationID: nil, responseID: "r2", speechItemID: nil, defaultSource: .ownerMicrophone)
        XCTAssertFalse(resolvedR2.awaitingTranscript)
        XCTAssertEqual(resolvedR2.revision, 2)

        _ = tracker.admit(VoiceToolProposal(call: VoiceCall(id: "c-look", name: "look", arguments: "{}", session: 1), goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone), session: 1)
        tracker.recordStepFinished(callID: "c-look", state: .done, output: """
        app: Notes   read: 2026-11-27T01:00:05Z (19 ms)
        elements (3 on screen; only the changed are listed: + new, ~ moved; the 2 others keep their numbers, full=true lists all):
        ~2 TextView "周五" [16,130,360,400]
        """)
        XCTAssertEqual(tracker.activeGoal?.needsFreshEvidence, false)
        XCTAssertEqual(tracker.activeGoal?.observedScreen.elements[3]?.text, "发送")
        XCTAssertEqual(tracker.activeGoal?.observedScreen.elements[2]?.frame?.y, 130)

        let pathSend = tracker.admit(
            VoiceToolProposal(
                call: VoiceCall(id: "c-path-arr", name: "do", arguments: #"{"actions":[{"path":[{"tap":"发送"}]}]}"#, session: 1),
                goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone
            ),
            session: 1
        )
        if case .deny(_, let code, _, _) = pathSend {
            XCTAssertEqual(code, .forbiddenByConstraint)
        } else {
            XCTFail("Array-form path targeting Send must be blocked under forbidsSend.")
        }

        let pathFindSend = tracker.admit(
            VoiceToolProposal(
                call: VoiceCall(id: "c-path-find", name: "do", arguments: #"{"actions":[{"path":[{"tap":{"find":"傳送"}}]}]}"#, session: 1),
                goalID: u2.goalID, goalRevision: 2, source: .ownerMicrophone
            ),
            session: 1
        )
        if case .deny(_, let code, _, _) = pathFindSend {
            XCTAssertEqual(code, .forbiddenByConstraint)
        } else {
            XCTFail("Path find target with Traditional Chinese 傳送 must be blocked under forbidsSend.")
        }

        let quoted = tracker.ingestCompleteUtterance(text: "在备忘录写上『现在可以发送了』这句话", itemID: "u3", delegationID: "d3", source: .ownerMicrophone, at: t0.addingTimeInterval(2))
        XCTAssertEqual(quoted.relation, .supplementOrRevise)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)

        let holdNatural = tracker.ingestCompleteUtterance(text: "暂时不发出去，先留在草稿里", itemID: "u3b", delegationID: "d3b", source: .ownerMicrophone, at: t0.addingTimeInterval(2.5))
        XCTAssertEqual(holdNatural.relation, .supplementOrRevise)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)

        let clearance = tracker.ingestCompleteUtterance(text: "现在可以发送了", itemID: "u4", delegationID: "d4", source: .ownerMicrophone, at: t0.addingTimeInterval(3))
        XCTAssertEqual(clearance.replacementScope, .constraintsOnly)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, false)
        let staleR1 = tracker.admit(VoiceToolProposal(call: VoiceCall(id: "c-stale", name: "do", arguments: #"{"actions":[{"type":"周五"}]}"#, session: 1), goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone), session: 1)
        if case .deny(_, let code, _, _) = staleR1 {
            XCTAssertEqual(code, .staleRevision)
        } else {
            XCTFail("Stale r1 Friday write must stay denied even after a constraints-only clearance.")
        }

        let stopWithHold = tracker.ingestCompleteUtterance(text: "停一下，先别发", itemID: "u4b", delegationID: "d4b", source: .ownerMicrophone, at: t0.addingTimeInterval(3.5))
        XCTAssertEqual(stopWithHold.relation, .stop)
        XCTAssertEqual(tracker.activeGoal?.stopped, true)
        XCTAssertEqual(tracker.activeGoal?.forbidsSend, true)

        let otherApp = tracker.ingestCompleteUtterance(text: "打开设置，把字体改成大号", itemID: "u5", delegationID: "d5", source: .ownerMicrophone, at: t0.addingTimeInterval(4))
        XCTAssertEqual(otherApp.relation, .independentNewTask)
        XCTAssertNotEqual(otherApp.goalID, u1.goalID)
        XCTAssertEqual(tracker.activeGoal?.targetApp, "com.apple.preferences")

        let stopHere = tracker.ingestCompleteUtterance(text: "到这里就停吧", itemID: "u6", delegationID: "d6", source: .ownerMicrophone, at: t0.addingTimeInterval(5))
        XCTAssertEqual(stopHere.relation, .stop)
        XCTAssertEqual(tracker.activeGoal?.stopped, true)
    }

    func testReconnectAfterPreDisconnectRevisionSendsBoundedRecoveryNoteOnce() async throws {
        URLProtocol.registerClass(BridgeStub.self)
        defer { URLProtocol.unregisterClass(BridgeStub.self) }

        let time = FakeTime()
        var links: [FakeConnection] = []
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, _, _ in
                if name == "do" {
                    return ("unknown: the bridge did not answer; the action may have run.", true, nil)
                }
                return ("app: Notes   read: 2026-11-27T01:00:01Z (15 ms)\nelements (1):\n" + #" 1 Button "新建备忘录" [340,800,44,44]"#, false, nil)
            },
            connection: { onEvent, onClosed in
                let link = FakeConnection()
                link.onEvent = onEvent
                link.onClosed = onClosed
                links.append(link)
                return link
            },
            time: time.clock,
            storage: storage.storage
        )
        XCTAssertTrue(voice.setBridge(BridgeStub.address))
        voice.onConversationEnded = { _, _ in }
        await voice.start()
        links.last?.play(["type": "session.created"],
                         ["type": "conversation.item.input_audio_transcription.completed", "item_id": "u1", "transcript": "打开备忘录，写周五"],
                         ["type": "response.created", "response": ["id": "r1"]],
                         ["type": "response.output_item.done", "response_id": "r1",
                          "item": ["type": "function_call", "call_id": "c-draft", "name": "do", "arguments": #"{"actions":[{"tap":1},{"type":"周五"}]}"#]])
        await time.settle()
        links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u2", "transcript": "改成周六，先别发送"])
        links.last?.onClosed?("network drop")
        await time.settle()

        await voice.start()
        links.last?.play(["type": "session.created"])
        await time.settle()

        let recoveryNotes = links.last?.notes.filter { $0.contains("Reconnect goal recovery") } ?? []
        XCTAssertEqual(recoveryNotes.count, 1)
        let recovery = try XCTUnwrap(recoveryNotes.first)
        XCTAssertTrue(recovery.contains("g1 r2"), recovery)
        XCTAssertTrue(recovery.contains("c-draft:do:unknown"), recovery)
        XCTAssertTrue(recovery.contains("call look first"), recovery)
        XCTAssertTrue(recovery.contains("do not send"), recovery)
        XCTAssertLessThanOrEqual(recovery.utf8.count, VoiceGoalTracker.noteByteLimit)
        voice.stop()
    }

    func testPromptAndToolLengthsStayUnchangedAndLongGoalNotesPreserveDirectivesWithin480Bytes() async throws {
        URLProtocol.registerClass(OpenAIStub.self)
        let savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        defer {
            AppLocalization.shared.preference = savedLanguage
            URLProtocol.unregisterClass(OpenAIStub.self)
        }

        let session = VoiceDirect.session(in: storage.storage)
        let instructions = try XCTUnwrap(session["instructions"] as? String)
        let tools = try XCTUnwrap(session["tools"] as? [[String: Any]])
        let toolNames = tools.compactMap { $0["name"] as? String }
        XCTAssertEqual(toolNames, ["get_ios_version", "look", "open_app", "do"])

        XCTAssertEqual(instructions.count, 2973, "Static Realtime instructions length drifted from main baseline.")
        for forbidden in ["Goal update", "Reconnect goal recovery", "forbidsSend", "replacementScope"] {
            XCTAssertFalse(instructions.contains(forbidden))
            for tool in tools {
                XCTAssertFalse((tool["description"] as? String ?? "").contains(forbidden))
            }
        }
        let nonDoToolChars = tools
            .filter { ($0["name"] as? String) != "do" }
            .compactMap { $0["description"] as? String }
            .reduce(0) { $0 + $1.count }
        XCTAssertEqual(nonDoToolChars, 600, "Static non-do tool descriptions drifted from main baseline.")
        let allToolChars = tools
            .compactMap { $0["description"] as? String }
            .reduce(0) { $0 + $1.count }
        XCTAssertEqual(allToolChars, 8100, "Static all Realtime tool descriptions drifted from main baseline.")

        _ = try await VoiceDirect.exchangeLiveOffer("offer", model: "gpt-live-1.1", apiKey: "sk-test")
        let liveSession = try XCTUnwrap(OpenAIStub.session)
        let liveForeground = try XCTUnwrap(liveSession["instructions"] as? String)
        let liveBackend = try XCTUnwrap((liveSession["delegation"] as? [String: Any])?["responses"] as? [String: Any])
        let liveBackendInstructions = try XCTUnwrap(liveBackend["instructions"] as? String)
        let liveBackendTools = try XCTUnwrap(liveBackend["tools"] as? [[String: Any]])
        let liveBackendToolChars = liveBackendTools.compactMap { $0["description"] as? String }.reduce(0) { $0 + $1.count }
        XCTAssertEqual(liveForeground.count, 1470, "Live foreground instructions drifted from main baseline.")
        XCTAssertEqual(liveBackendInstructions.count, 3045, "Live backend instructions drifted from main baseline.")
        XCTAssertEqual(liveBackendToolChars, 8294, "Live backend tool descriptions drifted from main baseline.")

        XCTAssertEqual(VoiceDirect.codexFrontendInstructions.count, 861, "Codex frontend instructions drifted from main baseline.")
        XCTAssertEqual(VoiceDirect.codexBackendInstructions.count, 2784, "Codex backend instructions drifted from main baseline.")
        let codexToolChars = VoiceDirect.codexTools.compactMap { $0["description"] as? String }.reduce(0) { $0 + $1.count }
        XCTAssertEqual(codexToolChars, 8100, "Codex tool descriptions drifted from main baseline.")

        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 4_000)
        let u1 = tracker.ingestCompleteUtterance(text: "打开备忘录，写周五", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
        let screen = "app: Notes   read: 2026-11-27T01:00:01Z (12 ms)\nelements (1):\n" + #" 1 Button "新建备忘录" [340,800,44,44]"#
        for idx in 1...4 {
            let cid = "very_long_call_identifier_number_\(idx)_abcdefghij"
            let p = VoiceToolProposal(
                call: VoiceCall(id: cid, name: "do", arguments: #"{"actions":[{"tap":1}]}"#, session: 1),
                goalID: u1.goalID, goalRevision: 1, source: .ownerMicrophone
            )
            _ = tracker.admit(p, session: 1)
            tracker.recordStepFinished(callID: cid, state: .done, output: screen)
        }
        let longCJK = "改成周六下午三点在会议室开会并同步发给所有人讨论具体安排，先别发送，" + String(repeating: "额外备注内容需要完整记录下来", count: 8)
        let u2 = tracker.ingestCompleteUtterance(text: longCJK, itemID: "u2", delegationID: "d2", source: .ownerMicrophone, at: t0.addingTimeInterval(1))
        let note = try XCTUnwrap(tracker.revisionNote(for: u2))
        XCTAssertLessThanOrEqual(note.utf8.count, VoiceGoalTracker.noteByteLimit, "Revision note must fit inside 480 UTF-8 bytes.")
        XCTAssertTrue(note.contains("do not send"), note)
        XCTAssertTrue(note.contains("call look first"), note)
        XCTAssertTrue(note.contains("edit existing draft (clear:true)"), note)

        let recovery = try XCTUnwrap(tracker.recoveryNote(forSession: 2))
        XCTAssertLessThanOrEqual(recovery.utf8.count, VoiceGoalTracker.noteByteLimit, "Recovery note must fit inside 480 UTF-8 bytes.")
        XCTAssertTrue(recovery.contains("do not send"), recovery)
        XCTAssertTrue(recovery.contains("call look first"), recovery)
        XCTAssertTrue(recovery.contains("edit existing draft (clear:true)"), recovery)
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSimulatorNotesRevisionRehearsalProducesOneSaturdayDraftWithoutSending() async {
        UserDefaults.standard.set("revise-notes", forKey: "pokiTalkRehearsal")
        defer { UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal") }
        TalkRehearsal.resetNotesState()

        _ = await TalkRehearsal.step(name: "do", arguments: #"{"actions":[{"tap":1},{"type":"周五"}]}"#)
        _ = await TalkRehearsal.step(name: "do", arguments: #"{"actions":[{"tap":2},{"type":"周六"}]}"#)
        XCTAssertEqual(TalkRehearsal.notesState.drafts.last, "周五周六", "Omitting clear must append like PokiCore.")
        _ = await TalkRehearsal.step(name: "do", arguments: #"{"actions":[{"tap":2},{"type":"周六","clear":true}]}"#)
        XCTAssertEqual(TalkRehearsal.notesState.drafts.last, "周六", "clear:true must replace the draft text.")

        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, arguments, _ in await TalkRehearsal.step(name: name, arguments: arguments) },
            connection: VoiceModel.connection,
            storage: storage.storage
        )
        voice.onConversationEnded = { _, _ in }
        await voice.start(microphone: false)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if voice.lines.contains(where: { $0.role == .poki && $0.text.contains("周六") }) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(TalkRehearsal.notesState.opened, 1)
        XCTAssertEqual(TalkRehearsal.notesState.drafts, ["周六"])
        XCTAssertEqual(TalkRehearsal.notesState.sent, 0)
        XCTAssertEqual(voice.goalTracker.activeGoal?.revision, 2)
        XCTAssertEqual(voice.goalTracker.activeGoal?.forbidsSend, true)
        voice.stop()
    }
    #endif
}
