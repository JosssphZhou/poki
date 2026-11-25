import Foundation
import PokiCore

/// Photo-library tools are added by the photo-library change.
enum PhotoTools {
    static let specs: [ToolSpec] = []
    static func find(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("photo-library tools are not available in this build.") }
    static func export(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("photo-library tools are not available in this build.") }
    static func save(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.invalid("the path is outside the app's photo workspace; nothing was saved") }
    static func addToAlbum(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("photo-library tools are not available in this build.") }
    static func albums(_ arguments: String) async -> PokiCore.ToolAnswer { NativeToolAnswer.unavailable("photo-library tools are not available in this build.") }
}
