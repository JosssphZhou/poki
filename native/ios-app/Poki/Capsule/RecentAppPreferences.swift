import Foundation
#if DEBUG
import CryptoKit
#endif

enum RecentAppPreferences {
    static let defaults: UserDefaults = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pokiUITestDuplicateRecentApps") {
            let suite = fixtureSuite ?? UUID().uuidString
            let defaults = UserDefaults(suiteName: "poki.ui-test.recents." + suite)!
            // A unique unlisted ID makes accidental persistence detectable even if Notes was already first.
            let recent = ["com.apple.mobilenotes", "COM.APPLE.MOBILENOTES", "com.apple.mobilenotes", "test.poki.recents." + suite]
            defaults.set(recent, forKey: RecentAppsStore.defaultsKey)
            defaults.set(recent, forKey: "mentions.recent")
            return defaults
        }
        #endif
        return .standard
    }()

    #if DEBUG
    private static var fixtureSuite: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-pokiUITestRecentsSuite"), index + 1 < arguments.count,
              let uuid = UUID(uuidString: arguments[index + 1]) else { return nil }
        return uuid.uuidString
    }

    static func cleanFixtureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-pokiUITestCleanupRecents"), let suite = fixtureSuite else { return }
        UserDefaults.standard.removePersistentDomain(forName: "poki.ui-test.recents." + suite)
    }

    /// Compare the owner's persisted values across launches without exposing the app IDs in test output.
    static var persistedFingerprint: String {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier!) ?? [:]
        let values = [RecentAppsStore.defaultsKey, "mentions.recent"].map { domain[$0] ?? NSNull() }
        let data = (try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif
}
