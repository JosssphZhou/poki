import Foundation
import UIKit
import PokiCore

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
            return NativeToolAnswer.unavailable("this iPhone did not report a battery level; nothing was read.")
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
