import Foundation

/// One step of "point the phone over there", ready to render.
nonisolated struct FlareAimInstruction: Sendable, Equatable, Identifiable {
    let systemImage: String
    let text: String

    var id: String { text }
}
