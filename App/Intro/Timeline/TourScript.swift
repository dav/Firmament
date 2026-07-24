import Foundation

/// Identifies one narrated beat of the intro tour, in script order.
nonisolated enum BeatID: String, CaseIterable, Sendable {
    case racecar
    case noSurroundings
    case linesVanish
    case blackness
    case earthReveal
    case orbitDrawn
    case gridUnfolds
    case nodesAppear
    case zoomHome

    /// 1-based position in script order.
    var index: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    /// Bundled narration resource name (no extension), e.g.
    /// `intro-02-no-surroundings`.
    var audioResourceName: String {
        let kebab = rawValue.reduce(into: "") { result, character in
            if character.isUppercase {
                result.append("-")
                result.append(Character(character.lowercased()))
            } else {
                result.append(character)
            }
        }
        return "intro-0\(index)-\(kebab)"
    }
}

/// One narrated beat: its caption, timing rules, camera path, and scene
/// actions. Camera keyframes and action ranges are expressed as fractions of
/// beat progress, so they stretch automatically when recorded narration
/// changes the beat's duration.
nonisolated struct TourBeat: Sendable {
    let id: BeatID
    let caption: String
    /// Beat never runs shorter than this, even with a short recording.
    let minDuration: TimeInterval
    /// Used when the narration audio file is missing.
    let placeholderDuration: TimeInterval
    /// Breathing room after the narration ends before the next beat.
    let audioPaddingAfter: TimeInterval
    let camera: [CameraKeyframe]
    let actions: [SceneAction]

    init(
        id: BeatID,
        caption: String,
        minDuration: TimeInterval,
        placeholderDuration: TimeInterval,
        audioPaddingAfter: TimeInterval = 0.75,
        camera: [CameraKeyframe],
        actions: [SceneAction] = []
    ) {
        precondition(!camera.isEmpty, "Every beat needs at least one camera keyframe")
        self.id = id
        self.caption = caption
        self.minDuration = minDuration
        self.placeholderDuration = placeholderDuration
        self.audioPaddingAfter = audioPaddingAfter
        self.camera = camera.sorted { $0.progress < $1.progress }
        self.actions = actions
    }
}

/// The whole tour, in beat order.
nonisolated struct TourScript: Sendable {
    let beats: [TourBeat]
}
