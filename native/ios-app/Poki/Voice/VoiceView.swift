import AVFoundation
import SwiftUI

/// Talk to Poki: say what to do, Poki does it on this iPhone and answers out loud.
struct VoiceView: View {
    @Environment(AppModel.self) private var app
    /// Set when Voice is a sheet over Home: the Done button closes it.
    var close: (() -> Void)?
    /// Pushed from Settings › Model: no navigation stack or Done of its own.
    var embedded = false
    @State private var bridgeText = ""
    @State private var editingBridge = false
    @State private var bridgeRejected = false
    @State private var micDenied = false

    private var voice: VoiceModel { app.voice }

    var body: some View {
        if embedded { form } else { NavigationStack { form.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let close { close() } else { dismiss() } } } } } }
    }

    private var form: some View {
        @Bindable var voice = voice
        return List {
                // Voice runs on the message field (the black button: Talk with Poki for a live conversation, Dictate
                // for dictation). This page only says how it runs and keeps its options.
                PaperSection {
                    LabeledContent("Live voice") {
                        Text(voice.canTalkLive ? (VoiceDirect.apiKey != nil ? String(localized: "OpenAI key") : String(localized: "Voice bridge")) : String(localized: "Not available"))
                            .foregroundStyle(voice.canTalkLive ? Paper.ink2 : Paper.ink)
                    }
                    LabeledContent("Dictation", value: String(localized: "On this iPhone"))
                    Toggle("Mute Poki’s voice", isOn: $voice.muted)
                } footer: {
                    if micDenied { Text("Poki can't use the microphone. Allow it in Settings, Privacy, Microphone.").foregroundStyle(Paper.ink) }
                    else if voice.canTalkLive {
                        Text("Talk with Poki, behind the black button on the message field, is a live conversation: Poki listens, acts and answers out loud. It ends by itself 8 seconds after an answer if nobody speaks, and when Poki goes to the background (once a running step is done). Tap End to stop sooner. Dictate only turns your words into text.")
                    } else {
                        Text("A live conversation uses OpenAI’s Realtime voice, which needs an OpenAI API key in Settings › Model. Dictation in the message field works with every model.")
                    }
                }
                if voice.lastTurnMS != nil || voice.bridge != nil || VoiceDirect.apiKey == nil {
                    PaperSection {
                        if let ms = voice.lastTurnMS { LabeledContent("Last answer", value: "\(ms) ms") }
                        bridgeRows
                    } header: {
                        Text("Advanced")
                    }
                }
            }
            .paperList()
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
    }

    @Environment(\.dismiss) private var dismiss

    @ViewBuilder private var bridgeRows: some View {
        if let bridge = voice.bridge, !editingBridge {
            LabeledContent("Mac voice bridge") { Text(bridge.display).font(.footnote.monospaced()) }
            Button("Change address") { bridgeText = bridge.base.absoluteString; bridgeRejected = false; editingBridge = true }
        } else {
            TextField("Mac voice bridge address", text: $bridgeText)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit(saveBridge)
            Button("Save address", action: saveBridge).disabled(bridgeText.trimmingCharacters(in: .whitespaces).isEmpty)
            Text(bridgeRejected ? "That is not a voice bridge address. It looks like http://192.168.1.10:47830/voice/ followed by a long code." : "Optional, for live voice without an OpenAI key on this iPhone: run bin/voice-bridge.mjs on your Mac and enter the address it gives.")
                .font(.footnote).foregroundStyle(bridgeRejected ? Paper.ink : Paper.ink2)
        }
    }

    private func saveBridge() {
        bridgeRejected = !voice.setBridge(bridgeText)
        if !bridgeRejected { editingBridge = false }
    }

    private var symbol: String {
        switch voice.phase {
        case .off: "waveform.slash"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .listening, .hearing: "waveform"
        case .thinking: "hand.tap.fill"
        case .speaking: "speaker.wave.2.fill"
        case .lost: "exclamationmark.triangle.fill"
        }
    }

    private static func icon(_ role: VoiceLine.Role) -> String {
        switch role {
        case .you: "person.wave.2"
        case .poki: "pawprint.fill"
        case .tool: "hand.tap"
        case .note: "info.circle"
        }
    }
}

private extension View {
    /// Liquid Glass on iOS 26; the bordered prominent style before it.
    @ViewBuilder func prominentGlass() -> some View {
        if #available(iOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }
}
