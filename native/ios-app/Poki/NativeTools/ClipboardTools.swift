import Foundation
import UIKit
import PokiCore

/// The clipboard is read only when the owner asks a question in the chat. iOS may show its own paste
/// prompt; a refusal leaves the clipboard unread, and an empty clipboard is reported as empty.
enum ClipboardTools {
    static let specs: [ToolSpec] = [
        .make("clipboard_read",
              "Read the text the owner copied, as text. iOS may ask the owner to allow the paste; a refusal means nothing was read. Images or other non-text items are not returned.",
              [:], []),
    ]

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            return NativeToolAnswer.empty("the clipboard has no text\(pasteboard.hasImages ? " (it has an image; images are not read by this tool)" : "").")
        }
        guard let text = pasteboard.string, !text.isEmpty else {
            return NativeToolAnswer.empty("the clipboard has no text.")
        }
        let value = text.count > 200_000 ? String(text.prefix(200_000)) : text
        let suffix = text.count > value.count ? "\n(the clipboard text was cut to its first \(value.count) characters)" : ""
        return NativeToolAnswer.ok("clipboard:\n" + value + suffix)
    }
}

/// The battery level and charging state. Monitoring is turned on only for the read and then put back;
/// a level of -1 means iOS did not report one.
enum BatteryTools {
    static let specs: [ToolSpec] = [
        .make("battery_status",
              "Read this iPhone's battery percentage and whether it is charging. A level of -1 is reported as unreadable rather than zero.",
              [:], []),
    ]

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let device = UIDevice.current
        let wasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true
        defer { device.isBatteryMonitoringEnabled = wasEnabled }
        let level = device.batteryLevel
        guard level >= 0 else {
            return NativeToolAnswer.unavailable("this iPhone did not report a battery level. Turn battery monitoring on in Settings if the device should report it.")
        }
        let percent = Int((level * 100).rounded())
        let state: String
        switch device.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "on battery"
        case .unknown: state = "charging state unknown"
        @unknown default: state = "charging state unknown"
        }
        return NativeToolAnswer.ok("battery: \(percent)%\nstate: \(state)\nsource: UIDevice on this iPhone")
    }
}
