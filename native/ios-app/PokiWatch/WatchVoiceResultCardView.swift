// Adapted from semantic-craft/iOS-vibebuddy (VibeBuddyApp/Watch/WatchAlertCard.swift and
// WatchRootView.swift, commit 2c2972d7), MIT License, Copyright (c) 2026 Xianwei Zhang.
// Poki adapts the watch card presentation, secondary hub (W17), and Voice Task (W18) to Paper
// `p-B-0` watchOS 27 Liquid Glass styling while preserving one-shot Voice Task, task history,
// and multi-chunk result loading.

import SwiftUI

struct WatchVoiceResultView: View {
    let model: WatchVoiceModel
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var retry = 0
    @State private var loadFailed = false

    private var update: WatchVoiceUpdate? {
        model.results.first(where: { $0.id == id })
    }

    private var isBlocked: Bool {
        update?.phase == .blocked
    }

    var body: some View {
        ZStack {
            WatchOLEDBackground(
                center: UnitPoint(x: 0.30, y: 0.10),
                innerColor: isBlocked
                    ? Color(hex: 0xFF9F0A, opacity: 0x2E / 255.0)
                    : Color(hex: 0x30D158, opacity: 0x2E / 255.0),
                midColor: nil,
                endRadiusFraction: 0.58
            )

            VStack(spacing: 6) {
                HStack {
                    resultTopStatus
                    Spacer()
                }
                .frame(height: 20)
                .padding(.horizontal, 4)

                if let update {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if update.fullTextBytes != nil {
                                if loadFailed {
                                    Text("Couldn’t load the full result.")
                                        .font(WatchDesignTokens.resultBodyFont)
                                        .foregroundStyle(WatchDesignTokens.titleRed)
                                    Button("Try again") { retry += 1 }
                                        .font(WatchDesignTokens.buttonFont)
                                        .buttonStyle(.bordered)
                                } else {
                                    ProgressView("Loading full result…")
                                        .font(WatchDesignTokens.resultBodyFont)
                                }
                                Text("Preview")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(WatchDesignTokens.hintSecondary)
                            }

                            if let text = update.text {
                                let parts = Self.splitHeadlineAndBody(text)
                                Text(parts.headline)
                                    .font(WatchDesignTokens.resultHeadlineFont)
                                    .foregroundStyle(WatchDesignTokens.titleWhite)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("watchResult.headline")
                                if let detail = parts.body {
                                    Text(detail)
                                        .font(WatchDesignTokens.resultBodyFont)
                                        .foregroundStyle(WatchDesignTokens.cardBodyText)
                                        .lineSpacing(3.5)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("watchResult.body")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, WatchDesignTokens.resultCardPaddingH)
                        .padding(.top, WatchDesignTokens.resultCardPaddingV)
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollIndicators(.visible)
                    .tint(isBlocked ? WatchDesignTokens.statusOrange : WatchDesignTokens.statusGreen)
                    .background(
                        LinearGradient(
                            colors: [WatchDesignTokens.resultCardTop, WatchDesignTokens.resultCardBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
                    )
                    .overlay(alignment: .trailing) {
                        // Subtle watchOS 27 scroll cue bar matching Paper W13A.
                        VStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(isBlocked ? WatchDesignTokens.statusOrange : WatchDesignTokens.statusGreen)
                                .frame(width: 2.5, height: 22)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 2.5, height: 52)
                        .background(Color.white.opacity(0.18), in: Capsule())
                        .padding(.trailing, 3.5)
                        .allowsHitTesting(false)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous)
                            .strokeBorder(WatchDesignTokens.resultCardBorder, lineWidth: 0.75)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: WatchDesignTokens.resultCardCornerRadius, style: .continuous))
                    .padding(.top, 2)
                } else {
                    Text("Result")
                        .font(WatchDesignTokens.resultBodyFont)
                        .foregroundStyle(WatchDesignTokens.subtitleDefault)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Text("Turn Crown for details")
                        .font(WatchDesignTokens.resultFooterFont)
                        .foregroundStyle(WatchDesignTokens.hintSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text("Saved to history")
                        .font(WatchDesignTokens.resultFooterFont)
                        .foregroundStyle(WatchDesignTokens.historyLinkBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)

                Button {
                    model.clearSelectedResult()
                    dismiss()
                } label: {
                    Text("Done")
                        .font(WatchDesignTokens.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchDesignTokens.bottomBarHeight)
                        .background(
                            LinearGradient(
                                colors: [Color.white.opacity(0x24 / 255.0), Color.white.opacity(0x10 / 255.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.white.opacity(0x38 / 255.0), lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .watchGlassControl(in: Capsule(), tint: .white.opacity(0.06), interactive: true)
                .accessibilityIdentifier("watchResult.done")
            }
            .padding(.top, WatchDesignTokens.screenTopPadding)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: retry) {
            loadFailed = false
            let loaded = await model.loadFullResult(id)
            if !Task.isCancelled { loadFailed = !loaded }
        }
    }

    private var resultTopStatus: some View {
        let accent = isBlocked ? WatchDesignTokens.statusAmberLight : WatchDesignTokens.statusGreenLight
        let iconColor = isBlocked ? WatchDesignTokens.statusOrange : WatchDesignTokens.statusGreen
        let pillFill = isBlocked ? WatchDesignTokens.statusOrangePillFill : WatchDesignTokens.statusGreenPillFill
        let pillBorder = isBlocked ? WatchDesignTokens.statusOrangePillBorder : WatchDesignTokens.statusGreenPillBorder
        let title: LocalizedStringResource = update?.phase.title ?? "Task finished"
        let symbol = isBlocked ? "exclamationmark" : "checkmark"

        return HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(iconColor)

            Text(title)
                .font(WatchDesignTokens.resultTopBarFont)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(pillFill, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(pillBorder, lineWidth: 0.5)
        }
        .accessibilityIdentifier("watchResult.status")
    }

    static func splitHeadlineAndBody(_ text: String) -> (headline: String, body: String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = trimmed.split(maxSplits: 1, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.count == 2 {
            return (lines[0], lines[1])
        }
        // Single-paragraph fallback: promote a concise leading title or first sentence so
        // W13A always shows a clear bold headline + body hierarchy even without a newline.
        if trimmed.count > 18 {
            let delimiters: [Character] = ["。", "！", "？", "：", "!", "?"]
            if let cutIndex = trimmed.firstIndex(where: { delimiters.contains($0) }) {
                let distance = trimmed.distance(from: trimmed.startIndex, to: cutIndex)
                if distance >= 3, distance <= 24 {
                    let after = trimmed.index(after: cutIndex)
                    let remainder = trimmed[after...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remainder.isEmpty {
                        let lead = trimmed[cutIndex] == "："
                            ? String(trimmed[..<cutIndex])
                            : String(trimmed[...cutIndex])
                        return (lead.trimmingCharacters(in: .whitespaces), remainder)
                    }
                }
            }
            if let dotRange = trimmed.range(of: ". ") {
                let distance = trimmed.distance(from: trimmed.startIndex, to: dotRange.lowerBound)
                if distance >= 4, distance <= 44 {
                    let remainder = trimmed[dotRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remainder.isEmpty {
                        return (String(trimmed[..<dotRange.lowerBound]) + ".", remainder)
                    }
                }
            }
        }
        return (trimmed, nil)
    }
}

struct WatchVoiceSecondaryHubView: View {
    let model: WatchVoiceModel

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                if let latest = model.results.first {
                    NavigationLink {
                        WatchVoiceResultView(model: model, id: latest.id)
                    } label: {
                        latestResultCard(latest)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchRemote.latestResult")
                }

                if !model.results.isEmpty {
                    NavigationLink {
                        WatchVoiceHistoryView(model: model)
                    } label: {
                        hubRow(
                            title: "Task history",
                            symbol: "clock",
                            isPrimaryBlue: false,
                            showBadge: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchRemote.history")
                }

                NavigationLink {
                    WatchVoiceTaskView(model: model)
                } label: {
                    hubRow(
                        title: "Voice Task",
                        symbol: "mic.fill",
                        isPrimaryBlue: true,
                        showBadge: model.hasPending
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchRemote.voiceTask")
            }
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding - 1)
            .padding(.top, 7)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
        }
    }

    private func latestResultCard(_ latest: WatchVoiceUpdate) -> some View {
        let isFinished = latest.phase == .finished
        let accent = isFinished ? WatchDesignTokens.statusGreenLight : WatchDesignTokens.statusAmberLight
        let iconColor = isFinished ? WatchDesignTokens.statusGreen : WatchDesignTokens.statusOrange

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.22))
                    Image(systemName: isFinished ? "checkmark" : "exclamationmark")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(iconColor)
                }
                .frame(width: 14, height: 14)

                Text(latest.phase.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
            }
            if let text = latest.text {
                let parts = WatchVoiceResultView.splitHeadlineAndBody(text)
                Text(parts.headline)
                    .font(WatchDesignTokens.hubCardPreviewFont)
                    .foregroundStyle(WatchDesignTokens.titleWhite)
                    .lineSpacing(2)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [WatchDesignTokens.hubLatestTop, WatchDesignTokens.hubLatestBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
                .strokeBorder(WatchDesignTokens.resultCardBorder, lineWidth: 0.75)
        }
    }

    private func hubRow(
        title: LocalizedStringResource,
        symbol: String,
        isPrimaryBlue: Bool,
        showBadge: Bool
    ) -> some View {
        let bgColors = isPrimaryBlue
            ? [WatchDesignTokens.hubBlueRowTop, WatchDesignTokens.hubBlueRowBottom]
            : [WatchDesignTokens.hubRowTop, WatchDesignTokens.hubRowBottom]
        let borderColor = isPrimaryBlue
            ? WatchDesignTokens.hubBlueRowBorder
            : WatchDesignTokens.resultCardBorder
        let badgeFill = isPrimaryBlue
            ? Color(hex: 0x0077FD, opacity: 0x73 / 255.0)
            : Color(hex: 0x5AA7FF, opacity: 0x33 / 255.0)
        let badgeBorder = isPrimaryBlue
            ? Color(hex: 0x9ACFFF, opacity: 0xB3 / 255.0)
            : Color(hex: 0x8AC4FF, opacity: 0x80 / 255.0)
        let iconColor: Color = isPrimaryBlue ? .white : WatchDesignTokens.skyBlueLight

        return HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badgeFill)
                Circle()
                    .strokeBorder(badgeBorder, lineWidth: 0.75)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(WatchDesignTokens.hubCardTitleFont)
                .foregroundStyle(WatchDesignTokens.titleWhite)
                .lineLimit(1)

            Spacer(minLength: 4)

            if showBadge {
                Circle()
                    .fill(WatchDesignTokens.pokiBlue)
                    .frame(width: 7, height: 7)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isPrimaryBlue ? 0.72 : 0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: bgColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.75)
        }
    }
}

struct WatchVoiceHistoryView: View {
    let model: WatchVoiceModel

    var body: some View {
        Group {
            if model.results.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(WatchDesignTokens.skyBlueLight)
                    Text("No tasks yet")
                        .font(WatchDesignTokens.resultBodyFont)
                        .foregroundStyle(WatchDesignTokens.subtitleDefault)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.results) { update in
                    NavigationLink {
                        WatchVoiceResultView(model: model, id: update.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(update.phase.title, systemImage: update.phase.symbol)
                                .font(WatchDesignTokens.buttonFont)
                                .foregroundStyle(update.phase == .finished ? WatchDesignTokens.statusGreenLight : WatchDesignTokens.statusAmberLight)
                            if let text = update.text {
                                Text(text)
                                    .font(WatchDesignTokens.resultBodyFont)
                                    .foregroundStyle(WatchDesignTokens.cardBodyText)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [WatchDesignTokens.hubLatestTop, WatchDesignTokens.hubLatestBottom],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: WatchDesignTokens.hubCardCornerRadius, style: .continuous)
                                    .strokeBorder(WatchDesignTokens.resultCardBorder, lineWidth: 0.75)
                            }
                    )
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(WatchDesignTokens.screenBackground.ignoresSafeArea())
        .navigationTitle("Task history")
    }
}

struct WatchVoiceTaskView: View {
    let model: WatchVoiceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            WatchOLEDBackground(
                center: UnitPoint(x: 0.5, y: 0.42),
                innerColor: model.recording
                    ? Color(hex: 0xFF453A, opacity: 0x42 / 255.0)
                    : Color(hex: 0x0077FD, opacity: 0x42 / 255.0),
                midColor: nil,
                endRadiusFraction: 0.68
            )

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0x16 / 255.0), in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0x2E / 255.0), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .watchGlassControl(in: Circle(), tint: .white.opacity(0.05), interactive: true)
                    .accessibilityLabel("Back")

                    Text("Voice Task")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WatchDesignTokens.skyBlueLight)
                        .lineLimit(1)

                    Spacer()
                }
                .frame(height: 22)
                .padding(.horizontal, 2)

                Spacer(minLength: 6)

                if model.pendingStatus == .idle {
                    taskIdleContent
                } else {
                    ScrollView {
                        taskPendingContent
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }

                Spacer(minLength: 8)

                if !model.recording {
                    NavigationLink {
                        WatchVoiceHistoryView(model: model)
                    } label: {
                        Text("View task history")
                            .font(WatchDesignTokens.secondaryButtonFont)
                            .foregroundStyle(.white.opacity(0xEC / 255.0))
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchDesignTokens.secondaryBottomBarHeight)
                            .background(
                                LinearGradient(
                                    colors: [Color.white.opacity(0x20 / 255.0), Color.white.opacity(0x10 / 255.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0x36 / 255.0), lineWidth: 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                    .watchGlassControl(in: Capsule(), tint: .white.opacity(0.05), interactive: true)
                    .accessibilityIdentifier("watchVoice.history")
                }
            }
            .padding(.top, WatchDesignTokens.screenTopPadding)
            .padding(.horizontal, WatchDesignTokens.screenHorizontalPadding)
            .padding(.bottom, WatchDesignTokens.screenBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if model.microphone == .granted { await model.requestNotifications() }
        }
    }

    private var taskIdleContent: some View {
        VStack(spacing: 8) {
            if model.microphone == .undetermined {
                Button {
                    Task { await model.requestMicrophone() }
                } label: {
                    Label("Enable microphone", systemImage: "mic.fill")
                        .font(WatchDesignTokens.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchDesignTokens.bottomBarHeight)
                        .background(
                            LinearGradient(
                                colors: [WatchDesignTokens.pokiBlueTop, WatchDesignTokens.pokiBlueBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(WatchDesignTokens.glassBlueBorder, lineWidth: 0.75)
                        }
                }
                .buttonStyle(.plain)
                .watchGlassControl(in: Capsule(), tint: WatchDesignTokens.pokiBlue.opacity(0.75), interactive: true)
            } else if model.microphone == .denied {
                VStack(spacing: 6) {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(WatchDesignTokens.statusAmberLight)
                    Text("Allow Poki’s microphone in Watch Settings.")
                        .font(WatchDesignTokens.compactSubtitleFont)
                        .foregroundStyle(WatchDesignTokens.subtitleDefault)
                        .multilineTextAlignment(.center)
                }
            } else {
                recordControl
            }

            if let problem = model.problem {
                Text(problem)
                    .font(WatchDesignTokens.compactSubtitleFont)
                    .foregroundStyle(WatchDesignTokens.subtitleDefault)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    private var taskPendingContent: some View {
        VStack(spacing: 8) {
            switch model.pendingStatus {
            case .idle:
                EmptyView()
            case .sending:
                VStack(spacing: 6) {
                    ProgressView()
                    Label("Sending recording…", systemImage: "arrow.up.circle")
                        .font(WatchDesignTokens.compactTitleFont)
                        .foregroundStyle(WatchDesignTokens.skyBlueLight)
                        .multilineTextAlignment(.center)
                }
            case .deliveryFailed(let failure):
                VStack(spacing: 6) {
                    Label(failure.title, systemImage: failure.symbol)
                        .font(WatchDesignTokens.compactTitleFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(failure.detail)
                        .font(WatchDesignTokens.compactSubtitleFont)
                        .foregroundStyle(WatchDesignTokens.subtitleDefault)
                        .multilineTextAlignment(.center)
                }
            case .tracking(let update):
                VStack(spacing: 6) {
                    Label(update.phase.title, systemImage: update.phase.symbol)
                        .font(WatchDesignTokens.compactTitleFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    if update.phase == .waitingForUnlock {
                        Text("If it doesn’t continue after unlocking, tap the notification on iPhone or tap Check iPhone here.")
                            .font(WatchDesignTokens.compactSubtitleFont)
                            .foregroundStyle(WatchDesignTokens.subtitleDefault)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            if let problem = model.problem {
                Text(problem)
                    .font(WatchDesignTokens.compactSubtitleFont)
                    .foregroundStyle(WatchDesignTokens.subtitleDefault)
                    .multilineTextAlignment(.center)
            }

            if model.hasPending, !model.sending {
                Button {
                    model.sync()
                } label: {
                    Text(model.update == nil ? "Retry delivery" : "Check iPhone")
                        .font(WatchDesignTokens.buttonFont)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: WatchDesignTokens.secondaryBottomBarHeight)
                        .background(
                            LinearGradient(
                                colors: [WatchDesignTokens.pokiBlueTop, WatchDesignTokens.pokiBlueBottom],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .watchGlassControl(in: Capsule(), tint: WatchDesignTokens.pokiBlue.opacity(0.75), interactive: true)

                if model.update == nil {
                    Button(role: .destructive) {
                        model.discardPending()
                    } label: {
                        Text("Cancel")
                            .font(WatchDesignTokens.secondaryButtonFont)
                            .foregroundStyle(WatchDesignTokens.titleRed)
                            .frame(maxWidth: .infinity)
                            .frame(height: WatchDesignTokens.secondaryBottomBarHeight)
                            .background(WatchDesignTokens.statusRedPillFill, in: Capsule())
                            .overlay {
                                Capsule()
                                    .strokeBorder(WatchDesignTokens.statusRedPillBorder, lineWidth: 0.75)
                            }
                    }
                    .buttonStyle(.plain)
                    .watchGlassControl(in: Capsule(), tint: WatchDesignTokens.statusRed.opacity(0.2), interactive: true)
                }
            }
        }
    }

    private var recordControl: some View {
        let isRecording = model.recording
        let orbSize: CGFloat = 86
        let gradientStops = isRecording
            ? [
                Color(hex: 0xFF6B63, opacity: 0x85 / 255.0),
                Color(hex: 0xFF453A, opacity: 0x48 / 255.0),
                Color(hex: 0x26080A, opacity: 0xE6 / 255.0)
            ]
            : [
                Color(hex: 0x5AA7FF, opacity: 0x73 / 255.0),
                Color(hex: 0x0077FD, opacity: 0x38 / 255.0),
                Color(hex: 0x081226, opacity: 0xE6 / 255.0)
            ]
        let ringColor = isRecording
            ? Color(hex: 0xFF7B72, opacity: 0xE0 / 255.0)
            : Color(hex: 0x8AC4FF, opacity: 0xD9 / 255.0)
        let glowColor = isRecording
            ? Color(hex: 0xFF453A, opacity: 0x73 / 255.0)
            : Color(hex: 0x0077FD, opacity: 0x73 / 255.0)

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(glowColor.opacity(0.45))
                    .frame(width: orbSize * 0.9, height: orbSize * 0.9)
                    .blur(radius: 16)
                    .allowsHitTesting(false)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: gradientStops,
                            center: UnitPoint(x: 0.32, y: 0.24),
                            startRadius: 2,
                            endRadius: orbSize * 0.65
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.55), .white.opacity(0.06), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .padding(1)
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(ringColor, lineWidth: 1.5)
                    }
                    .overlay {
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 31, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: orbSize, height: orbSize)
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 15, maximumDistance: 45, perform: {}) { pressing in
                if pressing { model.startRecording() } else { model.stopRecording() }
            }
            .accessibilityLabel(isRecording ? "Send recording" : "Record a task")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isRecording { model.stopRecording() } else { model.startRecording() }
            }
            .accessibilityIdentifier("watchVoice.record")

            VStack(spacing: 2) {
                Text(isRecording ? "Listening…" : "Hold to speak")
                    .font(WatchDesignTokens.compactTitleFont)
                    .foregroundStyle(.white)
                Text(isRecording ? "Release to send" : "Release to send to iPhone")
                    .font(WatchDesignTokens.compactSubtitleFont)
                    .foregroundStyle(WatchDesignTokens.subtitleDefault)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }
}

extension WatchVoiceUpdate.Phase {
    var title: LocalizedStringResource {
        switch self {
        case .received: "iPhone received it"
        case .waitingForUnlock: "Received. Unlock your iPhone."
        case .running: "Poki is working"
        case .finished: "Task finished"
        case .blocked: "Task needs attention"
        }
    }

    var symbol: String {
        switch self {
        case .received: "iphone"
        case .waitingForUnlock: "lock.fill"
        case .running: "ellipsis.circle"
        case .finished: "checkmark.circle"
        case .blocked: "exclamationmark.circle"
        }
    }
}
