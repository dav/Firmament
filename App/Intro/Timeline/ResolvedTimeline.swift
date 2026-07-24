import Foundation

/// A narration file found in the bundle, with its probed duration.
nonisolated struct ProbedAudio: Sendable {
    let url: URL
    let duration: TimeInterval
}

/// A beat with its concrete start time and duration after audio resolution.
nonisolated struct ResolvedBeat: Sendable {
    let beat: TourBeat
    let startTime: TimeInterval
    let duration: TimeInterval
    /// nil → no recording bundled; the beat ran on its placeholder duration.
    let audioURL: URL?

    var endTime: TimeInterval { startTime + duration }
}

/// One sampled instant of the tour: everything the scene controller needs to
/// pose the camera and set every entity's state. Pure data — scene state is a
/// function of `time` alone, which is what makes scrubbing trivial.
nonisolated struct TourFrame: Sendable {
    let time: TimeInterval
    let beatID: BeatID
    let beatIndex: Int
    let beatProgress: Double
    let beatStartTime: TimeInterval
    let camera: SampledCamera
    /// Values for every action in the script, in script order.
    let actionValues: [ResolvedActionValue]
    let caption: String
}

/// Where a sampled time falls in the timeline.
nonisolated struct TimelineLocation: Sendable {
    let index: Int
    let beat: ResolvedBeat
    let progress: Double
}

/// The script resolved against probed audio durations into absolute time.
nonisolated struct ResolvedTimeline: Sendable {
    let beats: [ResolvedBeat]

    var totalDuration: TimeInterval { beats.last?.endTime ?? 0 }

    /// Beat duration rule: with a recording, `max(audio + padding, minDuration)`;
    /// without one, the placeholder duration.
    static func resolve(script: TourScript, audio: [BeatID: ProbedAudio]) -> ResolvedTimeline {
        var resolved: [ResolvedBeat] = []
        resolved.reserveCapacity(script.beats.count)
        var cursor: TimeInterval = 0
        for beat in script.beats {
            let duration: TimeInterval
            if let probed = audio[beat.id] {
                duration = max(probed.duration + beat.audioPaddingAfter, beat.minDuration)
            } else {
                duration = beat.placeholderDuration
            }
            resolved.append(
                ResolvedBeat(
                    beat: beat,
                    startTime: cursor,
                    duration: duration,
                    audioURL: audio[beat.id]?.url
                )
            )
            cursor += duration
        }
        return ResolvedTimeline(beats: resolved)
    }

    func beat(withID id: BeatID) -> ResolvedBeat? {
        beats.first { $0.beat.id == id }
    }

    /// The beat containing time `t` (clamped to the timeline), with progress
    /// through it. The final instant belongs to the last beat at progress 1.
    func location(at t: TimeInterval) -> TimelineLocation {
        precondition(!beats.isEmpty, "Cannot locate a time in an empty timeline")
        let clamped = min(max(t, 0), totalDuration)
        for (index, beat) in beats.enumerated() where clamped < beat.endTime || index == beats.count - 1 {
            let progress = beat.duration > 0
                ? min(max((clamped - beat.startTime) / beat.duration, 0), 1)
                : 1
            return TimelineLocation(index: index, beat: beat, progress: progress)
        }
        fatalError("location(at:) fell through a non-empty timeline")
    }

    func sample(at t: TimeInterval) -> TourFrame {
        let location = location(at: t)
        return TourFrame(
            time: min(max(t, 0), totalDuration),
            beatID: location.beat.beat.id,
            beatIndex: location.index,
            beatProgress: location.progress,
            beatStartTime: location.beat.startTime,
            camera: sampleCamera(in: location.beat.beat, progress: location.progress),
            actionValues: sampleActions(currentIndex: location.index, progress: location.progress),
            caption: location.beat.beat.caption
        )
    }

    private func sampleCamera(in beat: TourBeat, progress: Double) -> SampledCamera {
        let keyframes = beat.camera
        guard let first = keyframes.first, let last = keyframes.last else {
            fatalError("TourBeat guarantees at least one camera keyframe")
        }
        if progress <= first.progress {
            return SampledCamera(from: first, to: first, blend: 0)
        }
        if progress >= last.progress {
            return SampledCamera(from: last, to: last, blend: 0)
        }
        for (from, to) in zip(keyframes, keyframes.dropFirst()) where progress <= to.progress {
            let span = to.progress - from.progress
            let linear = span > 0 ? (progress - from.progress) / span : 1
            return SampledCamera(from: from, to: to, blend: to.easing.apply(linear))
        }
        return SampledCamera(from: last, to: last, blend: 0)
    }

    /// Every action in the script with its progress at the sampled instant:
    /// actions in earlier beats read 1, later beats 0, and the current beat's
    /// actions interpolate through their windows.
    private func sampleActions(currentIndex: Int, progress: Double) -> [ResolvedActionValue] {
        var values: [ResolvedActionValue] = []
        for (index, resolvedBeat) in beats.enumerated() {
            for action in resolvedBeat.beat.actions {
                let raw: Double
                if index < currentIndex {
                    raw = 1
                } else if index > currentIndex {
                    raw = 0
                } else {
                    raw = Self.windowProgress(of: action, at: progress)
                }
                values.append(
                    ResolvedActionValue(
                        target: action.target,
                        effect: action.effect,
                        progress: action.easing.apply(raw)
                    )
                )
            }
        }
        return values
    }

    private static func windowProgress(of action: SceneAction, at progress: Double) -> Double {
        let lower = action.range.lowerBound
        let upper = action.range.upperBound
        if progress <= lower { return 0 }
        if progress >= upper { return 1 }
        let span = upper - lower
        return span > 0 ? (progress - lower) / span : 1
    }
}
