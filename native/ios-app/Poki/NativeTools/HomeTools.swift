import Foundation
import HomeKit
import PokiCore

/// Turns lights on and off through HomeKit. It waits for the home manager's first update, matches the
/// home, room and light by name, and writes the power characteristic. More than one match is reported
/// as ambiguous instead of choosing for the owner; a batch reports each light separately.
enum HomeTools {
    static let specs: [ToolSpec] = [
        .make("home_set_light",
              "Turn a HomeKit light on or off. name is the light's name (omit to use every light in the room); room and home are optional names. A name that matches more than one light is reported as ambiguous. Each light's result is reported separately.",
              [
                "name": ["type": "string", "description": "The light or switch name."],
                "room": ["type": "string"],
                "home": ["type": "string"],
                "on": ["type": "boolean"],
              ], ["on"]),
    ]

    @MainActor private static let service = HomeService()

    @MainActor static func perform(_ arguments: String) async -> PokiCore.ToolAnswer {
        let args = ToolArgs(arguments)
        guard let on = args.bool("on") else {
            return NativeToolAnswer.invalid("on must be true or false; nothing was changed")
        }
        do {
            let homes = try await service.loadHomes()
            guard !homes.isEmpty else {
                return NativeToolAnswer.empty("no homes or accessories are available. HomeKit needs the Home app set up and access allowed; the Simulator usually has neither.")
            }
            let selectedHomes: [HMHome]
            if let requested = args.string("home") {
                selectedHomes = homes.filter { $0.name.compare(requested, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                if selectedHomes.count > 1 {
                    return NativeToolAnswer.ambiguous("more than one home is named “\(requested)”: \(selectedHomes.map(\.name).joined(separator: ", ")). Ask the owner which one; nothing was changed.")
                }
                if selectedHomes.isEmpty {
                    return NativeToolAnswer.empty("no home is named “\(requested)”. Homes: \(homes.map(\.name).joined(separator: ", ")); nothing was changed.")
                }
            } else if homes.count > 1 {
                return NativeToolAnswer.ambiguous("there is more than one home: \(homes.map(\.name).joined(separator: ", ")). Ask the owner which home; nothing was changed.")
            } else {
                selectedHomes = homes
            }
            let home = selectedHomes[0]
            let requestedRoom = args.string("room")
            let rooms: [HMRoom]
            if let requestedRoom {
                rooms = home.rooms.filter { $0.name.compare(requestedRoom, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                if rooms.count > 1 {
                    return NativeToolAnswer.ambiguous("more than one room is named “\(requestedRoom)”: \(rooms.map(\.name).joined(separator: ", ")). Ask the owner which one; nothing was changed.")
                }
                if rooms.isEmpty {
                    return NativeToolAnswer.empty("no room is named “\(requestedRoom)” in \(home.name). Rooms: \(home.rooms.map(\.name).joined(separator: ", ")); nothing was changed.")
                }
            } else {
                rooms = home.rooms
            }
            // Room-less accessories live in the home's default room; the Home app exposes them in
            // `accessories`, and `rooms` only for rooms that have some. Match names, not identities.
            let accessories = requestedRoom == nil ? home.accessories : rooms.flatMap(\.accessories)
            let requestedName = args.string("name")
            var candidates: [(HMHome, HMService, HMCharacteristic)] = []
            var seen = Set<ObjectIdentifier>()
            for accessory in accessories {
                guard accessory.isReachable, seen.insert(ObjectIdentifier(accessory)).inserted else { continue }
                for service in accessory.services where Self.isLight(service, named: requestedName) {
                    if let power = service.characteristics.first(where: { $0.characteristicType == HMCharacteristicTypePowerState }) {
                        candidates.append((home, service, power))
                    }
                }
            }
            if candidates.isEmpty {
                let names = home.accessories.flatMap { $0.services.filter { Self.isLight($0) }.map { "\($0.accessory?.name ?? ""): \($0.name)" } }
                let namePart = requestedName.map { " “\($0)”" } ?? ""
                let roomPart = requestedRoom.map { " in \($0)" } ?? ""
                let list = names.isEmpty ? "none" : names.joined(separator: ", ")
                return NativeToolAnswer.empty("no light matched\(namePart)\(roomPart). Lights: \(list); nothing was changed.")
            }
            if let requestedName, candidates.count > 1 {
                let labels = candidates.map { "\($0.0.name) / \($0.1.accessory?.name ?? $0.1.name)" }
                return NativeToolAnswer.ambiguous("more than one light matches “\(requestedName)”: \(labels.joined(separator: ", ")). Ask the owner which one; nothing was changed.")
            }
            var lines: [String] = []
            var failures = 0
            for (_, service, power) in candidates {
                let label = "\(service.accessory?.room?.name ?? "No room") / \(service.accessory?.name ?? service.name)"
                do {
                    try await power.writeValue(on)
                    let readBack = (try? await power.readValue()) ?? power.value
                    let state = (readBack as? Bool) == on
                    let readText = (readBack as? Bool).map { $0 ? "on" : "off" } ?? "unknown"
                    let result = state ? (on ? "on" : "off") : "write sent, read back \(readText)"
                    lines.append("\(label): \(result)")
                    if !state { failures += 1 }
                } catch {
                    failures += 1
                    lines.append("\(label): failed — \(error.localizedDescription)")
                }
            }
            let header = failures == 0 ? "changed: \(lines.count) light\(lines.count == 1 ? "" : "s")" : "changed: \(lines.count - failures) of \(lines.count); \(failures) failed"
            return NativeToolAnswer.ok(header + "\n" + lines.joined(separator: "\n"))
        } catch HomeService.Failure.denied {
            return NativeToolAnswer.permission("Home access is not allowed. Open Settings › Privacy & Security › Home and allow Poki. Nothing was changed.")
        } catch HomeService.Failure.timeout {
            return NativeToolAnswer.timeout("HomeKit did not finish loading the home data; nothing was changed. Try again with the Home app open.")
        } catch {
            return NativeToolAnswer.unavailable("HomeKit is not available: \(error.localizedDescription)")
        }
    }

    private static func isLight(_ service: HMService, named: String? = nil) -> Bool {
        let lightTypes: Set<String> = [HMServiceTypeLightbulb, HMServiceTypeSwitch, HMServiceTypeOutlet, HMServiceTypeFan]
        guard lightTypes.contains(service.serviceType) else { return false }
        guard let named else { return true }
        if service.name.compare(named, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame { return true }
        return (service.accessory?.name ?? "").compare(named, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

@MainActor
private final class HomeService: NSObject, HMHomeManagerDelegate {
    enum Failure: Error { case denied, timeout }
    private let manager = HMHomeManager()
    private var loaded = false

    override init() {
        super.init()
        manager.delegate = self
    }

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.loaded = true }
    }

    func loadHomes() async throws -> [HMHome] {
        let status = manager.authorizationStatus
        if status.contains(.restricted) { throw Failure.denied }
        if !loaded {
            for _ in 0..<50 {
                if loaded { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        if status.contains(.authorized) == false, loaded == false {
            throw Failure.denied
        }
        guard loaded else { throw Failure.timeout }
        return manager.homes
    }
}

