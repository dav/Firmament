import Foundation
import Observation

/// The tour's clock: advances time, samples the resolved timeline, detects
/// beat boundaries, and keeps narration playback in sync. Never touches
/// RealityKit — the renderer applies `currentFrame` each render tick.
@MainActor
@Observable
final class TourDirector {
    enum Phase: Equatable {
        case loading
        case ready
        case playing
        case finished
    }

    private(set) var phase: Phase = .loading
    /// Mutates every render frame; deliberately untracked so SwiftUI doesn't
    /// re-evaluate the tour view at display rate. The renderer reads it from
    /// its own update subscription, not through observation.
    @ObservationIgnored private(set) var time: TimeInterval = 0
    @ObservationIgnored private(set) var currentFrame: TourFrame?
    /// Observable beat-granularity mirrors of `currentFrame` for the UI.
    private(set) var currentBeatID: BeatID?
    private(set) var currentCaption = ""
    /// Coarse (~5 Hz) mirror of `time` for the DEBUG scrubber, so an open
    /// scrubber doesn't invalidate SwiftUI every frame.
    private(set) var displayTime: TimeInterval = 0
    private(set) var timeline: ResolvedTimeline?
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused { audio.pause() } else { audio.resume() }
        }
    }
    var playbackSpeed: Double = 1.0 {
        didSet { audio.setRate(Float(playbackSpeed)) }
    }

    var onFinished: (() -> Void)?

    private let audio = TourAudioLibrary()
    private var currentBeatIndex: Int?

    /// Probes bundled narration and resolves the script into absolute time.
    func load() async {
        let probed = await TourAudioLibrary.probe(script: IntroScript.script)
        let resolved = ResolvedTimeline.resolve(script: IntroScript.script, audio: probed)
        timeline = resolved
        setFrame(resolved.sample(at: 0))
        phase = .ready
        Log.info("intro.start", [
            "total_duration_s": resolved.totalDuration,
            "beats_with_audio": resolved.beats.count(where: { $0.audioURL != nil })
        ])
    }

    func play() {
        guard phase == .ready else { return }
        phase = .playing
        enterBeat(at: time)
    }

    /// Called once per render frame by the renderer's update subscription.
    /// The delta is clamped because RealityKit's first update event after a
    /// subscription can report seconds of "elapsed" time — observed jumping
    /// the tour clock ~9 s on launch — and a hitched frame shouldn't teleport
    /// the tour either.
    func advance(by delta: TimeInterval) {
        guard phase == .playing, !isPaused, let timeline else { return }
        time += min(max(delta, 0), 0.25) * playbackSpeed
        if time >= timeline.totalDuration {
            time = timeline.totalDuration
            setFrame(timeline.sample(at: time))
            finish()
            return
        }
        let frame = timeline.sample(at: time)
        if frame.beatIndex != currentBeatIndex {
            enterBeat(at: time)
        }
        setFrame(frame)
    }

    func seek(to target: TimeInterval) {
        guard let timeline else { return }
        time = min(max(target, 0), timeline.totalDuration)
        setFrame(timeline.sample(at: time))
        displayTime = time
        if phase == .finished, time < timeline.totalDuration {
            phase = .playing
        }
        enterBeat(at: time)
    }

    func seek(toBeat id: BeatID) {
        guard let timeline, let beat = timeline.beat(withID: id) else { return }
        seek(to: beat.startTime)
    }

    /// Jumps to the start of the next beat (the tour's "Next" control); on the
    /// last beat it runs the clock out so the tour finishes.
    func skipToNextBeat() {
        guard let timeline else { return }
        let nextIndex = timeline.location(at: time).index + 1
        if nextIndex < timeline.beats.count {
            seek(to: timeline.beats[nextIndex].startTime)
        } else {
            seek(to: timeline.totalDuration)
        }
    }

    private func enterBeat(at target: TimeInterval) {
        guard let timeline else { return }
        let location = timeline.location(at: target)
        currentBeatIndex = location.index
        Log.info("intro.beat", [
            "index": location.index + 1,
            "id": location.beat.beat.id.rawValue,
            "duration_s": location.beat.duration,
            "audio_found": location.beat.audioURL != nil
        ])
        if !isPaused, phase == .playing {
            audio.play(
                beat: location.beat,
                atOffset: location.progress * location.beat.duration,
                rate: Float(playbackSpeed)
            )
        }
    }

    /// Stores the frame (untracked) and updates the observable mirrors only
    /// when their values actually change, keeping SwiftUI churn at beat rate.
    private func setFrame(_ frame: TourFrame) {
        currentFrame = frame
        if currentBeatID != frame.beatID {
            currentBeatID = frame.beatID
            currentCaption = frame.caption
        }
        if abs(frame.time - displayTime) > 0.2 {
            displayTime = frame.time
        }
    }

    private func finish() {
        guard phase != .finished else { return }
        phase = .finished
        audio.stop()
        onFinished?()
    }
}
