import AVFoundation

/// Finds and plays the user's narration recordings, one segment per beat.
/// Files live in the bundle as `intro-NN-slug.m4a` (see IntroScript.swift for
/// the full list); a missing file is fine — its beat runs on the placeholder
/// duration with captions only.
@MainActor
final class TourAudioLibrary {
    private var player: AVAudioPlayer?
    private var hasConfiguredSession = false

    /// Locates each beat's recording and probes its duration. The duration
    /// loads suspend rather than block, so main-actor isolation is fine here.
    /// Missing files are logged and omitted.
    static func probe(script: TourScript) async -> [BeatID: ProbedAudio] {
        var result: [BeatID: ProbedAudio] = [:]
        for beat in script.beats {
            guard let url = Bundle.main.url(
                forResource: beat.id.audioResourceName,
                withExtension: "m4a"
            ) else {
                Log.warn("intro.audio.missing", ["beat": beat.id.rawValue])
                continue
            }
            do {
                let duration = try await AVURLAsset(url: url).load(.duration).seconds
                result[beat.id] = ProbedAudio(url: url, duration: duration)
            } catch {
                Log.warn("intro.audio.unreadable", [
                    "beat": beat.id.rawValue,
                    "error": String(describing: error)
                ])
            }
        }
        return result
    }

    /// Starts the beat's narration at `offset` seconds in (for seeks mid-beat).
    func play(beat: ResolvedBeat, atOffset offset: TimeInterval, rate: Float) {
        stop()
        guard let url = beat.audioURL else { return }
        configureSessionIfNeeded()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = rate
            player.currentTime = max(0, offset)
            player.play()
            self.player = player
        } catch {
            Log.warn("intro.audio.playbackFailed", [
                "beat": beat.beat.id.rawValue,
                "error": String(describing: error)
            ])
        }
    }

    func pause() {
        player?.pause()
    }

    func resume() {
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    private func configureSessionIfNeeded() {
        guard !hasConfiguredSession else { return }
        hasConfiguredSession = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.warn("intro.audio.sessionFailed", ["error": String(describing: error)])
        }
    }
}
