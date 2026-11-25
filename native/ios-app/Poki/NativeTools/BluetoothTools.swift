import CoreBluetooth
import Foundation
import UIKit
import PokiCore

/// A short foreground scan for broadcasting Bluetooth Low Energy peripherals. It waits for the central
/// to power on, stops at the timeout or when the task is cancelled, and reports the advertised name and
/// signal strength of each peripheral once, keyed by its identifier.
enum BluetoothTools {
    static let specs: [ToolSpec] = [
        .make("bluetooth_scan",
              "Scan for nearby Bluetooth Low Energy devices for a few seconds and return their names and signal strength (RSSI). Scan only while the owner asked; the scan stops at timeout or when the task is stopped. Bluetooth off, permission denied and no devices are reported separately.",
              [
                "seconds": ["type": "integer", "minimum": 1, "maximum": 20],
                "name": ["type": "string", "description": "Only return peripherals whose advertised name contains this text."],
              ], []),
    ]

    @MainActor private static let scanner = BluetoothScanner()

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        guard UIApplication.shared.applicationState == .active else {
            return NativeToolAnswer.unavailable("Bluetooth scanning needs Poki in the foreground; nothing was scanned. The scan is limited to the owner's request.")
        }
        let args = ToolArgs(arguments)
        let seconds = min(20, max(1, args.int("seconds") ?? 5))
        let filter = args.string("name")
        switch scanner.authorization {
        case .denied, .restricted:
            return NativeToolAnswer.permission("Bluetooth access is not allowed. Open Settings › Privacy & Security › Bluetooth and allow Poki. Nothing was scanned.")
        default:
            break
        }
        let result = await scanner.scan(seconds: Double(seconds), filter: filter)
        switch result {
        case .cancelled:
            return NativeToolAnswer.ok("stopped: the Bluetooth scan was stopped; the devices found before then are not reported.")
        case .timeoutNoDevices:
            return NativeToolAnswer.empty("no Bluetooth LE devices were found in \(seconds) s. The scan stopped.")
        case .unavailable(let reason):
            return NativeToolAnswer.unavailable(reason + " Nothing was scanned.")
        case .found(let devices):
            let lines = devices.map { device in
                let signal = device.rssi.map { "\($0) dBm" } ?? "signal unknown"
                return "- \(device.name) — \(signal) — \(device.id)"
            }
            return NativeToolAnswer.ok("bluetooth devices: \(devices.count)\n" + lines.joined(separator: "\n") + "\nthe scan stopped.")
        }
    }
}

/// CBCentralManager's delegate arrives on its own queue; this class keeps the collected peripherals
/// behind a lock and resolves the scan exactly once.
private final class BluetoothScanner: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    enum Result {
        case found([Device])
        case timeoutNoDevices
        case cancelled
        case unavailable(String)
    }
    struct Device { let id: UUID; let name: String; let rssi: Int? }

    private let queue = DispatchQueue(label: "poki.bluetooth.scan")
    private var central: CBCentralManager?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result, Never>?
    private var devices: [UUID: Device] = [:]
    private var filter: String?
    private var started = false
    private var finished = false
    private var timeout: DispatchWorkItem?

    var authorization: CBManagerAuthorization { CBManager.authorization }

    func scan(seconds: Double, filter: String?) async -> Result {
        if lock.withLock({ continuation != nil }) {
            return .unavailable("another Bluetooth scan is already running; nothing was scanned.")
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    self.continuation = continuation
                    self.devices = [:]
                    self.filter = filter?.lowercased()
                    self.started = false
                    self.finished = false
                }
                if central == nil {
                    central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
                }
                let work = DispatchWorkItem { [weak self] in self?.finish(.timeoutNoDevices) }
                timeout = work
                queue.asyncAfter(deadline: .now() + seconds, execute: work)
                if central?.state == .poweredOn { beginScan() }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() { finish(.cancelled) }

    private func beginScan() {
        lock.withLock {
            guard !finished, !started, let central, central.state == .poweredOn else { return }
            started = true
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    private func finish(_ result: Result) {
        var pending: CheckedContinuation<Result, Never>?
        var final = result
        lock.withLock {
            guard !finished else { return }
            finished = true
            timeout?.cancel()
            timeout = nil
            central?.stopScan()
            let collected = Array(devices.values).sorted { ($0.rssi ?? -999) > ($1.rssi ?? -999) }
            if case .timeoutNoDevices = result, !collected.isEmpty {
                final = .found(collected)
            }
            pending = continuation
            continuation = nil
        }
        pending?.resume(returning: final)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScan()
        case .unauthorized:
            finish(.unavailable("Bluetooth permission is not allowed for Poki."))
        case .poweredOff:
            finish(.unavailable("Bluetooth is off on this iPhone."))
        case .unsupported:
            finish(.unavailable("this device does not support Bluetooth LE."))
        case .resetting, .unknown:
            break
        @unknown default:
            finish(.unavailable("Bluetooth is not available."))
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "unnamed"
        let wanted = lock.withLock { filter }
        if let wanted, !wanted.isEmpty, !name.lowercased().contains(wanted) { return }
        lock.withLock {
            guard !finished, devices[peripheral.identifier] == nil else { return }
            devices[peripheral.identifier] = Device(id: peripheral.identifier, name: name,
                                                     rssi: RSSI.intValue == 127 ? nil : RSSI.intValue)
        }
    }
}
