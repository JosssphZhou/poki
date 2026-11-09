import Foundation

struct PlanStep: Identifiable, Equatable, Codable {
    enum State: String, Equatable, Codable { case current, waiting, done, failed }
    let id: UUID
    var text: String
    var state: State
    init(_ text: String, state: State = .current) { id = UUID(); self.text = text; self.state = state }
}
