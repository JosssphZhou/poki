#if POKI_WATCH
import Foundation
import os
import UserNotifications
import WatchConnectivity
import XCTest
@testable import Poki

@MainActor
private final class FakePhoneLink: WatchVoicePhoneLink {
    var isActivated = true
    var isWatchAppInstalled = true
    var isReachable = true
    private(set) var sentUpdates: [WatchVoiceUpdate] = []
    private(set) var contextUpdates: [WatchVoiceUpdate] = []
    var onUpdate: (@MainActor (WatchVoiceUpdate) -> Void)?

    func activate(delegate: WCSessionDelegate) {}

    func sendMessageData(_ data: Data) {
        guard let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: data) else { return }
        sentUpdates.append(update)
        onUpdate?(update)
    }

    func updateApplicationContext(_ context: [String: Any]) throws {
        guard let data = context[WatchVoiceRequest.contextKey] as? Data,
              let update = try? JSONDecoder().decode(WatchVoiceUpdate.self, from: data) else { return }
        contextUpdates.append(update)
        if !isReachable { onUpdate?(update) }
    }
}

@MainActor
private final class FakeBackgroundExecution: WatchBackgroundExecution {
    private final class Token: Hashable {
        let id = UUID()
        let expirationHandler: @MainActor @Sendable () -> Void

        init(expirationHandler: @escaping @MainActor @Sendable () -> Void) {
            self.expirationHandler = expirationHandler
        }

        static func == (lhs: Token, rhs: Token) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private var active: [Token] = []
    var activeCount: Int { active.count }

    func begin(name: String, expirationHandler: @escaping @MainActor @Sendable () -> Void) -> AnyObject? {
        let token = Token(expirationHandler: expirationHandler)
        active.append(token)
        return token
    }

    func end(_ token: AnyObject?) {
        guard let boxed = token as? Token else { return }
        active.removeAll { $0 == boxed }
    }

    func expireAll() {
        let pending = active
        for token in pending {
            token.expirationHandler()
        }
    }
}

@MainActor
private final class FakeWatchDeliveryLink: WatchVoiceDeliveryLink {
    var isActivated = true
    var isCompanionInstalled = true
    var isReachable = true
    var needsUnlockAfterReboot = false
    private(set) var sentRequests: [WatchVoiceRequest] = []
    var handler: (@MainActor (WatchVoiceRequest, Data, @escaping @Sendable (Data) -> Void, @escaping @Sendable (Error) -> Void) -> Void)?

    func activate() {
        isActivated = true
    }

    func sendMessageData(
        _ data: Data,
        replyHandler: @escaping @Sendable (Data) -> Void,
        errorHandler: @escaping @Sendable (Error) -> Void
    ) {
        guard let request = try? JSONDecoder().decode(WatchVoiceRequest.self, from: data) else {
            replyHandler(Data())
            return
        }
        sentRequests.append(request)
        handler?(request, data, replyHandler, errorHandler)
    }
}

@MainActor
final class WatchVoiceBackgroundTests: XCTestCase {
    private var tempDirectory: URL!
    private var savedDefaults: [String: Any?] = [:]
    private var savedSetup: SetupState!
    private var savedCustomProviders: [CustomProvider] = []
    private var savedLanguage = AppLocalization.system
    private var postedNoticeIDs: [UUID] = []

    private let trackedKeys = [
        "wantsOn",
        "relayAddress",
        "relayEnabled",
        "chat.provider",
        "chat.model.custom",
        CustomProviders.selectedKey,
        "pokiWatchVoiceTestTranscript",
        "pokiWatchVoiceSimulateLocked",
    ]

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appending(path: "WatchVoiceBackgroundTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        savedLanguage = AppLocalization.shared.preference
        AppLocalization.shared.preference = "en"
        savedSetup = SetupState.load()
        savedCustomProviders = CustomProviders.all
        for key in trackedKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key)
        }
        UserDefaults.standard.set(true, forKey: "pokiWatchVoiceTestTranscript")
        UserDefaults.standard.set(false, forKey: "pokiWatchVoiceSimulateLocked")
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .provisional])
        await SessionStore.shared.waitUntilLoaded()
    }

    override func tearDown() async throws {
        for id in postedNoticeIDs {
            WatchVoiceNotice.clearUnlockPrompt(for: id)
        }
        postedNoticeIDs.removeAll()
        if let tempDirectory { try? FileManager.default.removeItem(at: tempDirectory) }
        for (key, value) in savedDefaults {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for current in CustomProviders.all where !savedCustomProviders.contains(where: { $0.id == current.id }) {
            CustomProviders.remove(current.id)
        }
        savedSetup?.save()
        AppLocalization.shared.preference = savedLanguage
    }

    private func configureModel(on server: FakeCompletions) throws {
        try ModelKeys.saveCustom(address: "http://127.0.0.1:\(server.port)/v1", model: "poki-mock", typedKey: "")
    }

    private func makeApp(wantsOn: Bool, sessionOn: Bool) -> (AppModel, ChatModel) {
        UserDefaults.standard.set(wantsOn, forKey: "wantsOn")
        let app = AppModel(launcher: FakeLauncher(), pairer: FakePairing(), automation: FakeAutomation())
        app.setup.loopback = .proxy
        app.loopback.simulate(.working(ms: 5))
        if sessionOn {
            app.startSession()
        }
        let chat = ChatModel(app: app)
        return (app, chat)
    }

    private func sendToPhone(_ phone: WatchVoicePhone, request: WatchVoiceRequest) async throws -> WatchVoiceUpdate? {
        let encoded = try JSONEncoder().encode(request)
        let replyData: Data = await withCheckedContinuation { continuation in
            phone.session(WCSession.default, didReceiveMessageData: encoded) { data in
                continuation.resume(returning: data)
            }
        }
        guard !replyData.isEmpty else { return nil }
        return try JSONDecoder().decode(WatchVoiceUpdate.self, from: replyData)
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ predicate: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return predicate()
    }

    private func waitForDeliveredNotice(id: UUID, timeout: Duration = .seconds(5)) async -> UNNotification? {
        let expectedID = WatchVoiceNotice.identifier(for: id)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            if let match = delivered.first(where: { $0.request.identifier == expectedID }) {
                return match
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    private func waitForNoticeCleared(id: UUID, timeout: Duration = .seconds(5)) async -> Bool {
        let expectedID = WatchVoiceNotice.identifier(for: id)
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
            if !delivered.contains(where: { $0.request.identifier == expectedID }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    private func finishTaskReplies(_ summary: String) -> [String] {
        [
            FakeCompletions.tool("finish_task", [
                "success": true,
                "summary": summary,
                "details": [],
                "answer": ["kind": "action"],
            ]),
            FakeCompletions.text(summary),
        ]
    }

    func testBackgroundColdWakeTurnsOnWantedSessionExecutesRealChatAndStopsKeepAlive() async throws {
        let server = try FakeCompletions(replies: finishTaskReplies("Checked Poki in the background."))
        try configureModel(on: server)
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()
        XCTAssertFalse(app.sessionOn)
        XCTAssertFalse(app.background.isOn)

        let link = FakePhoneLink()
        let bg = FakeBackgroundExecution()
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            link: link,
            backgroundExecution: bg,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )

        let id = UUID()
        let receipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .received)

        let finished = await waitUntil { link.sentUpdates.last?.phase == .finished }
        XCTAssertTrue(finished, "Cold-woken background Poki must finish real delegated chat; sent=\(link.sentUpdates)")
        XCTAssertEqual(link.sentUpdates.map(\.phase), [.running, .finished])
        XCTAssertTrue(link.sentUpdates.last?.text?.contains("Checked Poki in the background.") == true)
        XCTAssertGreaterThanOrEqual(server.requests.count, 1)

        let cleanedUp = await waitUntil(timeout: .seconds(2)) { !app.background.isOn && bg.activeCount == 0 }
        XCTAssertTrue(cleanedUp, "Watch-woken background keep-alive must stop immediately after task completion")
        XCTAssertFalse(app.background.isOn, "BackgroundKeeper must not stay running after Watch task finishes")
        XCTAssertFalse(app.sessionOn, "Watch-woken temporary background session must wind down after completion")
        XCTAssertTrue(app.wantsOn, "Winding down after Watch task must preserve wantsOn for the next wake")
        XCTAssertEqual(bg.activeCount, 0)
    }

    func testBackgroundColdWakeStopsKeepAliveAfterModelFailure() async throws {
        let server = try FakeCompletions(replies: [], responseStatus: "500 Internal Server Error")
        try configureModel(on: server)
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()

        let link = FakePhoneLink()
        let bg = FakeBackgroundExecution()
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            link: link,
            backgroundExecution: bg,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )

        let id = UUID()
        let receipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .received)

        let blocked = await waitUntil { link.sentUpdates.last?.phase == .blocked }
        XCTAssertTrue(blocked, "Model HTTP 500 must report blocked to Watch; sent=\(link.sentUpdates)")

        let cleanedUp = await waitUntil(timeout: .seconds(2)) { !app.background.isOn && bg.activeCount == 0 }
        XCTAssertTrue(cleanedUp, "Watch-woken background keep-alive must stop immediately after task failure")
        XCTAssertFalse(app.background.isOn)
        XCTAssertFalse(app.sessionOn)
        XCTAssertTrue(app.wantsOn)
        XCTAssertEqual(bg.activeCount, 0)
    }

    func testBackgroundColdWakeStopsKeepAliveAfterBackgroundExpirationCancel() async throws {
        let heldStarted = OSAllocatedUnfairLock(initialState: false)
        let server = try FakeCompletions(
            replies: finishTaskReplies("Should be cancelled"),
            holdFirstReply: { heldStarted.withLock { $0 = true } }
        )
        try configureModel(on: server)
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()

        let link = FakePhoneLink()
        let bg = FakeBackgroundExecution()
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            link: link,
            backgroundExecution: bg,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )

        let id = UUID()
        let receipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .received)

        let inFlight = await waitUntil { heldStarted.withLock { $0 } && bg.activeCount == 1 }
        XCTAssertTrue(inFlight, "Expected real ChatModel request to be in flight with an active background task")

        bg.expireAll()

        let cancelled = await waitUntil { link.sentUpdates.last?.phase == .blocked }
        XCTAssertTrue(cancelled, "Expiring background execution must cancel task and report blocked; sent=\(link.sentUpdates)")

        let cleanedUp = await waitUntil(timeout: .seconds(2)) { !app.background.isOn && bg.activeCount == 0 }
        XCTAssertTrue(cleanedUp, "Watch-woken background keep-alive must stop immediately after task cancellation")
        XCTAssertFalse(app.background.isOn)
        XCTAssertFalse(app.sessionOn)
        XCTAssertTrue(app.wantsOn)
        XCTAssertEqual(bg.activeCount, 0)
    }

    func testLockedPhoneParksTaskPostsRealUnlockNoticeAndResumesAfterUnlock() async throws {
        let server = try FakeCompletions(replies: finishTaskReplies("Completed after unlock."))
        try configureModel(on: server)
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()

        var protectedDataAvailable = false
        var screenLocked = true
        let link = FakePhoneLink()
        let bg = FakeBackgroundExecution()
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            link: link,
            backgroundExecution: bg,
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { protectedDataAvailable },
            isScreenLocked: { screenLocked }
        )

        let id = UUID()
        postedNoticeIDs.append(id)
        let receipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .waitingForUnlock)
        XCTAssertEqual(server.requests.count, 0, "Model must not run while phone is locked")
        XCTAssertFalse(app.background.isOn, "Parking a locked task must not start continuous background keep-alive")

        let notice = await waitForDeliveredNotice(id: id)
        XCTAssertNotNil(notice, "Locked phone must post a real local unlock reminder notification")

        let retryReceipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(retryReceipt?.phase, .waitingForUnlock)

        protectedDataAvailable = true
        screenLocked = false
        phone.handleUnlockSignal()

        let finished = await waitUntil { link.sentUpdates.last?.phase == .finished }
        XCTAssertTrue(finished, "Unlock signal must resume parked task; sent=\(link.sentUpdates)")
        XCTAssertEqual(server.requests.count, 2, "Expected finish_task tool call plus final assistant turn")
        let cleared = await waitForNoticeCleared(id: id)
        XCTAssertTrue(cleared, "Unlocking and resuming must clear the local unlock reminder notification")

        let cleanedUp = await waitUntil(timeout: .seconds(2)) { !app.background.isOn && bg.activeCount == 0 }
        XCTAssertTrue(cleanedUp)
        XCTAssertFalse(app.background.isOn)
    }

    func testLockedScreenBeforeProtectedDataLocksStillWaitsForUnlock() async throws {
        let server = try FakeCompletions(replies: finishTaskReplies("Completed after early lock unlock."))
        try configureModel(on: server)
        let (app, chat) = makeApp(wantsOn: true, sessionOn: false)
        defer { app.stopSession() }
        app.wentToBackground()

        var screenLocked = true
        let link = FakePhoneLink()
        let phone = WatchVoicePhone(
            app: app,
            chat: chat,
            link: link,
            backgroundExecution: FakeBackgroundExecution(),
            journal: tempDirectory.appending(path: "WatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { screenLocked }
        )

        let id = UUID()
        postedNoticeIDs.append(id)
        let receipt = try await sendToPhone(phone, request: .submit(id: id, audio: Data("m4a".utf8)))
        XCTAssertEqual(receipt?.phase, .waitingForUnlock)
        XCTAssertEqual(server.requests.count, 0)

        screenLocked = false
        phone.handleUnlockSignal()

        let finished = await waitUntil { link.sentUpdates.last?.phase == .finished }
        XCTAssertTrue(finished)
        XCTAssertFalse(app.background.isOn)
    }

    func testWaitingForUnlockPollsAndWakesSuspendedPhoneOnceUnlocked() async throws {
        let server = try FakeCompletions(replies: finishTaskReplies("Resumed after suspension."))
        try configureModel(on: server)
        let journal = tempDirectory.appending(path: "PhoneWatchVoice.json")
        let watchArchive = tempDirectory.appending(path: "WatchArchive.json")

        let (app1, chat1) = makeApp(wantsOn: true, sessionOn: false)
        defer { app1.stopSession() }
        app1.wentToBackground()
        let bg1 = FakeBackgroundExecution()
        let phoneLink1 = FakePhoneLink()
        let phone1 = WatchVoicePhone(
            app: app1,
            chat: chat1,
            link: phoneLink1,
            backgroundExecution: bg1,
            journal: journal,
            isProtectedDataAvailable: { false },
            isScreenLocked: { true }
        )

        var currentPhone: WatchVoicePhone = phone1
        let watchLink = FakeWatchDeliveryLink()
        watchLink.handler = { _, data, replyHandler, _ in
            currentPhone.session(WCSession.default, didReceiveMessageData: data, replyHandler: replyHandler)
        }
        let watch = WatchVoiceDeliveryController(
            link: watchLink,
            archiveURL: watchArchive,
            timing: WatchVoiceDeliveryTiming(
                reachabilityWait: .milliseconds(80),
                sendTimeout: .milliseconds(250),
                unlockPollInterval: .milliseconds(80)
            )
        )
        phoneLink1.onUpdate = { [weak watch] update in watch?.receive(update) }
        watch.setActive(true)

        let id = UUID()
        postedNoticeIDs.append(id)
        XCTAssertTrue(watch.enqueue(id: id, audio: Data("m4a".utf8)))

        let parkedOnWatch = await waitUntil { watch.update?.phase == .waitingForUnlock }
        XCTAssertTrue(parkedOnWatch)
        XCTAssertEqual(server.requests.count, 0)

        // Simulate iOS reclaiming the short background task and suspending/terminating Poki while locked.
        bg1.expireAll()
        XCTAssertEqual(bg1.activeCount, 0)
        XCTAssertFalse(app1.background.isOn)

        // Recreate Poki on iPhone unlocked, WITHOUT posting any Darwin unlock signal or opening Poki in front.
        let (app2, chat2) = makeApp(wantsOn: true, sessionOn: false)
        defer { app2.stopSession() }
        app2.wentToBackground()
        let phoneLink2 = FakePhoneLink()
        phoneLink2.onUpdate = { [weak watch] update in watch?.receive(update) }
        let bg2 = FakeBackgroundExecution()
        let phone2 = WatchVoicePhone(
            app: app2,
            chat: chat2,
            link: phoneLink2,
            backgroundExecution: bg2,
            journal: journal,
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )
        currentPhone = phone2

        // Active Watch waiting screen must poll status and wake the suspended phone automatically.
        let resumedAndFinished = await waitUntil(timeout: .seconds(5)) {
            watch.results.first(where: { $0.id == id })?.phase == .finished
        }
        XCTAssertTrue(resumedAndFinished, "Active Watch waitingForUnlock poll must wake suspended iPhone Poki once unlocked")
        XCTAssertGreaterThanOrEqual(server.requests.count, 1)
        let cleanedUp = await waitUntil(timeout: .seconds(2)) { !app2.background.isOn && bg2.activeCount == 0 }
        XCTAssertTrue(cleanedUp)
        XCTAssertFalse(app2.background.isOn)

        // Verify Watch stops polling once it leaves foreground.
        watch.setActive(false)
        let pollCountAfterBackground = watchLink.sentRequests.count
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(watchLink.sentRequests.count, pollCountAfterBackground)
    }

    func testBackgroundSessionStartTimeoutReturnsPromptlyWhenStartStalls() async {
        let stalled = Task {
            // Simulate a non-cooperative blocking call inside startTask.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
                    continuation.resume()
                }
            }
        }
        let started = ContinuousClock.now
        await AppModel.waitForSessionStart(stalled, timeout: .milliseconds(60))
        let elapsed = ContinuousClock.now - started
        XCTAssertLessThan(elapsed, .milliseconds(250), "Timeout must not block on a stalled sessionStartTask; elapsed=\(elapsed)")
    }

    func testOwnerTurnedOffAndOwnerPausedBothRefuseBackgroundExecution() async throws {
        let server = try FakeCompletions(replies: finishTaskReplies("Must not run"))
        try configureModel(on: server)

        // Case 1: Poki turned off (wantsOn == false, sessionOn == false).
        let (offApp, offChat) = makeApp(wantsOn: false, sessionOn: false)
        defer { offApp.stopSession() }
        offApp.wentToBackground()
        let offLink = FakePhoneLink()
        let offPhone = WatchVoicePhone(
            app: offApp,
            chat: offChat,
            link: offLink,
            backgroundExecution: FakeBackgroundExecution(),
            journal: tempDirectory.appending(path: "OffWatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )
        _ = try await sendToPhone(offPhone, request: .submit(id: UUID(), audio: Data("m4a".utf8)))
        let offBlocked = await waitUntil { offLink.sentUpdates.last?.phase == .blocked }
        XCTAssertTrue(offBlocked)
        XCTAssertFalse(offApp.sessionOn)
        XCTAssertFalse(offApp.background.isOn)

        // Case 2: Poki on, but owner explicitly paused it (ownerPaused == true).
        let (pausedApp, pausedChat) = makeApp(wantsOn: true, sessionOn: true)
        defer { pausedApp.stopSession() }
        pausedApp.pauseRunner(byOwner: true)
        pausedApp.wentToBackground()
        XCTAssertTrue(pausedApp.ownerPaused)
        let pausedLink = FakePhoneLink()
        let pausedPhone = WatchVoicePhone(
            app: pausedApp,
            chat: pausedChat,
            link: pausedLink,
            backgroundExecution: FakeBackgroundExecution(),
            journal: tempDirectory.appending(path: "PausedWatchVoice.json"),
            isProtectedDataAvailable: { true },
            isScreenLocked: { false }
        )
        _ = try await sendToPhone(pausedPhone, request: .submit(id: UUID(), audio: Data("m4a".utf8)))
        let pausedBlocked = await waitUntil { pausedLink.sentUpdates.last?.phase == .blocked }
        XCTAssertTrue(pausedBlocked)
        XCTAssertEqual(server.requests.count, 0, "Neither turned-off nor owner-paused Poki may execute a Watch task")
    }

    func testWatchDeliveryTimeoutWCErrorAndCancelLeaveSendingState() async throws {
        let link = FakeWatchDeliveryLink()
        let watch = WatchVoiceDeliveryController(
            link: link,
            archiveURL: tempDirectory.appending(path: "DeliveryArchive.json"),
            timing: WatchVoiceDeliveryTiming(
                reachabilityWait: .milliseconds(60),
                sendTimeout: .milliseconds(100),
                unlockPollInterval: .milliseconds(80)
            )
        )

        // 1. Stale reachable connection that never replies -> exits Sending into .timedOut, and Cancel clears it.
        link.handler = { _, _, _, _ in }
        XCTAssertTrue(watch.enqueue(audio: Data("m4a".utf8)))
        XCTAssertEqual(watch.pendingStatus, .sending)
        let timedOut = await waitUntil(timeout: .seconds(2)) {
            watch.pendingStatus == .deliveryFailed(.timedOut)
        }
        XCTAssertTrue(timedOut, "Hanging sendMessageData must leave Sending into timedOut; status=\(watch.pendingStatus)")
        watch.discardPending()
        XCTAssertEqual(watch.pendingStatus, .idle)
        XCTAssertFalse(watch.hasPending)

        // 2. WCErrorDomain notReachable (7007) -> exits Sending into .phoneUnavailable, Retry delivers when phone responds.
        link.handler = { _, _, _, errorHandler in
            errorHandler(NSError(domain: "WCErrorDomain", code: 7007))
        }
        let id = UUID()
        XCTAssertTrue(watch.enqueue(id: id, audio: Data("m4a".utf8)))
        let failed = await waitUntil(timeout: .seconds(2)) {
            watch.pendingStatus == .deliveryFailed(.phoneUnavailable)
        }
        XCTAssertTrue(failed, "WCError 7007 must leave Sending into phoneUnavailable; status=\(watch.pendingStatus)")

        link.handler = { _, _, replyHandler, _ in
            let reply = try! JSONEncoder().encode(WatchVoiceUpdate(id: id, phase: .received, text: nil))
            replyHandler(reply)
        }
        watch.sync()
        let accepted = await waitUntil(timeout: .seconds(2)) {
            watch.pendingStatus == .tracking(WatchVoiceUpdate(id: id, phase: .received, text: nil))
        }
        XCTAssertTrue(accepted)

        // 3. Monotonic phase progression preserves rawValues and drops stale updates.
        XCTAssertEqual(WatchVoiceUpdate.Phase.received.rawValue, 0)
        XCTAssertEqual(WatchVoiceUpdate.Phase.running.rawValue, 1)
        XCTAssertEqual(WatchVoiceUpdate.Phase.finished.rawValue, 2)
        XCTAssertEqual(WatchVoiceUpdate.Phase.blocked.rawValue, 3)
        XCTAssertEqual(WatchVoiceUpdate.Phase.waitingForUnlock.rawValue, 4)
        watch.receive(WatchVoiceUpdate(id: id, phase: .waitingForUnlock, text: nil))
        watch.receive(WatchVoiceUpdate(id: id, phase: .received, text: nil))
        XCTAssertEqual(watch.update?.phase, .waitingForUnlock)
        watch.receive(WatchVoiceUpdate(id: id, phase: .finished, text: "Done"))
        XCTAssertFalse(watch.hasPending)
        XCTAssertEqual(watch.results.first?.phase, .finished)

        // 4. iPhone rebooted before first unlock -> immediate explicit prompt.
        link.needsUnlockAfterReboot = true
        XCTAssertTrue(watch.enqueue(audio: Data("m4a".utf8)))
        XCTAssertEqual(watch.pendingStatus, .deliveryFailed(.needsUnlockAfterReboot))
        watch.discardPending()
    }
}
#endif
