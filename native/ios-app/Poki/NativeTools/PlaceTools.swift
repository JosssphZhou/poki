import Foundation
import PokiCore

/// Location, map and weather tools are added by that change.
enum PlaceTools {
    struct WeatherCredit: Equatable { var service: String; var legal: URL; var markLight: URL; var markDark: URL }
    @MainActor static private(set) var lastWeatherCredit: WeatherCredit?
    static let specs: [ToolSpec] = []
    static func current(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("location tools are not available in this build.") }
    static func geocode(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("map tools are not available in this build.") }
    static func search(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("map tools are not available in this build.") }
    static func route(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("map tools are not available in this build.") }
    static func weather(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("weather tools are not available in this build.") }
}
