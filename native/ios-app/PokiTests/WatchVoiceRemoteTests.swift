import AVFAudio
import Foundation
import XCTest
@testable import Poki

private final class RemoteTestConnection: VoiceConnection, @unchecked Sendable {
    var onEvent: (@MainActor ([String: Any]) -> Void)?
    var onClosed: (@MainActor (String) -> Void)?
    private let lock = NSLock()
    private var localAudioEnabledStorage = true
    private var closedStorage = false
    private var connectErrorStorage: Error?
    private var remoteLevelStorage: Double = 0

    var localAudioEnabled: Bool { lock.withLock { localAudioEnabledStorage } }
    var closed: Bool { lock.withLock { closedStorage } }

    func setConnectError(_ error: Error?) { lock.withLock { connectErrorStorage = error } }
    func setRemoteLevel(_ level: Double) { lock.withLock { remoteLevelStorage = level } }

    @MainActor func connect(secret: String, base: URL?, microphone: Bool, direct: Bool) async throws {
        if let error = lock.withLock({ connectErrorStorage }) { throw error }
    }

    @MainActor func connectLive(microphone: Bool, direct: Bool, exchange: (String) async throws -> String) async throws {
        if let error = lock.withLock({ connectErrorStorage }) { throw error }
    }

    func hasRemoteSpeech() async -> Bool { lock.withLock { remoteLevelStorage > 0.005 } }
    func remoteAudioLevel() async -> Double? { lock.withLock { remoteLevelStorage } }
    func send(_ event: [String: Any]) -> Bool { true }
    func setRemoteVolume(_ value: Double) {}
    func setLocalAudioEnabled(_ enabled: Bool) { lock.withLock { localAudioEnabledStorage = enabled } }
    @MainActor func diagnose(_ write: @escaping @MainActor (String) -> Void) {}
    @MainActor func close() { lock.withLock { closedStorage = true } }

    @MainActor func play(_ event: [String: Any]) { onEvent?(event) }
}

@MainActor
private final class FakeWatchVoiceTransport: WatchVoiceTransport {
    var isActivated = true
    var isPaired = true
    var isWatchAppInstalled = true
    var isReachable = true
    var applicationContext: [String: Any] = [:]
    var sentMessages: [[String: Any]] = []
    var sentMessageData: [Data] = []
    var transferredUserInfo: [[String: Any]] = []

    func updateApplicationContext(_ context: [String: Any]) throws {
        applicationContext = context
    }

    func sendMessage(_ message: [String: Any]) {
        sentMessages.append(message)
    }

    func sendMessageData(_ data: Data) {
        sentMessageData.append(data)
    }

    func transferUserInfo(_ userInfo: [String: Any]) {
        transferredUserInfo.append(userInfo)
    }

    func decodedRemoteSnapshot() throws -> WatchVoiceRemoteSnapshot {
        let data = try XCTUnwrap(applicationContext[WatchVoiceRemote.contextKey] as? Data)
        return try JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: data)
    }
}

@MainActor
final class WatchVoiceRemoteTests: XCTestCase {
    private var previousBridge: VoiceBridge?
    private var previousRehearsal: Any?
    private var previousHold: Any?

    override func setUp() async throws {
        previousBridge = VoiceBridge.saved
        previousRehearsal = UserDefaults.standard.object(forKey: "pokiTalkRehearsal")
        previousHold = UserDefaults.standard.object(forKey: "pokiTalkHold")
        UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal")
        UserDefaults.standard.removeObject(forKey: "pokiTalkHold")
        URLProtocol.registerClass(BridgeStub.self)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(BridgeStub.self)
        VoiceBridge.saved = previousBridge
        if let previousRehearsal { UserDefaults.standard.set(previousRehearsal, forKey: "pokiTalkRehearsal") }
        else { UserDefaults.standard.removeObject(forKey: "pokiTalkRehearsal") }
        if let previousHold { UserDefaults.standard.set(previousHold, forKey: "pokiTalkHold") }
        else { UserDefaults.standard.removeObject(forKey: "pokiTalkHold") }
    }

    @MainActor
    private final class Harness {
        let time = FakeTime()
        let connection = RemoteTestConnection()
        let voice: VoiceModel
        var host: WatchVoiceRemoteHost!
        var snapshots: [WatchVoiceRemoteSnapshot] = []
        var fullResults: [WatchVoiceUpdate] = []
        var preparedCount = 0
        var foregroundRequestedCount = 0
        var isProtectedDataAvailable = true
        var isSetupReady = true
        var isBusy = false
        var hasMicrophonePermission = true
        var stepOverride: String?
        var toolGate: CheckedContinuation<PhoneAnswer, Never>?

        init(epoch: UInt64 = 10, bridgeAddress: String? = BridgeStub.address, suspendPhoneTool: Bool = false) {
            let conn = connection
            var ownerBox: Harness?
            voice = VoiceModel(
                clearTap: { _, _, _ in .clear },
                phoneTool: { _, _, _ in
                    if suspendPhoneTool {
                        return await withCheckedContinuation { continuation in
                            ownerBox?.toolGate = continuation
                        }
                    }
                    return ("ok", false, nil)
                },
                connection: { onEvent, onClosed in
                    conn.onEvent = onEvent
                    conn.onClosed = onClosed
                    return conn
                },
                time: time.clock
            )
            ownerBox = self
            if let bridgeAddress { _ = voice.setBridge(bridgeAddress) }
            host = WatchVoiceRemoteHost(
                voice: voice,
                environment: WatchVoiceRemoteEnvironment(
                    isProtectedDataAvailable: { [unowned self] in self.isProtectedDataAvailable },
                    isSetupReady: { [unowned self] in self.isSetupReady && self.voice.canTalkLive },
                    isBusy: { [unowned self] in self.isBusy },
                    hasMicrophonePermission: { [unowned self] in self.hasMicrophonePermission },
                    currentStep: { [unowned self] in self.stepOverride ?? self.voice.activeStepDescription },
                    prepareForVoice: { [unowned self] in self.preparedCount += 1 },
                    stopVoice: { [unowned self] in self.voice.stop() },
                    requestForegroundContinuation: { [unowned self] in self.foregroundRequestedCount += 1 },
                    now: { [unowned self] in self.time.now }
                ),
                epoch: epoch
            )
            host.onSnapshot = { [weak self] snapshot in
                self?.snapshots.append(snapshot)
            }
            host.onResult = { [weak self] result in
                self?.fullResults.append(result)
            }
            host.startObserving()
        }
    }

    func testStartMuteUnmuteAndEndLifecycleWithExplicitMuteIdempotency() async throws {
        let h = Harness()

        let startReply = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(startReply.outcome, .accepted)
        XCTAssertEqual(startReply.snapshot.state, .connecting)
        let callID = try XCTUnwrap(startReply.snapshot.callID)
        XCTAssertFalse(startReply.snapshot.isMuted)
        XCTAssertEqual(h.preparedCount, 1)

        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        let listening = h.host.currentSnapshot()
        XCTAssertEqual(listening.state, .listening)
        XCTAssertEqual(listening.callID, callID)
        XCTAssertTrue(listening.transportConnected)
        XCTAssertTrue(listening.inputReady)

        // Dynamic Island voice states flow through without renaming.
        h.connection.play(["type": "input_audio_buffer.speech_stopped"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .thinking)

        h.connection.play(["type": "output_audio_buffer.started"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .speaking)

        h.connection.play(["type": "output_audio_buffer.stopped"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .listening)

        // Explicit mute sets muted once; sending setMuted(true) again never toggles back.
        let mute1 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(true), targetCallID: callID))
        XCTAssertEqual(mute1.outcome, .accepted)
        XCTAssertEqual(mute1.snapshot.state, .muted)
        XCTAssertTrue(mute1.snapshot.isMuted)
        XCTAssertFalse(mute1.snapshot.inputReady)
        XCTAssertFalse(h.connection.localAudioEnabled)

        let mute2 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(true), targetCallID: callID))
        XCTAssertEqual(mute2.outcome, .noChange)
        XCTAssertEqual(mute2.snapshot.state, .muted)
        XCTAssertTrue(mute2.snapshot.isMuted)
        XCTAssertFalse(h.connection.localAudioEnabled)

        let unmute = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(false), targetCallID: callID))
        XCTAssertEqual(unmute.outcome, .accepted)
        XCTAssertEqual(unmute.snapshot.state, .listening)
        XCTAssertFalse(unmute.snapshot.isMuted)
        XCTAssertTrue(unmute.snapshot.inputReady)
        XCTAssertTrue(h.connection.localAudioEnabled)

        // End with mismatched call ID is rejected without ending the active call.
        let wrongEnd = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: "stale-call"))
        XCTAssertEqual(wrongEnd.outcome, .callChanged)
        XCTAssertTrue(h.voice.isOn)

        // End with matching call ID ends the active call.
        let end = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID))
        XCTAssertEqual(end.outcome, .accepted)
        XCTAssertEqual(end.snapshot.state, .idle)
        XCTAssertNil(end.snapshot.callID)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertTrue(h.connection.closed)
    }

    func testExpiredCommandDoesNotExecuteAndDuplicateRequestReturnsCachedReply() async throws {
        let h = Harness()

        let expiredStart = WatchVoiceRemoteCommand(
            issuedAt: h.time.now.addingTimeInterval(-11),
            action: .start
        )
        let expiredReply = h.host.handle(expiredStart)
        XCTAssertEqual(expiredReply.outcome, .expired)
        XCTAssertEqual(expiredReply.requestID, expiredStart.requestID)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.preparedCount, 0)

        let futureStart = WatchVoiceRemoteCommand(
            issuedAt: h.time.now.addingTimeInterval(3),
            action: .start
        )
        let futureReply = h.host.handle(futureStart)
        XCTAssertEqual(futureReply.outcome, .expired)
        XCTAssertFalse(h.voice.isOn)

        let startCmd = WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start)
        let firstReply = h.host.handle(startCmd)
        XCTAssertEqual(firstReply.outcome, .accepted)
        XCTAssertEqual(h.preparedCount, 1)

        // Even after advancing past the command window, retrying the same requestID returns the original cached reply without re-executing.
        await h.time.advance(15)
        let duplicateReply = h.host.handle(startCmd)
        XCTAssertEqual(duplicateReply, firstReply)
        XCTAssertEqual(h.preparedCount, 1)

        let callID = try XCTUnwrap(firstReply.snapshot.callID)
        let endCmd = WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID)
        let endFirst = h.host.handle(endCmd)
        XCTAssertEqual(endFirst.outcome, .accepted)

        // Start a second call, then replay the first call's end requestID: cached reply returns without ending the second call.
        let secondStart = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(secondStart.outcome, .accepted)
        XCTAssertTrue(h.voice.isOn)
        let replayedEnd = h.host.handle(endCmd)
        XCTAssertEqual(replayedEnd, endFirst)
        XCTAssertTrue(h.voice.isOn)
        h.voice.stop()
    }

    func testStartReturnsRequiresForegroundWhenMicMissingOrProtectedDataUnavailable() {
        let h = Harness()
        h.hasMicrophonePermission = false

        let noMic = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(noMic.outcome, .requiresForeground)
        XCTAssertTrue(noMic.snapshot.requiresForeground)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.foregroundRequestedCount, 1)

        h.hasMicrophonePermission = true
        h.isProtectedDataAvailable = false

        let locked = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(locked.outcome, .requiresForeground)
        XCTAssertTrue(locked.snapshot.requiresForeground)
        XCTAssertFalse(h.voice.isOn)
        XCTAssertEqual(h.foregroundRequestedCount, 2)
    }

    func testBackgroundAudioRestrictionDetectedAsForegroundRequired() {
        let restricted = NSError(
            domain: NSOSStatusErrorDomain,
            code: AVAudioSession.ErrorCode.cannotStartPlaying.rawValue
        )
        XCTAssertTrue(VoiceModel.isBackgroundAudioRestriction(restricted))
        let network = URLError(.timedOut)
        XCTAssertFalse(VoiceModel.isBackgroundAudioRestriction(network))
    }

    func testReducerDropsStaleSnapshotsByEpochAndSequenceAndFiltersMeterWindow() {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        func snap(epoch: UInt64, seq: UInt64, state: WatchVoiceCallState, callID: String? = "call-1") -> WatchVoiceRemoteSnapshot {
            WatchVoiceRemoteSnapshot(
                epoch: epoch,
                sequence: seq,
                state: state,
                callID: callID,
                isMuted: state == .muted,
                transportConnected: state == .listening || state == .muted,
                inputReady: state == .listening,
                requiresForeground: false,
                updatedAt: baseTime,
                detail: nil
            )
        }

        var reducer = WatchVoiceRemoteStateReducer()
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 2, seq: 5, state: .listening)))
        // Older sequence in same epoch is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 2, seq: 4, state: .connecting)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Duplicate (same epoch and sequence) is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 2, seq: 5, state: .muted)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Older epoch with higher sequence is dropped.
        XCTAssertFalse(reducer.apply(snapshot: snap(epoch: 1, seq: 99, state: .idle, callID: nil)))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        // Newer epoch with sequence 1 supersedes older epoch.
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 3, seq: 1, state: .muted, callID: "call-2")))
        XCTAssertEqual(reducer.latestSnapshot?.state, .muted)
        XCTAssertEqual(reducer.latestSnapshot?.epoch, 3)

        // Meter matching active epoch, callID, and [-0.5, 1.2]s window updates level.
        let validMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-2", level: 180, timestamp: baseTime.addingTimeInterval(-0.4))
        XCTAssertTrue(reducer.apply(meter: validMeter, now: baseTime))
        XCTAssertEqual(reducer.meterLevel, 180)

        // Meter from stale timestamp or wrong callID is rejected.
        let oldMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-2", level: 50, timestamp: baseTime.addingTimeInterval(-1.5))
        XCTAssertFalse(reducer.apply(meter: oldMeter, now: baseTime))
        let wrongCallMeter = WatchVoiceRemoteMeter(epoch: 3, callID: "call-1", level: 20, timestamp: baseTime)
        XCTAssertFalse(reducer.apply(meter: wrongCallMeter, now: baseTime))
        XCTAssertEqual(reducer.meterLevel, 180)
    }

    func testLiveStepAndLongResultUseSharedChunkedDelivery() async throws {
        let h = Harness(bridgeAddress: BridgeStub.liveAddress, suspendPhoneTool: true)
        let start = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start.outcome, .accepted)
        let callID = try XCTUnwrap(start.snapshot.callID)
        await h.time.settle()
        h.connection.play(["type": "session.started"])
        await h.time.settle()

        // Running open_app emits a one-line currentStep naming the app.
        h.connection.play([
            "type": "response.event",
            "delegation_id": "d1",
            "event": [
                "type": "response.output_item.done",
                "item": [
                    "type": "function_call",
                    "call_id": "call-open-wechat",
                    "name": "open_app",
                    "arguments": #"{"app":"WeChat"}"#,
                ],
            ],
        ])
        await h.time.settle()

        let duringStep = h.host.currentSnapshot()
        XCTAssertEqual(duringStep.state, .thinking)
        XCTAssertEqual(duringStep.currentStep, "Opening WeChat")

        h.toolGate?.resume(returning: ("opened WeChat", false, nil))
        h.toolGate = nil
        await h.time.settle()

        // Long spoken answer (> 32,768 UTF-8 bytes) delivers a preview with fullTextBytes in snapshot
        // while persisting to WatchVoiceResultJournal for multi-chunk (>= 3 chunks) #591 retrieval.
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-voice-journal-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: journalURL) }
        let writerJournal = WatchVoiceResultJournal(url: journalURL)
        h.host.onResult = { [weak h] result in
            h?.fullResults.append(result)
            try? writerJournal.store(result)
        }

        let longText = String(repeating: "Detailed result line 漢字 e\u{0301}.\n", count: 1_150) + "Final marker."
        XCTAssertGreaterThan(longText.utf8.count, WatchVoiceRequest.resultChunkBytes * 2)
        h.connection.play(["type": "session.output_transcript.delta", "delta": longText, "start_ms": 0, "end_ms": 900])
        h.connection.play(["type": "response.event", "delegation_id": "d1", "event": ["type": "response.completed", "response": ["id": "r1"]]])
        await h.time.settle()

        // Ending a Live session transitions through `.ending` until `session.closed` returns `.idle`.
        let end = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID))
        XCTAssertEqual(end.outcome, .accepted)
        XCTAssertEqual(end.snapshot.state, .ending)

        let delivered = try XCTUnwrap(end.snapshot.latestResult)
        XCTAssertEqual(delivered.phase, .finished)
        XCTAssertEqual(delivered.fullTextBytes, longText.utf8.count)
        XCTAssertNotEqual(delivered.text, longText)

        // Reload a fresh journal from disk and fetch via the real channel message-data handler.
        let reloadedChannel = WatchVoiceRemoteChannel(
            remoteHost: h.host,
            resultJournal: WatchVoiceResultJournal(url: journalURL),
            transport: FakeWatchVoiceTransport()
        )
        var assembled = Data()
        var chunkSizes: [Int] = []
        while assembled.count < longText.utf8.count {
            let requestData = try JSONEncoder().encode(WatchVoiceRequest.result(id: delivered.id, offset: assembled.count))
            let chunk = reloadedChannel.handleMessageData(requestData)
            XCTAssertFalse(chunk.isEmpty)
            chunkSizes.append(chunk.count)
            assembled.append(chunk)
        }
        XCTAssertGreaterThanOrEqual(chunkSizes.count, 3)
        XCTAssertEqual(chunkSizes[0], WatchVoiceRequest.resultChunkBytes)
        XCTAssertEqual(chunkSizes[1], WatchVoiceRequest.resultChunkBytes)
        XCTAssertLessThan(try XCTUnwrap(chunkSizes.last), WatchVoiceRequest.resultChunkBytes)
        XCTAssertEqual(String(data: assembled, encoding: .utf8), longText)

        h.connection.play(["type": "session.closed", "reason": "done"])
        await h.time.settle()
        XCTAssertEqual(h.host.currentSnapshot().state, .idle)
        XCTAssertNil(h.host.currentSnapshot().currentStep)
    }

    func testUnexpectedConnectionLossEmitsSingleBlockedResult() async throws {
        let h = Harness()
        let start = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start.outcome, .accepted)
        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        h.connection.onClosed?("network dropped")
        await h.time.settle()

        let failed = h.host.currentSnapshot()
        XCTAssertEqual(failed.state, .failed)
        let delivered = try XCTUnwrap(failed.latestResult)
        XCTAssertEqual(delivered.phase, .blocked)
        XCTAssertEqual(h.fullResults.count, 1)
        XCTAssertEqual(h.fullResults.first?.id, delivered.id)

        // Querying state again keeps the same failure record without emitting a duplicate.
        let reread = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .state))
        XCTAssertEqual(reread.snapshot.latestResult?.id, delivered.id)
        XCTAssertEqual(h.fullResults.count, 1)
    }

    func testLocalToneSynthesisProducesValidDistinctWavBuffers() {
        let cues: [WatchVoiceCue] = [.start, .mute, .unmute, .end]
        let buffers = cues.map(WatchVoiceTone.wavData(for:))
        for data in buffers {
            XCTAssertGreaterThan(data.count, 44)
            XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        }
        XCTAssertEqual(Set(buffers).count, cues.count)
    }

    func testDelayedTargetedEndStillEndsActiveMutedCallWithoutEndingNewerCall() async throws {
        let h = Harness()
        let start1 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start1.outcome, .accepted)
        let callID1 = try XCTUnwrap(start1.snapshot.callID)
        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        let muted = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .setMuted(true), targetCallID: callID1))
        XCTAssertEqual(muted.outcome, .accepted)
        XCTAssertEqual(muted.snapshot.state, .muted)

        // Watch queues End while offline; 15 seconds pass before Phone receives it (beyond 10s command window).
        let endIssuedAt = h.time.now
        await h.time.advance(15)
        let delayedEnd = h.host.handle(WatchVoiceRemoteCommand(issuedAt: endIssuedAt, action: .end, targetCallID: callID1))
        XCTAssertEqual(delayedEnd.outcome, .accepted)
        XCTAssertEqual(delayedEnd.snapshot.state, .idle)
        XCTAssertFalse(h.voice.isOn)

        // A delayed End targeting callID1 arriving after callID2 starts must never terminate callID2.
        let start2 = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start2.outcome, .accepted)
        let callID2 = try XCTUnwrap(start2.snapshot.callID)
        XCTAssertNotEqual(callID1, callID2)
        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        let lateOldCallEnd = h.host.handle(WatchVoiceRemoteCommand(issuedAt: endIssuedAt, action: .end, targetCallID: callID1))
        XCTAssertEqual(lateOldCallEnd.outcome, .callChanged)
        XCTAssertTrue(h.voice.isOn)
        XCTAssertEqual(h.voice.callID, callID2)
        h.voice.stop()
    }

    func testStaleRepliesDoNotOverwriteNewerReducerStateOrClearContinueOnPhone() {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        func snap(
            epoch: UInt64,
            seq: UInt64,
            state: WatchVoiceCallState,
            callID: String?,
            requiresForeground: Bool = false,
            detail: String? = nil
        ) -> WatchVoiceRemoteSnapshot {
            WatchVoiceRemoteSnapshot(
                epoch: epoch,
                sequence: seq,
                state: state,
                callID: callID,
                isMuted: state == .muted,
                transportConnected: state.isActiveCall,
                inputReady: state == .listening,
                requiresForeground: requiresForeground,
                updatedAt: baseTime,
                detail: detail
            )
        }

        // Case 1: Late requiresForeground reply with older (epoch, seq) must NOT clobber active listening state.
        var reducer = WatchVoiceRemoteStateReducer()
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 2, seq: 5, state: .listening, callID: "call-1")))
        let staleForegroundReply = WatchVoiceRemoteReply(
            requestID: UUID(),
            outcome: .requiresForeground,
            snapshot: snap(epoch: 2, seq: 2, state: .idle, callID: nil, requiresForeground: true, detail: "Unlock iPhone"),
            detail: "Unlock iPhone"
        )
        XCTAssertFalse(reducer.apply(reply: staleForegroundReply))
        XCTAssertEqual(reducer.latestSnapshot?.state, .listening)
        XCTAssertFalse(reducer.pendingContinueOnPhone)
        XCTAssertNil(reducer.lastProblem)

        // Case 2: Late .state reply with older (epoch, seq) must NOT clear newer requiresForeground / detail.
        XCTAssertTrue(reducer.apply(snapshot: snap(
            epoch: 2,
            seq: 6,
            state: .failed,
            callID: nil,
            requiresForeground: true,
            detail: "Allow microphone access"
        )))
        let staleStateReply = WatchVoiceRemoteReply(
            requestID: UUID(),
            outcome: .accepted,
            snapshot: snap(epoch: 2, seq: 1, state: .idle, callID: nil, requiresForeground: false, detail: nil),
            detail: nil
        )
        XCTAssertFalse(reducer.apply(reply: staleStateReply))
        XCTAssertEqual(reducer.latestSnapshot?.state, .failed)
        XCTAssertTrue(reducer.pendingContinueOnPhone)
        XCTAssertEqual(reducer.lastProblem, "Allow microphone access")

        // Case 3: Same-version .state reply preserves requiresForeground and detail.
        let sameVersionStateReply = WatchVoiceRemoteReply(
            requestID: UUID(),
            outcome: .accepted,
            snapshot: snap(epoch: 2, seq: 6, state: .failed, callID: nil, requiresForeground: true, detail: nil),
            detail: nil
        )
        XCTAssertTrue(reducer.apply(reply: sameVersionStateReply))
        XCTAssertTrue(reducer.pendingContinueOnPhone)
        XCTAssertEqual(reducer.lastProblem, "Allow microphone access")

        // Case 4: Late reply targeting an older callID must NOT mutate a newer active call.
        XCTAssertTrue(reducer.apply(snapshot: snap(epoch: 2, seq: 8, state: .listening, callID: "call-2")))
        let wrongCallReply = WatchVoiceRemoteReply(
            requestID: UUID(),
            outcome: .failed,
            snapshot: snap(epoch: 2, seq: 8, state: .listening, callID: "call-2"),
            detail: "Stale error from call-1"
        )
        XCTAssertFalse(reducer.apply(reply: wrongCallReply, targetCallID: "call-1"))
        XCTAssertEqual(reducer.latestSnapshot?.callID, "call-2")
        XCTAssertNil(reducer.lastProblem)
    }

    func testWatchReducerKeepsEndAvailableWhileDisconnectedAndClearsOnConfirmOrCallChange() throws {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        func snap(seq: UInt64, state: WatchVoiceCallState, callID: String?) -> WatchVoiceRemoteSnapshot {
            WatchVoiceRemoteSnapshot(
                epoch: 4,
                sequence: seq,
                state: state,
                callID: callID,
                isMuted: state == .muted,
                transportConnected: state.isActiveCall,
                inputReady: state == .listening,
                requiresForeground: false,
                updatedAt: baseTime,
                detail: nil
            )
        }

        var reducer = WatchVoiceRemoteStateReducer()
        XCTAssertFalse(reducer.canShowEndButton)
        XCTAssertTrue(reducer.apply(snapshot: snap(seq: 1, state: .muted, callID: "call-A")))
        XCTAssertTrue(reducer.canShowEndButton)

        // Queue End while disconnected: subsequent taps reuse the same requestID for idempotent dedupe.
        let cmd1 = try XCTUnwrap(reducer.queueEnd(now: baseTime))
        let cmd2 = try XCTUnwrap(reducer.queueEnd(now: baseTime.addingTimeInterval(5)))
        XCTAssertEqual(cmd1.requestID, cmd2.requestID)
        XCTAssertEqual(cmd1.targetCallID, "call-A")
        XCTAssertNotNil(reducer.pendingEnd)
        XCTAssertTrue(reducer.canShowEndButton)

        // Newer snapshot still on the same active call preserves pendingEnd until Phone actually ends it.
        XCTAssertTrue(reducer.apply(snapshot: snap(seq: 2, state: .listening, callID: "call-A")))
        XCTAssertEqual(reducer.pendingEnd?.requestID, cmd1.requestID)

        // Reconnect reply confirming idle clears pendingEnd and hides End.
        let endReply = WatchVoiceRemoteReply(
            requestID: cmd1.requestID,
            outcome: .accepted,
            snapshot: snap(seq: 3, state: .idle, callID: nil),
            detail: nil
        )
        XCTAssertTrue(reducer.apply(reply: endReply, targetCallID: "call-A"))
        XCTAssertNil(reducer.pendingEnd)
        XCTAssertFalse(reducer.canShowEndButton)

        // If Phone already moved to call-B before queued End for call-A confirms, call-B snapshot clears stale pendingEnd.
        XCTAssertTrue(reducer.apply(snapshot: snap(seq: 4, state: .muted, callID: "call-A2")))
        _ = try XCTUnwrap(reducer.queueEnd(now: baseTime))
        XCTAssertNotNil(reducer.pendingEnd)
        XCTAssertTrue(reducer.apply(snapshot: snap(seq: 5, state: .listening, callID: "call-B")))
        XCTAssertNil(reducer.pendingEnd)
        XCTAssertTrue(reducer.canShowEndButton)
    }

    func testOfflineConsecutiveResultsRetainedForReconnectCatchUp() async throws {
        let h = Harness()
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-voice-offline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: journalURL) }
        let journal = WatchVoiceResultJournal(url: journalURL)
        h.host.onResult = { [weak h] result in
            h?.fullResults.append(result)
            try? journal.store(result)
        }

        let start = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        XCTAssertEqual(start.outcome, .accepted)
        let callID = try XCTUnwrap(start.snapshot.callID)
        await h.time.settle()
        h.connection.play(["type": "session.created"])
        await h.time.settle()

        // Turn 1 finishes (> 16 KB) while Watch is offline.
        let firstLongText = "First offline turn.\n" + String(repeating: "Alpha line 漢字.\n", count: 1_000) + "END_FIRST"
        XCTAssertGreaterThan(firstLongText.utf8.count, WatchVoiceRequest.resultChunkBytes)
        h.connection.play(["type": "response.created", "response": ["id": "resp-1"]])
        h.connection.play(["type": "output_audio_buffer.started"])
        h.connection.play(["type": "response.output_audio_transcript.done", "transcript": firstLongText])
        h.connection.play(["type": "response.done", "response": ["id": "resp-1"]])
        h.connection.play(["type": "output_audio_buffer.stopped"])
        await h.time.settle()
        XCTAssertEqual(h.fullResults.count, 1)
        let firstID = try XCTUnwrap(h.fullResults.first?.id)

        // Turn 2 finishes while Watch is still offline.
        h.connection.play(["type": "response.created", "response": ["id": "resp-2"]])
        h.connection.play(["type": "output_audio_buffer.started"])
        h.connection.play(["type": "response.output_audio_transcript.done", "transcript": "Second offline turn completed."])
        h.connection.play(["type": "response.done", "response": ["id": "resp-2"]])
        h.connection.play(["type": "output_audio_buffer.stopped"])
        await h.time.settle()
        XCTAssertEqual(h.fullResults.count, 2)
        let secondID = try XCTUnwrap(h.fullResults.last?.id)
        XCTAssertNotEqual(firstID, secondID)

        // Watch reconnects and pulls state: BOTH offline results must be present newest-first.
        let reconnectReply = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .state))
        XCTAssertEqual(reconnectReply.snapshot.recentResults.map(\.id), [secondID, firstID])
        let firstPreview = try XCTUnwrap(reconnectReply.snapshot.recentResults.last)
        XCTAssertEqual(firstPreview.fullTextBytes, firstLongText.utf8.count)

        // Merging into Watch history preserves chronological newest-first order and deduplicates retries.
        let (merged, added) = WatchVoiceRemote.mergeResults(reconnectReply.snapshot.deliveredResults, into: [])
        XCTAssertEqual(merged.map(\.id), [secondID, firstID])
        XCTAssertEqual(added.map(\.id), [secondID, firstID])
        let (mergedAgain, addedAgain) = WatchVoiceRemote.mergeResults(reconnectReply.snapshot.deliveredResults, into: merged)
        XCTAssertEqual(mergedAgain, merged)
        XCTAssertTrue(addedAgain.isEmpty)

        // Full text of the earlier (> 16 KB) offline turn remains retrievable across chunks via the real handler.
        let reloadedChannel = WatchVoiceRemoteChannel(
            remoteHost: h.host,
            resultJournal: WatchVoiceResultJournal(url: journalURL),
            transport: FakeWatchVoiceTransport()
        )
        var assembled = Data()
        var chunks = 0
        while assembled.count < firstLongText.utf8.count {
            let req = try JSONEncoder().encode(WatchVoiceRequest.result(id: firstID, offset: assembled.count))
            let chunk = reloadedChannel.handleMessageData(req)
            XCTAssertFalse(chunk.isEmpty)
            assembled.append(chunk)
            chunks += 1
        }
        XCTAssertGreaterThanOrEqual(chunks, 2)
        XCTAssertEqual(String(data: assembled, encoding: .utf8), firstLongText)

        _ = h.host.handle(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .end, targetCallID: callID))
    }

    func testApplicationContextMergePreservesPendingOneShotTaskAcrossPhoneRestart() throws {
        let taskUpdate = WatchVoiceUpdate(id: UUID(), phase: .finished, text: "Saved #591 task result")
        let taskData = try JSONEncoder().encode(taskUpdate)
        let remoteData = Data("{\"epoch\":9}".utf8)

        // After iPhone restarts, latestTaskContext is nil while session.applicationContext still holds #591's task.
        let existing: [String: Any] = [WatchVoiceRequest.contextKey: taskData]
        let merged = WatchVoiceRemote.mergeApplicationContext(
            existing: existing,
            taskContext: nil,
            remoteContext: remoteData
        )
        XCTAssertEqual(merged[WatchVoiceRequest.contextKey] as? Data, taskData)
        XCTAssertEqual(merged[WatchVoiceRemote.contextKey] as? Data, remoteData)

        // Updating #591 task context later preserves the remote snapshot context as well.
        let newerTaskData = Data("{\"id\":\"newer\"}".utf8)
        let merged2 = WatchVoiceRemote.mergeApplicationContext(
            existing: merged,
            taskContext: newerTaskData,
            remoteContext: nil
        )
        XCTAssertEqual(merged2[WatchVoiceRequest.contextKey] as? Data, newerTaskData)
        XCTAssertEqual(merged2[WatchVoiceRemote.contextKey] as? Data, remoteData)
    }

    func testDelayedDuplicateEndBackgroundCopyDoesNotOverwriteIdleApplicationContext() async throws {
        let h = Harness(bridgeAddress: BridgeStub.liveAddress)
        let transport = FakeWatchVoiceTransport()
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-voice-dup-end-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: journalURL) }
        let channel = WatchVoiceRemoteChannel(
            remoteHost: h.host,
            resultJournal: WatchVoiceResultJournal(url: journalURL),
            transport: transport
        )
        var backgroundTaskActive = false
        channel.onBackgroundTaskNeeded = { backgroundTaskActive = $0 }

        // Start a Live call and move it to .listening.
        let startPayload = try JSONEncoder().encode(WatchVoiceRemoteCommand(issuedAt: h.time.now, action: .start))
        let startReplyDict = channel.handleRemoteMessage([WatchVoiceRemote.commandKey: startPayload], pushSnapshot: false)
        let startReply = try JSONDecoder().decode(
            WatchVoiceRemoteReply.self,
            from: XCTUnwrap(startReplyDict[WatchVoiceRemote.replyKey] as? Data)
        )
        XCTAssertEqual(startReply.outcome, .accepted)
        let callID = try XCTUnwrap(startReply.snapshot.callID)
        await h.time.settle()
        h.connection.play(["type": "session.started"])
        await h.time.settle()

        // Watch tracks the active call, then queues End offline and also flushes the same requestID on reconnect.
        var watchReducer = WatchVoiceRemoteStateReducer()
        let listeningSnapshot = try transport.decodedRemoteSnapshot()
        XCTAssertEqual(listeningSnapshot.state, .listening)
        XCTAssertTrue(watchReducer.apply(snapshot: listeningSnapshot))
        let endCommand = try XCTUnwrap(watchReducer.queueEnd(now: h.time.now))
        let endPayload = try JSONEncoder().encode(endCommand)

        // 1. Instant sendMessage copy arrives first -> Live call enters .ending and caches that receipt.
        let firstReplyDict = channel.handleRemoteMessage([WatchVoiceRemote.commandKey: endPayload], pushSnapshot: false)
        let firstReply = try JSONDecoder().decode(
            WatchVoiceRemoteReply.self,
            from: XCTUnwrap(firstReplyDict[WatchVoiceRemote.replyKey] as? Data)
        )
        XCTAssertEqual(firstReply.outcome, .accepted)
        XCTAssertEqual(firstReply.snapshot.state, .ending)
        XCTAssertEqual(try transport.decodedRemoteSnapshot().state, .ending)

        // 2. Live session finishes closing -> phone transitions to .idle and updates applicationContext.
        h.connection.play(["type": "session.closed", "reason": "done"])
        await h.time.settle()
        let idleSnapshot = try transport.decodedRemoteSnapshot()
        XCTAssertEqual(idleSnapshot.state, .idle)
        XCTAssertGreaterThan(idleSnapshot.sequence, firstReply.snapshot.sequence)
        XCTAssertFalse(backgroundTaskActive)

        // 3. Delayed background transferUserInfo copy with the SAME requestID arrives after phone is already .idle.
        let duplicateReplyDict = channel.handleRemoteMessage([WatchVoiceRemote.commandKey: endPayload], pushSnapshot: true)
        let duplicateReply = try JSONDecoder().decode(
            WatchVoiceRemoteReply.self,
            from: XCTUnwrap(duplicateReplyDict[WatchVoiceRemote.replyKey] as? Data)
        )
        // Cached receipt is preserved for duplicate requestID.
        XCTAssertEqual(duplicateReply, firstReply)
        XCTAssertEqual(duplicateReply.snapshot.state, .ending)

        // Sync channels MUST carry the phone's current .idle snapshot, never the stale cached .ending snapshot.
        let contextAfterDuplicate = try transport.decodedRemoteSnapshot()
        XCTAssertEqual(contextAfterDuplicate.state, .idle)
        XCTAssertEqual(contextAfterDuplicate.sequence, idleSnapshot.sequence)
        XCTAssertFalse(backgroundTaskActive)

        let pushedData = try XCTUnwrap(transport.sentMessages.last?[WatchVoiceRemote.snapshotKey] as? Data)
        let pushedSnapshot = try JSONDecoder().decode(WatchVoiceRemoteSnapshot.self, from: pushedData)
        XCTAssertEqual(pushedSnapshot.state, .idle)
        XCTAssertEqual(pushedSnapshot.sequence, idleSnapshot.sequence)

        // A Watch that missed the earlier .idle push applies applicationContext and MUST end up in .idle.
        XCTAssertTrue(watchReducer.apply(snapshot: contextAfterDuplicate))
        XCTAssertEqual(watchReducer.latestSnapshot?.state, .idle)
        XCTAssertNil(watchReducer.pendingEnd)
        XCTAssertFalse(watchReducer.canShowEndButton)
        XCTAssertEqual(callID, endCommand.targetCallID)

        // A duplicate instant sendMessage arriving after .idle also keeps applicationContext at .idle.
        let duplicateInstantDict = channel.handleRemoteMessage([WatchVoiceRemote.commandKey: endPayload], pushSnapshot: false)
        let duplicateInstant = try JSONDecoder().decode(
            WatchVoiceRemoteReply.self,
            from: XCTUnwrap(duplicateInstantDict[WatchVoiceRemote.replyKey] as? Data)
        )
        XCTAssertEqual(duplicateInstant, firstReply)
        XCTAssertEqual(try transport.decodedRemoteSnapshot().state, .idle)
        XCTAssertEqual(try transport.decodedRemoteSnapshot().sequence, idleSnapshot.sequence)
    }
}
