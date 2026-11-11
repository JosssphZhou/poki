import Foundation
import XCTest

// Only the device ABI and unused iOS keyboard APIs are replaced. NativeServicesWDA is compiled unchanged.
final class NativeDevice: @unchecked Sendable {
    static let shared = NativeDevice()
    var started: XCTestExpectation!
    private let lock = NSLock()
    private var pending: (() -> Void)?

    func call(_ request: [String: Any], complete: @escaping () -> Void) {
        if request["op"] as? String == "tap" {
            lock.lock()
            pending = complete
            lock.unlock()
            started.fulfill()
        } else {
            precondition(request["op"] as? String == "ax_tree")
            complete()
        }
    }

    func finishInput() {
        lock.lock()
        let completion = pending
        pending = nil
        lock.unlock()
        completion?()
    }
}

func poki_native_client_new(_ config: UnsafePointer<CChar>) -> OpaquePointer? { OpaquePointer(bitPattern: 1) }
func poki_native_client_free(_ handle: OpaquePointer) {}
func poki_native_client_call(
    _ handle: OpaquePointer, _ json: UnsafePointer<CChar>,
    _ callback: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void,
    _ context: UnsafeMutableRawPointer?
) -> Int32 {
    let request = try! JSONSerialization.jsonObject(with: Data(String(cString: json).utf8)) as! [String: Any]
    NativeDevice.shared.call(request) {
        #"{"ok":true,"value":{"elements":[]}}"#.withCString { callback(context, $0) }
    }
    return 0
}

enum AppFiles { static let pairingFile = URL(fileURLWithPath: "/unused-test-pairing") }
enum KeyboardLink {
    static var directory: URL? { nil }
    static let holdFile = "hold", releaseFile = "release"
    struct Hold { let expires: Date }
    static func remove(_ file: String, in directory: URL) { fatalError("Unexpected keyboard access") }
    static func write(_ hold: Hold, _ file: String, in directory: URL) { fatalError("Unexpected keyboard access") }
}

struct PokiKeyboardTyping {
    static let displayName = "Poki", lastDeclineKey = "test.lastDecline", switchBackKey = "test.switchBack"
    static var available: Bool { false }
    static var quickTrusted: Bool { false }
    static var lastStatus: Status? { nil }
    static func setting(_ key: String) -> Bool { false }
    static func release() { fatalError("Unexpected keyboard access") }
    struct Options {
        var clear = false, hidden = false, maySwitch = false
        var app: String?
        var budget = 0.0
    }
    enum Check: String { case unknown }
    struct Status { var check: Check?; var moved = false; var tail: String?; var visible = false }
    enum Result { case typed(Status), declined(String) }
    init(_ choose: @escaping (Bool) async throws -> (String?, Bool)) {}
    func type(_ text: String, _ options: Options) async throws -> Result { fatalError("Unexpected keyboard access") }
}

struct NativeIME {
    init(screen: CGSize, call: @escaping ([String: Any]) async throws -> [String: Any]) {}
    static func isHan(_ character: Character) -> Bool { false }
    static func plan(_ text: String) throws -> [String] { fatalError("Unexpected IME access") }
    static func rect(_ frame: Any?) -> CGRect { fatalError("Unexpected IME access") }
    func type(_ text: String, clear: Bool, frequency: Int?) async throws -> String { fatalError("Unexpected IME access") }
}
