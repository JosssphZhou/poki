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

    func testVoiceOriginNeverAutoApprovesSensitiveStepsEvenWithSpokenAffirmation() async throws {
        try ModelKeys.save("sk-test-approval-boundary", for: .openai, storage: storage.storage)
        ModelKeys.setSelectedProvider(.openai, in: storage.storage)
        ModelKeys.setSelectedModel("gpt-6.1-terra", in: storage.storage)
        XCTAssertTrue(ApprovalClassifier.hasModel(in: storage.storage), "Test fixture must have a usable approval classifier model.")
        storage.storage.defaults.set(ApprovalClassifier.Level.permissive.rawValue, forKey: ApprovalClassifier.levelKey)

        let sendApproval = PendingApproval(
            id: "voice-send-\(UUID().uuidString)",
            app: "WeChat",
            summary: "Tap “发送”",
            reason: "sending a message (\"发送\")",
            expires: Date().addingTimeInterval(60)
        )
        for mode in [ApprovalClassifier.Mode.confirm, ApprovalClassifier.Mode.reply] {
            storage.storage.defaults.set(mode.rawValue, forKey: ApprovalClassifier.modeKey)
            let approval = PendingApproval(
                id: "voice-\(mode.rawValue)-\(UUID().uuidString)",
                app: sendApproval.app,
                summary: sendApproval.summary,
                reason: sendApproval.reason,
                expires: sendApproval.expires
            )
            XCTAssertEqual(
                ApprovalClassifier.route(approval, voiceOn: true, origin: .voice("voice-session"), storage: storage.storage),
                .owner,
                "Voice sessions must always route optional sensitive steps to on-device owner confirmation under \(mode.rawValue)."
            )
            XCTAssertEqual(
                ApprovalClassifier.route(approval, voiceOn: true, origin: .chat("dictation-chat"), storage: storage.storage),
                .owner,
                "Active voice/dictation must not allow auto-approval even when origin is chat under \(mode.rawValue)."
            )
        }

        let verdict = await ApprovalClassifier.decide(
            sendApproval,
            level: .permissive,
            voice: [
                VoiceLine(role: .you, text: "给小王发消息说我晚点到"),
                VoiceLine(role: .poki, text: "要发送吗？"),
                VoiceLine(role: .you, text: "好的"),
                VoiceLine(role: .you, text: "确认"),
            ],
            origin: .voice("voice-session"),
            storage: storage.storage
        )
        XCTAssertFalse(verdict.allowed, "Spoken 好的/确认 must never auto-approve a sensitive step.")
        XCTAssertEqual(verdict.reason, "spoken confirmations cannot approve sensitive steps")

        let originalApp = AskPoki.app
        let originalChat = AskPoki.chat
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: storage.storage)
        let chat = ChatModel(app: app)
        AskPoki.install(app: app, chat: chat)
        defer {
            if let originalApp, let originalChat { AskPoki.install(app: originalApp, chat: originalChat) }
        }
        XCTAssertEqual(
            ApprovalClassifier.origin(voiceOn: true, outsideSession: nil),
            .voice(chat.sessionID),
            "Active voice (including dictation) must resolve to .voice origin."
        )
    }

    func testPartialAndSegmentedUtteranceRunsOnlyLowRiskPrepAndBlocksSendAcrossVoicePaths() async throws {
        URLProtocol.registerClass(BridgeStub.self)
        defer { URLProtocol.unregisterClass(BridgeStub.self) }

        let chatScreen = """
        app: 微信 (com.tencent.xin)   read: 2026-11-27T01:00:00Z (12 ms)
        elements (3):
         1 Cell "小王" [16,120,358,64]
         2 TextField "发消息" [16,760,290,40]
         3 Button "发送" [320,760,60,40]
        """

        // 1. Realtime streaming partial delta + segmented turn ("给小王发消息说" -> "我晚点到")
        do {
            let time = FakeTime()
            var links: [FakeConnection] = []
            var opened = 0
            var typed: [String] = []
            var sent = 0
            let voice = VoiceModel(
                clearTap: { _, _, _ in .clear },
                phoneTool: { name, arguments, _ in
                    let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
                    switch name {
                    case "open_app":
                        opened += 1
                        return (chatScreen, false, nil)
                    case "look":
                        return (chatScreen, false, nil)
                    case "do":
                        for action in args["actions"] as? [[String: Any]] ?? [] {
                            if action["launch"] != nil { opened += 1 }
                            if (action["tap"] as? Int) == 3 { sent += 1 }
                            if let text = action["type"] as? String { typed.append(text) }
                        }
                        return (chatScreen, false, nil)
                    default:
                        return ("ok", false, nil)
                    }
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
                             ["type": "input_audio_buffer.speech_started", "item_id": "rt-u1"],
                             ["type": "conversation.item.input_audio_transcription.delta", "item_id": "rt-u1", "delta": "给小王发消息说"],
                             ["type": "response.created", "response": ["id": "rt-r1"]],
                             ["type": "response.output_item.done", "response_id": "rt-r1",
                              "item": ["type": "function_call", "call_id": "rt-open", "name": "do", "arguments": #"{"actions":[{"launch":"com.tencent.xin"}]}"#]],
                             ["type": "response.output_item.done", "response_id": "rt-r1",
                              "item": ["type": "function_call", "call_id": "rt-type-early", "name": "do", "arguments": #"{"actions":[{"tap":2},{"type":"我晚点到"}]}"#]],
                             ["type": "response.output_item.done", "response_id": "rt-r1",
                              "item": ["type": "function_call", "call_id": "rt-send-early", "name": "do", "arguments": #"{"actions":[{"tap":3}]}"#]],
                             ["type": "response.done", "response": ["id": "rt-r1"]])
            await time.settle()

            XCTAssertEqual(opened, 1, "Low-risk preparation (open_app for messaging app) must run during partial utterance.")
            XCTAssertTrue(typed.isEmpty, "Message typing must wait until the partial utterance completes.")
            XCTAssertEqual(sent, 0, "Sending must never execute while the utterance is still partial.")

            // VAD commits halfway ("给小王发消息说"): still incomplete -> sending/typing stay blocked.
            links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "rt-u1", "transcript": "给小王发消息说"],
                             ["type": "response.created", "response": ["id": "rt-r2"]],
                             ["type": "response.output_item.done", "response_id": "rt-r2",
                              "item": ["type": "function_call", "call_id": "rt-send-half", "name": "do", "arguments": #"{"actions":[{"tap":3}]}"#]],
                             ["type": "response.done", "response": ["id": "rt-r2"]])
            await time.settle()
            XCTAssertEqual(sent, 0, "Segmented incomplete utterance must still block sending.")

            // Spoken affirmation alone ("好的" / "确认") must NOT complete the unfinished message!
            links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "rt-u1-ack", "transcript": "确认"],
                             ["type": "response.created", "response": ["id": "rt-r2b"]],
                             ["type": "response.output_item.done", "response_id": "rt-r2b",
                              "item": ["type": "function_call", "call_id": "rt-send-ack", "name": "do", "arguments": #"{"actions":[{"tap":3}]}"#]],
                             ["type": "response.done", "response": ["id": "rt-r2b"]])
            await time.settle()
            XCTAssertEqual(sent, 0, "Spoken 确认 must not complete a partial utterance or trigger sending.")

            // Second segment arrives ("我晚点到") -> completes the same goal without reopening WeChat.
            links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "rt-u2", "transcript": "我晚点到"],
                             ["type": "response.created", "response": ["id": "rt-r3"]],
                             ["type": "response.output_item.done", "response_id": "rt-r3",
                              "item": ["type": "function_call", "call_id": "rt-reopen", "name": "do", "arguments": #"{"actions":[{"launch":"com.tencent.xin"}]}"#]],
                             ["type": "response.output_item.done", "response_id": "rt-r3",
                              "item": ["type": "function_call", "call_id": "rt-type-full", "name": "do", "arguments": #"{"actions":[{"tap":2},{"type":"我晚点到"}]}"#]],
                             ["type": "response.done", "response": ["id": "rt-r3"]])
            await time.settle()
            XCTAssertEqual(opened, 1, "Completing the segmented goal must reuse the already-opened chat app.")
            XCTAssertEqual(typed, ["我晚点到"], "Typing must proceed once the utterance is complete.")
            voice.stop()
        }

        // 2. Live segmented turn ("给小王发消息说" -> "我晚点到")
        do {
            let time = FakeTime()
            var links: [FakeConnection] = []
            var opened = 0
            var sent = 0
            let voice = VoiceModel(
                clearTap: { _, _, _ in .clear },
                phoneTool: { name, arguments, _ in
                    let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
                    if name == "open_app" { opened += 1; return (chatScreen, false, nil) }
                    if name == "do" {
                        for action in args["actions"] as? [[String: Any]] ?? [] where (action["tap"] as? Int) == 3 { sent += 1 }
                    }
                    return (chatScreen, false, nil)
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
            XCTAssertTrue(voice.setBridge(BridgeStub.liveAddress))
            voice.onConversationEnded = { _, _ in }
            await voice.start()
            links.last?.play(["type": "session.started"],
                             ["type": "session.input_transcript.delta", "delta": "给小王发消息说", "start_ms": 0, "end_ms": 600],
                             ["type": "session.delegation.created", "delegation": ["id": "live-d1"]])
            links.last?.call("live-open", "open_app", arguments: #"{"app":"微信"}"#, delegation: "live-d1")
            links.last?.call("live-send-half", "do", arguments: #"{"actions":[{"tap":3}]}"#, delegation: "live-d1")
            await time.settle()
            XCTAssertEqual(opened, 1, "Live must allow low-risk open_app while utterance is incomplete.")
            XCTAssertEqual(sent, 0, "Live must block sending while utterance is incomplete.")
            voice.stop()
        }

        // 3. ChatGPT subscription voice (CodexVoice) partial delta + segmented turn
        do {
            let codexStorage = try IsolatedTestStorage(prefix: "voice-goal-codex")
            defer { try? codexStorage.tearDown() }
            VoiceDirect.setEnabled(false, in: codexStorage.storage)
            try codexStorage.seedCodexCredential(accessToken: "fixture-codex-partial-token")
            ModelKeys.setSelectedProvider(.chatgpt, in: codexStorage.storage)

            let codex = GoalTestSubscriptionVoice()
            let time = FakeTime()
            var links: [FakeConnection] = []
            var opened = 0
            var typed: [String] = []
            var sent = 0
            let voice = VoiceModel(
                clearTap: { _, _, _ in .clear },
                phoneTool: { name, arguments, _ in
                    let args = (try? JSONSerialization.jsonObject(with: Data(arguments.utf8))) as? [String: Any] ?? [:]
                    if name == "open_app" { opened += 1; return (chatScreen, false, nil) }
                    if name == "do" {
                        for action in args["actions"] as? [[String: Any]] ?? [] {
                            if (action["tap"] as? Int) == 3 { sent += 1 }
                            if let text = action["type"] as? String { typed.append(text) }
                        }
                    }
                    return (chatScreen, false, nil)
                },
                connection: { onEvent, onClosed in
                    let link = FakeConnection()
                    link.onEvent = onEvent
                    link.onClosed = onClosed
                    links.append(link)
                    return link
                },
                time: time.clock,
                codex: codex,
                storage: codexStorage.storage
            )
            voice.onConversationEnded = { _, _ in }
            await voice.start()

            codex.notify("thread/realtime/transcript/delta", ["role": "user", "delta": "给小王发消息说"])
            let openPrep = await codex.callTool("open_app", #"{"app":"微信"}"#)
            XCTAssertEqual(openPrep?.failed, false, "Codex voice must allow low-risk open_app during partial delta.")
            let earlySend = await codex.callTool("do", #"{"actions":[{"tap":3}]}"#)
            XCTAssertEqual(earlySend?.failed, true, "Codex voice must block sending during partial delta.")

            codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "给小王发消息说"])
            let halfSend = await codex.callTool("do", #"{"actions":[{"tap":3}]}"#)
            XCTAssertEqual(halfSend?.failed, true, "Codex voice must block sending on segmented incomplete utterance.")

            codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "确认"])
            let ackSend = await codex.callTool("do", #"{"actions":[{"tap":3}]}"#)
            XCTAssertEqual(ackSend?.failed, true, "Spoken 确认 in Codex voice must not complete the utterance or allow sending.")

            codex.notify("thread/realtime/transcript/done", ["role": "user", "text": "我晚点到"])
            let fullType = await codex.callTool("do", #"{"actions":[{"tap":2},{"type":"我晚点到"}]}"#)
            XCTAssertEqual(fullType?.failed, false, "Codex voice must allow typing after the utterance completes.")
            XCTAssertEqual(opened, 1)
            XCTAssertEqual(typed, ["我晚点到"])
            XCTAssertEqual(sent, 0)
            voice.stop()
        }
    }

    func testSpokenConfirmationNeverApprovesWaitingSensitiveStepOrCreatesNewTask() async throws {
        URLProtocol.registerClass(BridgeStub.self)
        defer { URLProtocol.unregisterClass(BridgeStub.self) }

        var tracker = VoiceGoalTracker()
        let t0 = Date(timeIntervalSince1970: 5_000)
        let u1 = tracker.ingestCompleteUtterance(text: "打开微信给小王写我晚点到，先别发送", itemID: "u1", delegationID: "d1", source: .ownerMicrophone, at: t0)
        for spoken in ["好的", "确认", "确定", "同意", "批准", "yes", "confirm", "approve", "好的，确认"] {
            let record = tracker.ingestCompleteUtterance(text: spoken, itemID: "ack-\(spoken)", delegationID: nil, source: .ownerMicrophone, at: t0.addingTimeInterval(1))
            XCTAssertEqual(record.relation, .chitchat, "Spoken affirmation \(spoken) must stay chitchat/call-control, never a new task or send clearance.")
            XCTAssertEqual(tracker.activeGoal?.id, u1.goalID, spoken)
            XCTAssertEqual(tracker.activeGoal?.forbidsSend, true, "Spoken affirmation \(spoken) must never lift forbidsSend.")
        }

        // Live: spoken "确认" must be rejected as acknowledgment, never creating a new active task.
        let time = FakeTime()
        var links: [FakeConnection] = []
        var liveToolRuns: [String] = []
        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, _, _ in
                liveToolRuns.append(name)
                return ("ok", false, nil)
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
        XCTAssertTrue(voice.setBridge(BridgeStub.liveAddress))
        voice.onConversationEnded = { _, _ in }
        await voice.start()
        links.last?.play(["type": "session.started"],
                         ["type": "session.input_transcript.delta", "delta": "打开微信给小王写我晚点到，先别发", "start_ms": 0, "end_ms": 800],
                         ["type": "session.delegation.created", "delegation": ["id": "d1"]])
        links.last?.call("c-open", "open_app", arguments: #"{"app":"微信"}"#, delegation: "d1")
        await time.settle()
        links.last?.play(["type": "session.input_transcript.delta", "delta": "确认", "start_ms": 1200, "end_ms": 1500],
                         ["type": "session.delegation.created", "delegation": ["id": "d-confirm"]])
        links.last?.call("c-confirm-send", "do", arguments: #"{"actions":[{"tap":"发送"}]}"#, delegation: "d-confirm")
        await time.settle()
        XCTAssertEqual(liveToolRuns, ["open_app"], "Live delegation for spoken 确认 must not run sensitive device actions.")
        voice.stop()
    }

    func testGuardedCallingPokiAndUngroundedAppsAreBlockedDuringPartialUtterance() {
        XCTAssertEqual(
            VoiceAppIdentity.detectApp(in: "打开备忘录记一下电话号码"),
            "com.apple.mobilenotes",
            "Ordinary mention of phone number in Notes must not resolve to Phone app."
        )
        XCTAssertEqual(VoiceAppIdentity.canonical("钱包"), "com.apple.passbook")
        XCTAssertEqual(VoiceAppIdentity.canonical("电话"), "com.apple.mobilephone")
        XCTAssertTrue(VoiceAppIdentity.isPoki("nz.zheha.poki"))

        var tracker = VoiceGoalTracker()
        tracker.ingestPartialUtterance(text: "给小王发消息说", itemID: "p1", source: .ownerMicrophone, replace: false)
        let binding = tracker.resolveBinding(delegationID: nil, responseID: nil, speechItemID: "p1", defaultSource: .ownerMicrophone)
        XCTAssertTrue(binding.awaitingTranscript)

        for (id, appName) in [("c-wallet", "钱包"), ("c-phone", "电话"), ("c-facetime", "FaceTime"), ("c-poki", "Poki"), ("c-notes", "备忘录")] {
            let proposal = VoiceToolProposal(
                call: VoiceCall(id: id, name: "open_app", arguments: #"{"app":"\#(appName)"}"#, session: 1, speechItem: "p1"),
                goalID: binding.goalID, goalRevision: binding.revision, source: binding.source,
                awaitingUtteranceTranscript: true
            )
            if case .deny(_, let code, _, _) = tracker.admit(proposal, session: 1) {
                XCTAssertEqual(code, .partialUtteranceRequiresCompletion, "\(appName) must be blocked during messaging partial utterance.")
            } else {
                XCTFail("Expected partial denial for \(appName).")
            }
        }

        for (id, tool, args) in [
            ("c-look", "look", "{}"),
            ("c-home", "go_home", "{}"),
            ("c-wait", "do", #"{"actions":[{"wait":300}]}"#),
            ("c-wechat", "open_app", #"{"app":"微信"}"#),
        ] {
            let proposal = VoiceToolProposal(
                call: VoiceCall(id: id, name: tool, arguments: args, session: 1, speechItem: "p1"),
                goalID: binding.goalID, goalRevision: binding.revision, source: binding.source,
                awaitingUtteranceTranscript: true
            )
            guard case .allow = tracker.admit(proposal, session: 1) else {
                return XCTFail("Low-risk preparation \(tool) \(args) must be allowed during partial utterance.")
            }
        }
    }

    func testBridgedTapAwaitingOnDeviceApprovalBlocksSpokenConfirmationAndRetryUntilOwnerResolves() async throws {
        URLProtocol.registerClass(BridgedTapCheckStub.self)
        defer {
            BridgedTapCheckStub.reset()
            URLProtocol.unregisterClass(BridgedTapCheckStub.self)
        }
        BridgedTapCheckStub.reset()

        let time = FakeTime()
        var links: [FakeConnection] = []
        var tapContinuation: CheckedContinuation<TapClearance, Never>?
        let tapWaiting = expectation(description: "bridged tap suspended on clearTap")

        let voice = VoiceModel(
            clearTap: { _, _, _ in
                await withCheckedContinuation { continuation in
                    tapContinuation = continuation
                    tapWaiting.fulfill()
                }
            },
            phoneTool: { _, _, _ in ("ok", false, nil) },
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
        XCTAssertTrue(voice.setBridge(BridgedTapCheckStub.address))
        voice.onConversationEnded = { _, _ in }
        await voice.start()

        links.last?.play(["type": "session.created"],
                         ["type": "conversation.item.input_audio_transcription.completed", "item_id": "u-send", "transcript": "给小王发消息说我晚点到"],
                         ["type": "response.created", "response": ["id": "r-send"]],
                         ["type": "response.output_item.done", "response_id": "r-send",
                          "item": ["type": "function_call", "call_id": "c-tap-send", "name": "tap_text", "arguments": #"{"text":"发送"}"#]],
                         ["type": "response.done", "response": ["id": "r-send"]])
        await fulfillment(of: [tapWaiting], timeout: 3.0)
        XCTAssertTrue(voice.hasPendingOnDeviceApproval, "Sensitive bridged tap must mark an on-device approval as pending while waiting for owner.")

        // Owner speaks "好的" and "确认", and the model tries to re-invoke tap_text / do -> must be denied.
        links.last?.play(["type": "conversation.item.input_audio_transcription.completed", "item_id": "u-ok", "transcript": "好的"],
                         ["type": "conversation.item.input_audio_transcription.completed", "item_id": "u-confirm", "transcript": "确认"],
                         ["type": "response.created", "response": ["id": "r-retry"]],
                         ["type": "response.output_item.done", "response_id": "r-retry",
                          "item": ["type": "function_call", "call_id": "c-tap-retry", "name": "tap_text", "arguments": #"{"text":"发送"}"#]],
                         ["type": "response.done", "response": ["id": "r-retry"]])
        await time.settle()

        let retryCall = try XCTUnwrap(voice.calls.first(where: { $0.id == "c-tap-retry" }))
        XCTAssertEqual(retryCall.state, .failed)
        XCTAssertTrue(retryCall.output.contains("on-device confirmation"), retryCall.output)
        XCTAssertEqual(BridgedTapCheckStub.checkedTaps, 0, "Spoken confirmation must never release or execute the waiting tap.")
        XCTAssertTrue(voice.hasPendingOnDeviceApproval)

        // Only the owner resolving the on-device card completes the waiting call.
        tapContinuation?.resume(returning: .declined("sending a message (\"发送\")"))
        tapContinuation = nil
        await time.settle()
        XCTAssertFalse(voice.hasPendingOnDeviceApproval)
        XCTAssertEqual(BridgedTapCheckStub.checkedTaps, 0)
        voice.stop()
    }

    func testAppModelOnDeviceApprovalLifecycleBlocksSpokenConfirmationAcrossVoiceAndDictationPaths() async throws {
        let originalApp = AskPoki.app
        let originalChat = AskPoki.chat
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), storage: storage.storage)
        let chat = ChatModel(app: app)
        AskPoki.install(app: app, chat: chat)
        defer {
            if let originalApp, let originalChat { AskPoki.install(app: originalApp, chat: originalChat) }
        }
        app.approvalMode = .confirm

        async let connectorResult = app.clearConnectorStep(connector: "WeChat", summary: "Tap “发送”", always: true)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.approvals.isEmpty }, object: nil)], timeout: 2.0)
        let pending = try XCTUnwrap(app.approvals.first)
        XCTAssertTrue(app.voice.hasPendingOnDeviceApproval, "AppModel.askOwner must sync pending on-device approval state to VoiceModel.")

        // 1. Dictation path refuses spoken "好的" / "确认" without sending to chat or clearing approval.
        let entriesBeforeDictation = chat.entries.count
        let dictation = Dictation()
        app.voice.activateDictation(dictation, listen: {})
        await app.voice.finishDictation(dictation, read: { "好的" }).value
        await app.voice.finishDictation(dictation, read: { "确认" }).value
        XCTAssertTrue(app.approvals.contains(where: { $0.id == pending.id }), "Dictated 好的/确认 must leave on-device approval pending.")
        XCTAssertEqual(chat.entries.count, entriesBeforeDictation, "Dictated 好的/确认 while approval waits must not forward a chat turn.")
        XCTAssertFalse(chat.entries.contains { if case .you = $0.kind { return true }; return false })
        XCTAssertTrue(app.voice.lines.contains(where: { $0.role == .note }), "Dictation must inform the owner that an approval is waiting on device.")

        // 2. Execution gate denies mutating steps while on-device approval waits.
        var tracker = app.voice.goalTracker
        let goalRecord = tracker.ingestCompleteUtterance(text: "给小王发消息说我晚点到", itemID: "u-live-wait", delegationID: "d-wait", source: .ownerMicrophone, at: Date())
        let sendProposal = VoiceToolProposal(
            call: VoiceCall(id: "c-send-wait", name: "do", arguments: #"{"actions":[{"tap":"发送"}]}"#, session: 1),
            goalID: goalRecord.goalID, goalRevision: goalRecord.revision, source: .ownerMicrophone
        )
        if case .deny(_, let code, _, _) = tracker.admit(sendProposal, session: 1) {
            XCTAssertEqual(code, .awaitingOnDeviceApproval)
        } else {
            XCTFail("Expected .awaitingOnDeviceApproval while AppModel holds a pending on-device approval.")
        }

        // 3. On-device owner resolution clears both AppModel and VoiceModel pending state.
        app.resolve(pending, approved: false)
        let allowed = await connectorResult
        XCTAssertFalse(allowed)
        await fulfillment(of: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !app.voice.hasPendingOnDeviceApproval }, object: nil)], timeout: 2.0)
        XCTAssertTrue(app.approvals.isEmpty)
        app.voice.stop()
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSimulatorPartialPrepRehearsalOpensChatAppWithoutSendingOrAcceptingSpokenApproval() async throws {
        UserDefaults.standard.set("partial-prep", forKey: "pokiTalkRehearsal")
        defer { UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal") }
        TalkRehearsal.resetPartialPrepState()

        let voice = VoiceModel(
            clearTap: { _, _, _ in .clear },
            phoneTool: { name, arguments, _ in await TalkRehearsal.step(name: name, arguments: arguments) },
            connection: VoiceModel.connection,
            storage: storage.storage
        )
        voice.onConversationEnded = { _, _ in }
        await voice.start(microphone: false)
        let draftReady = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                voice.lines.contains { $0.role == .poki && $0.text.contains("未发送") }
            },
            object: nil
        )
        await fulfillment(of: [draftReady], timeout: 8)

        XCTAssertEqual(TalkRehearsal.partialPrepState.opened, 1, "Partial utterance rehearsal must open the chat app once.")
        XCTAssertEqual(TalkRehearsal.partialPrepState.typed, ["我晚点到"], "Message typing must run only after the second segment completes.")
        XCTAssertEqual(TalkRehearsal.partialPrepState.sent, 0, "Partial prep rehearsal must never send.")
        XCTAssertEqual(TalkRehearsal.partialPrepState.callLog.count, 2, "Only open_app and final type do should execute: \(TalkRehearsal.partialPrepState.callLog)")
        XCTAssertTrue(TalkRehearsal.partialPrepState.callLog.first?.hasPrefix("open_app:") == true)

        voice.setPendingOnDeviceApproval(id: "sim-approval-1", reason: "sending a message (\"发送\")")
        let goal = try XCTUnwrap(voice.goalTracker.activeGoal)
        let decision = VoiceExecutionGate.evaluate(
            proposal: VoiceToolProposal(
                call: VoiceCall(id: "sim-send", name: "do", arguments: #"{"actions":[{"tap":3}]}"#, session: 1),
                goalID: goal.id, goalRevision: goal.revision, source: .silentTest
            ),
            goal: goal,
            currentSession: 1,
            pendingApprovalReason: voice.goalTracker.pendingOnDeviceApprovalReason
        )
        if case .deny(_, let code, _, _) = decision {
            XCTAssertEqual(code, .awaitingOnDeviceApproval)
        } else {
            XCTFail("Expected pending on-device approval to block send step in rehearsal.")
        }
        voice.clearPendingOnDeviceApproval(id: "sim-approval-1")
        voice.stop()
    }
    #endif
}

private final class BridgedTapCheckStub: URLProtocol {
    static let address = "http://voice-bridge-check.test/voice/0123456789abcdef"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _checkedTaps = 0
    static var checkedTaps: Int { lock.withLock { _checkedTaps } }
    static func reset() { lock.withLock { _checkedTaps = 0 } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == "voice-bridge-check.test"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: String
        if request.url?.lastPathComponent == "tool" {
            let data = readRequestBody(request)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if json?["checked"] != nil {
                Self.lock.withLock { Self._checkedTaps += 1 }
                body = #"{"state":"done","output":"tapped 发送"}"#
            } else {
                body = #"{"state":"check","app":{"bundle_id":"com.tencent.xin","name":"WeChat"},"target":{"text":"发送","says":"发送"}}"#
            }
        } else {
            body = #"{"value":"ek_test","model":"gpt-realtime","local_tools":["get_ios_version"]}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func readRequestBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody, !body.isEmpty { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            out.append(buffer, count: count)
        }
        return out
    }
}

@MainActor
private final class GoalTestSubscriptionVoice: SubscriptionVoice {
    private var onEvent: ((String, [String: Any]) -> Void)?
    private var onTool: ((String, String) async -> PhoneAnswer)?

    func prepare(onEvent: @escaping (String, [String: Any]) -> Void, onTool: @escaping (String, String) async -> PhoneAnswer) async throws {
        self.onEvent = onEvent
        self.onTool = onTool
    }

    func start(offer: String) async throws -> String { "fixture-sdp-answer" }
    func stop() { onEvent = nil; onTool = nil }
    func notify(_ method: String, _ params: [String: Any]) { onEvent?(method, params) }
    func callTool(_ name: String, _ arguments: String) async -> PhoneAnswer? { await onTool?(name, arguments) }
}
