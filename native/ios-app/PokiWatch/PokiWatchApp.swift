import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

@main
struct PokiWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchVoiceDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchVoiceRemoteView(model: .shared)
                .onOpenURL { url in
                    guard url.scheme == "pokiwatch" else { return }
                    if url.host == "start" || url.path == "/start" {
                        WatchVoiceModel.shared.handleStartDeepLink()
                    }
                }
        }
    }
}

final class WatchVoiceDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivity = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchVoiceModel.shared.handle(connectivity)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let id = UUID(uuidString: response.notification.request.identifier) {
            Task { @MainActor in
                WatchVoiceModel.shared.openResult(id)
            }
        }
        completionHandler()
    }
}

private struct WatchVoiceRemoteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: WatchVoiceModel
    @State private var selectedPage: Int? = 0
    @State private var showingVoiceTask = false

    private var mode: WatchScreenMode {
        WatchScreenMode.resolve(
            state: model.remoteState,
            isMuted: model.remoteIsMuted,
            currentStep: model.remoteCurrentStep,
            requiresForeground: model.remoteRequiresForeground,
            isStartingCall: model.isStartingCall,
            showingEndedScreen: model.showingEndedScreen,
            hasTransportError: model.remoteTransportError != nil
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    mainVoiceScreen
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(0)

                    secondaryHubPage
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(1)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $selectedPage)
            .ignoresSafeArea()
            .background(WatchDesignTokens.screenBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $model.selectedResultID) { resultID in
                WatchVoiceResultView(model: model, id: resultID)
            }
            .navigationDestination(isPresented: $showingVoiceTask) {
                WatchVoiceTaskView(model: model)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.opened()
                WidgetCenter.shared.reloadTimelines(ofKind: "PokiWatchFace")
                Task { await model.requestNotifications() }
            } else if phase == .background {
                model.cancelRecording()
            }
        }
        .onChange(of: mode) { _, next in
            if next != .idle && next != .ended {
                selectedPage = 0
            }
        }
    }

    private var mainVoiceScreen: some View {
        let glow = mode.ambientGlow
        let pulseBoost = (mode == .speaking || mode == .listening) ? Double(model.remoteMeterLevel) / 255.0 : 0

        return ZStack {
            WatchOLEDBackground(
                center: glow.center,
                innerColor: glow.inner,
                midColor: glow.mid,
                endRadiusFraction: glow.endFraction,
                pulseBoost: pulseBoost
            )

            VStack(spacing: 0) {
                HStack {
                    topLeadingStatus(forSecondary: false)
                    Spacer()
                }
                .frame(height: 20)
                .padding(.horizontal, 4)

                Spacer(minLength: 2)

                WatchVoiceOrbView(
                    mode: mode,
                    meterLevel: model.remoteMeterLevel,
                    title: primaryTitle,
                    subtitle: subtitleText,
                    isInteractive: mode == .idle || mode == .muted,
                    isDisabled: model.remoteCommandInFlight || model.remoteState == .ending,
                    accessibilityIdentifier: mode == .muted ? "watchRemote.unmuteBear" : "watchRemote.primary",
                    onTap: { model.remotePrimaryAction() },
                    onLongPress: mode == .idle ? {
                        WKInterfaceDevice.current().play(.click)
                        showingVoiceTask = true
                    } : nil
                )

                Spacer(minLength: 4)

                WatchVoiceControlsBar(
                    layout: bottomLayout,
                    disabled: model.remoteState == .ending || (model.remoteCommandInFlight && mode != .waking && mode != .connecting),
                    onPrimary: { model.remotePrimaryAction() },
                    onEnd: { model.remoteEndAction() }
                )
            }
            .padding(.top, WatchDesignTokens.screenTopPadding)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var secondaryHubPage: some View {
        ZStack {
            WatchOLEDBackground(
                center: UnitPoint(x: 0.5, y: 0.0),
                innerColor: Color(hex: 0x0077FD, opacity: 0x2E / 255.0),
                midColor: nil,
                endRadiusFraction: 0.58
            )

            VStack(spacing: 0) {
                HStack {
                    topLeadingStatus(forSecondary: true)
                    Spacer()
                }
                .frame(height: 20)
                .padding(.top, WatchDesignTokens.screenTopPadding)
                .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding + 4)

                WatchVoiceSecondaryHubView(model: model)
            }
        }
    }

    private func topLeadingStatus(forSecondary: Bool) -> some View {
        let dotColor: Color
        let labelColor: Color
        let fillColor: Color
        let borderColor: Color
        let labelText: LocalizedStringResource

        if forSecondary {
            dotColor = WatchDesignTokens.statusGreen
            labelColor = WatchDesignTokens.statusPokiLabel
            fillColor = WatchDesignTokens.topPillNeutralFill
            borderColor = WatchDesignTokens.topPillNeutralBorder
            labelText = "Poki"
        } else {
            switch mode.topStatus {
            case .connected:
                dotColor = WatchDesignTokens.statusGreen
                labelColor = WatchDesignTokens.statusPokiLabel
                fillColor = WatchDesignTokens.topPillNeutralFill
                borderColor = WatchDesignTokens.topPillNeutralBorder
                labelText = "Poki"
            case .attention:
                dotColor = WatchDesignTokens.statusOrange
                labelColor = WatchDesignTokens.statusAmberLight
                fillColor = WatchDesignTokens.statusOrangePillFill
                borderColor = WatchDesignTokens.statusOrangePillBorder
                labelText = "Poki"
            case .disconnected:
                dotColor = WatchDesignTokens.statusRed
                labelColor = WatchDesignTokens.statusRedIcon
                fillColor = WatchDesignTokens.statusRedPillFill
                borderColor = WatchDesignTokens.statusRedPillBorder
                labelText = "Not connected"
            }
        }

        return HStack(spacing: WatchDesignTokens.statusDotGap) {
            Circle()
                .fill(dotColor)
                .frame(width: WatchDesignTokens.statusDotSize, height: WatchDesignTokens.statusDotSize)
                .shadow(color: dotColor.opacity(0.8), radius: 3)
            Text(labelText)
                .font(WatchDesignTokens.topBarFont)
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fillColor, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(borderColor, lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watchRemote.topStatus")
    }

    private var primaryTitle: LocalizedStringResource {
        switch mode {
        case .unavailable: "Unavailable"
        case .needsSetup: "Not set up"
        case .idle: "Poki"
        case .connecting, .waking: "Connecting"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .acting: "Acting"
        case .speaking: "Poki is speaking"
        case .muted: "Muted"
        case .ending: "Ending"
        case .ended: "Ended"
        case .locked: "Unlock iPhone to continue"
        case .failed: "Connection failed"
        }
    }

    private var subtitleText: String? {
        if model.hasPendingRemoteEnd {
            return String(localized: "Ending when iPhone reconnects…")
        }
        switch mode {
        case .unavailable:
            return String(localized: "iPhone not connected")
        case .needsSetup:
            return String(localized: "Finish voice setup on iPhone")
        case .idle:
            if let transportError = model.remoteTransportError {
                return String(localized: transportError)
            }
            return String(localized: "Tap to talk, hold for a task")
        case .connecting:
            return String(localized: "Checking connection and mic")
        case .waking:
            return String(localized: "Waking iPhone…")
        case .listening, .thinking, .speaking:
            return nil
        case .acting(let step, _):
            let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(localized: "Using the phone") : trimmed
        case .muted:
            return String(localized: "Tap Poki to unmute")
        case .ending:
            return String(localized: "Disconnecting call")
        case .ended:
            return String(localized: "Call ended. Returning in 3s")
        case .locked:
            return String(localized: "Continues automatically after unlock")
        case .failed:
            if let transportError = model.remoteTransportError {
                return String(localized: transportError)
            }
            return String(localized: "Poki isn’t running on iPhone")
        }
    }

    private var bottomLayout: WatchBottomActionLayout {
        switch mode {
        case .unavailable:
            if model.canEndRemoteCall {
                return .endOnly
            }
            return .caption(text: "Waiting for iPhone to reconnect", color: WatchDesignTokens.subtitleDefault)
        case .needsSetup:
            return .primaryBlue(title: "Continue on iPhone", identifier: "watchRemote.continueOnPhone")
        case .idle:
            return .captionPill(text: "Supports Double Tap")
        case .connecting, .waking, .muted:
            return .endOnly
        case .listening, .thinking, .acting, .speaking:
            return .muteAndEnd
        case .ending, .ended:
            return .spacer
        case .locked:
            return .primaryBlue(title: "Continue on iPhone", identifier: "watchRemote.continueOnPhone")
        case .failed:
            if model.canEndRemoteCall {
                return .endOnly
            }
            return .primaryBlue(title: "Retry", identifier: "watchRemote.retry")
        }
    }
}
