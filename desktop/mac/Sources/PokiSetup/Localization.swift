import Foundation
import Observation

enum SetupLanguage: String {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    func resolve(preferred: [String]) -> String {
        guard self == .system else { return rawValue }
        return Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferred).first ?? "en"
    }
}

@Observable final class SetupLocalization {
    static let shared = SetupLocalization()
    // bundle.sh embeds the SwiftPM bundle in Contents/Resources. Some SwiftPM
    // accessors only check the app root and the original build directory.
    private static let resources = Bundle.main.url(forResource: "PokiSetup_PokiSetup", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? Bundle.module
    private let defaults: UserDefaults
    var language: SetupLanguage {
        didSet { defaults.set(language.rawValue, forKey: "uiLanguage") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = SetupLanguage(rawValue: defaults.string(forKey: "uiLanguage") ?? "") ?? .system
    }

    var locale: Locale {
        var components = Locale.Components(identifier: Locale.current.identifier)
        let selected = language.resolve(preferred: Locale.preferredLanguages)
        components.languageComponents = Locale.Components(identifier: selected).languageComponents
        components.languageComponents.region = Locale.current.region
        return Locale(components: components)
    }

    func text(_ key: String.LocalizationValue, table: String = "Localizable") -> String {
        let resource = LocalizedStringResource(key, table: table, locale: locale, bundle: .atURL(Self.resources.bundleURL))
        return String(localized: resource)
    }
}

func localized(_ key: String.LocalizationValue) -> String {
    SetupLocalization.shared.text(key)
}

func progressLine(_ line: String, in localization: SetupLocalization = .shared) -> String {
    guard localization.locale.language.languageCode?.identifier == "zh" else { return line }
    func text(_ key: String.LocalizationValue) -> String { localization.text(key, table: "Progress") }
    let fixed = text(String.LocalizationValue(stringLiteral: line))
    if fixed != line { return fixed }
    if let match = line.wholeMatch(of: #/Signing Poki for (.+)/#) {
        return text("Signing Poki for \(String(match.1))")
    }
    if let match = line.wholeMatch(of: #/Downloading test build (\d+)/#) {
        return text("Downloading test build \(String(match.1))")
    }
    if let match = line.wholeMatch(of: #/App ID and profile for (.+)/#) {
        return text("App ID and profile for \(String(match.1))")
    }
    if let match = line.wholeMatch(of: #/Poki (\S+) \(([^)]+)\) signed for (.+)/#) {
        return text("Poki \(String(match.1)) (\(String(match.2))) signed for \(String(match.3))")
    }
    if let match = line.wholeMatch(of: #/(.+) \(free, 7-day signing\)/#) {
        return text("\(String(match.1)) (free, 7-day signing)")
    }
    if let match = line.wholeMatch(of: #/(.+) \(paid\)/#) {
        return text("\(String(match.1)) (paid)")
    }
    if let match = line.wholeMatch(of: #/The Apple ID signed in is not on team (.+) any more\./#) {
        return text("The Apple ID signed in is not on team \(String(match.1)) any more.")
    }
    if let match = line.wholeMatch(of: #/Remote pairing did not finish \(([\s\S]+)\)\. Poki can pair on the iPhone instead\./#) {
        return text("Remote pairing did not finish (\(String(match.1))). Poki can pair on the iPhone instead.")
    }
    if let match = line.wholeMatch(of: #/Could not let the iPhone use this pairing over the network \(([\s\S]+)\); Poki may need to pair on the phone\./#) {
        return text("Could not let the iPhone use this pairing over the network (\(String(match.1))); Poki may need to pair on the phone.")
    }
    if let match = line.wholeMatch(of: #/Could not write into Poki's container \(([\s\S]+)\); the QR hand-off below does it instead\./#) {
        return text("Could not write into Poki's container (\(String(match.1))); the QR hand-off below does it instead.")
    }
    if let match = line.wholeMatch(of: #/Could not give Poki its signing identity \(([\s\S]+)\); renewals stay on this computer\./#) {
        return text("Could not give Poki its signing identity (\(String(match.1))); renewals stay on this computer.")
    }
    if let match = line.wholeMatch(of: #/Scan the code with the iPhone's Camera, or open (\S+) on the iPhone/#) {
        return text("Scan the code with the iPhone's Camera, or open \(String(match.1)) on the iPhone")
    }
    if let match = line.wholeMatch(of: #/The iPhone refused a provisioning profile: ([\s\S]+)\. On a free team the phone must be registered on the Apple ID; sign in again\./#) {
        return text("The iPhone refused a provisioning profile: \(String(match.1)). On a free team the phone must be registered on the Apple ID; sign in again.")
    }
    if let match = line.wholeMatch(of: #/Install failed: ([\s\S]+)/#) {
        return text("Install failed: \(String(match.1))")
    }
    if let match = line.wholeMatch(of: #/signing failed: ([\s\S]+)/#) {
        return text("signing failed: \(String(match.1))")
    }
    if let match = line.wholeMatch(of: #/([\s\S]+) left out: a team profile cannot carry the packet-tunnel entitlement, so Poki uses your proxy app's loopback instead\./#) {
        return text("\(String(match.1)) left out: a team profile cannot carry the packet-tunnel entitlement, so Poki uses your proxy app's loopback instead.")
    }
    if let match = line.wholeMatch(of: #/(.+): signed without (.+) \(this team's profile does not carry it\)/#) {
        return text("\(String(match.1)): signed without \(String(match.2)) (this team's profile does not carry it)")
    }
    if let match = line.wholeMatch(of: #/Developer disk image not pre-seeded \(([\s\S]+)\); Poki downloads it itself\./#) {
        return text("Developer disk image not pre-seeded (\(String(match.1))); Poki downloads it itself.")
    }
    if let match = line.wholeMatch(of: #/The developer disk image was not mounted from this computer \(([\s\S]+)\)\. Poki mounts it itself when it connects\./#) {
        return text("The developer disk image was not mounted from this computer (\(String(match.1))). Poki mounts it itself when it connects.")
    }
    if let match = line.wholeMatch(of: #/Could not check whether Poki is running \(([\s\S]+)\)\. Updating anyway\./#) {
        return text("Could not check whether Poki is running (\(String(match.1))). Updating anyway.")
    }
    if let match = line.wholeMatch(of: #/The test build is not available any more \(([\s\S]+)\)\. Renewing with the release instead\./#) {
        return text("The test build is not available any more (\(String(match.1))). Renewing with the release instead.")
    }
    if let match = line.wholeMatch(of: #/Image build (\S+)\./#) {
        return text("Image build \(String(match.1)).")
    }
    if let match = line.wholeMatch(of: #/Replacing the certificate “(.+)” \(serial (.+)\), as you chose/#) {
        return text("Replacing the certificate “\(String(match.1))” (serial \(String(match.2))), as you chose")
    }
    if let match = line.wholeMatch(of: #/(\d+\.\d) of (\d+\.\d) MB/#) {
        return text("\(String(match.1)) of \(String(match.2)) MB")
    }
    if let match = line.wholeMatch(of: #/The iPhone stopped answering while (.+)\. Unplug it, plug it in again and unlock it, then try again\./#) {
        return text("The iPhone stopped answering while \(text(String.LocalizationValue(stringLiteral: String(match.1)))). Unplug it, plug it in again and unlock it, then try again.")
    }
    if let match = line.wholeMatch(of: #/(R2 .+\.) No Beta releases are available\. Try again later\./#) {
        return text("\(text(String.LocalizationValue(stringLiteral: String(match.1)))) No Beta releases are available. Try again later.")
    }
    return line
}

// Resolve stored UI messages when a view renders, so an open banner also follows the picker.
enum SetupMessage {
    case copy(String.LocalizationValue)
    case verbatim(String)

    var text: String {
        switch self {
        case .copy(let key): localized(key)
        case .verbatim(let text): text
        }
    }
}
