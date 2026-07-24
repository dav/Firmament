#if DEBUG
import SwiftUI

/// DEBUG-only tuning overlay for the tour: pause/play, a timeline scrubber,
/// playback speed, and beat jump chips. The scene is a pure function of time,
/// so dragging the slider re-poses everything live.
struct TourScrubberOverlay: View {
    @Bindable var director: TourDirector
    @State private var wasPausedBeforeScrub = false

    private static let speeds: [Double] = [0.25, 0.5, 1, 2, 4]

    var body: some View {
        if let timeline = director.timeline {
            VStack(spacing: 10) {
                transportRow
                Slider(
                    value: Binding(
                        get: { director.displayTime },
                        set: { director.seek(to: $0) }
                    ),
                    in: 0...max(timeline.totalDuration, 0.01)
                ) { editing in
                    if editing {
                        wasPausedBeforeScrub = director.isPaused
                        director.isPaused = true
                    } else {
                        director.isPaused = wasPausedBeforeScrub
                    }
                }
                beatChips(timeline: timeline)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal)
        }
    }

    private var transportRow: some View {
        HStack {
            Button(
                director.isPaused ? "Play" : "Pause",
                systemImage: director.isPaused ? "play.fill" : "pause.fill"
            ) {
                director.isPaused.toggle()
            }
            .labelStyle(.iconOnly)

            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Speed", selection: $director.playbackSpeed) {
                ForEach(Self.speeds, id: \.self) { speed in
                    Text("\(speed, format: .number.precision(.fractionLength(0...2)))×")
                        .tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
        }
    }

    private var timeLabel: String {
        let total = director.timeline?.totalDuration ?? 0
        return "\(format(director.displayTime)) / \(format(total))"
    }

    private func format(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = t - Double(minutes * 60)
        let secondsText = seconds.formatted(.number.precision(.fractionLength(1)).sign(strategy: .never))
        return "\(minutes):\(seconds < 10 ? "0" : "")\(secondsText)"
    }

    private func beatChips(timeline: ResolvedTimeline) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(timeline.beats, id: \.beat.id) { beat in
                    BeatChip(
                        beat: beat,
                        isCurrent: director.currentBeatID == beat.beat.id
                    ) {
                        director.seek(toBeat: beat.beat.id)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct BeatChip: View {
    let beat: ResolvedBeat
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("\(beat.beat.id.index)")
                    .bold()
                Text("\(beat.duration, format: .number.precision(.fractionLength(0)))s")
                    .foregroundStyle(.secondary)
                if beat.audioURL == nil {
                    Image(systemName: "waveform.slash")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isCurrent ? AnyShapeStyle(.tint.opacity(0.3)) : AnyShapeStyle(.fill.tertiary),
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }
}
#endif
