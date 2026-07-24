import Foundation
import Testing
@testable import Firmament

private func makeBeat(
    id: BeatID,
    minDuration: TimeInterval = 5,
    placeholderDuration: TimeInterval = 7,
    padding: TimeInterval = 0.75,
    camera: [CameraKeyframe]? = nil,
    actions: [SceneAction] = []
) -> TourBeat {
    TourBeat(
        id: id,
        caption: "caption \(id.rawValue)",
        minDuration: minDuration,
        placeholderDuration: placeholderDuration,
        audioPaddingAfter: padding,
        camera: camera ?? [
            CameraKeyframe(
                progress: 0,
                frame: .world,
                position: .zero,
                lookAt: SIMD3(0, 0, -1),
                fovDegrees: 60
            )
        ],
        actions: actions
    )
}

private let dummyURL = URL(fileURLWithPath: "/dev/null")

struct TimelineResolutionTests {
    @Test func audioLongerThanMinimumDrivesDuration() {
        let script = TourScript(beats: [makeBeat(id: .racecar, minDuration: 5)])
        let timeline = ResolvedTimeline.resolve(
            script: script,
            audio: [.racecar: ProbedAudio(url: dummyURL, duration: 9)]
        )
        #expect(timeline.beats[0].duration == 9.75)
    }

    @Test func shortAudioFallsBackToMinimumDuration() {
        let script = TourScript(beats: [makeBeat(id: .racecar, minDuration: 5)])
        let timeline = ResolvedTimeline.resolve(
            script: script,
            audio: [.racecar: ProbedAudio(url: dummyURL, duration: 1)]
        )
        #expect(timeline.beats[0].duration == 5)
    }

    @Test func missingAudioUsesPlaceholderDuration() {
        let script = TourScript(beats: [makeBeat(id: .racecar, placeholderDuration: 7)])
        let timeline = ResolvedTimeline.resolve(script: script, audio: [:])
        #expect(timeline.beats[0].duration == 7)
        #expect(timeline.beats[0].audioURL == nil)
    }

    @Test func startTimesAccumulate() {
        let script = TourScript(beats: [
            makeBeat(id: .racecar, placeholderDuration: 10),
            makeBeat(id: .noSurroundings, placeholderDuration: 8),
            makeBeat(id: .linesVanish, placeholderDuration: 5)
        ])
        let timeline = ResolvedTimeline.resolve(script: script, audio: [:])
        #expect(timeline.beats.map(\.startTime) == [0, 10, 18])
        #expect(timeline.totalDuration == 23)
    }
}

struct TimelineLocationTests {
    private let timeline = ResolvedTimeline.resolve(
        script: TourScript(beats: [
            makeBeat(id: .racecar, placeholderDuration: 10),
            makeBeat(id: .noSurroundings, placeholderDuration: 8)
        ]),
        audio: [:]
    )

    @Test func startBelongsToFirstBeat() {
        let location = timeline.location(at: 0)
        #expect(location.index == 0)
        #expect(location.progress == 0)
    }

    @Test func beatBoundaryBelongsToNextBeat() {
        let location = timeline.location(at: 10)
        #expect(location.index == 1)
        #expect(location.progress == 0)
    }

    @Test func midBeatProgressIsFractional() {
        let location = timeline.location(at: 14)
        #expect(location.index == 1)
        #expect(abs(location.progress - 0.5) < 1e-9)
    }

    @Test func timesBeyondTheEndClampToLastBeat() {
        let location = timeline.location(at: 99)
        #expect(location.index == 1)
        #expect(location.progress == 1)
    }

    @Test func negativeTimesClampToStart() {
        let location = timeline.location(at: -5)
        #expect(location.index == 0)
        #expect(location.progress == 0)
    }
}

struct CameraSamplingTests {
    private let timeline = ResolvedTimeline.resolve(
        script: TourScript(beats: [
            makeBeat(
                id: .racecar,
                placeholderDuration: 10,
                camera: [
                    CameraKeyframe(
                        progress: 0.2,
                        frame: .world,
                        position: .zero,
                        lookAt: SIMD3(0, 0, -1),
                        fovDegrees: 50,
                        easing: .linear
                    ),
                    CameraKeyframe(
                        progress: 0.8,
                        frame: .car,
                        position: SIMD3(10, 0, 0),
                        lookAt: SIMD3(10, 0, -1),
                        fovDegrees: 70,
                        easing: .linear
                    )
                ]
            )
        ]),
        audio: [:]
    )

    @Test func beforeFirstKeyframeHoldsIt() {
        let camera = timeline.sample(at: 1).camera
        #expect(camera.blend == 0)
        #expect(camera.from.fovDegrees == 50)
        #expect(camera.to.fovDegrees == 50)
    }

    @Test func afterLastKeyframeHoldsIt() {
        let camera = timeline.sample(at: 9).camera
        #expect(camera.from.fovDegrees == 70)
        #expect(camera.blend == 0)
    }

    @Test func midpointBlendsLinearly() {
        let camera = timeline.sample(at: 5).camera
        #expect(abs(camera.blend - 0.5) < 1e-9)
        #expect(camera.from.frame == .world)
        #expect(camera.to.frame == .car)
        #expect(abs(Double(camera.fovDegrees) - 60) < 1e-6)
    }
}

struct ActionSamplingTests {
    private let fade = SceneAction(
        target: .grass,
        effect: .fadeOpacity(from: 1, to: 0),
        range: 0.25...0.75,
        easing: .linear
    )

    private var timeline: ResolvedTimeline {
        ResolvedTimeline.resolve(
            script: TourScript(beats: [
                makeBeat(id: .racecar, placeholderDuration: 10, actions: [fade]),
                makeBeat(id: .noSurroundings, placeholderDuration: 10)
            ]),
            audio: [:]
        )
    }

    @Test func beforeWindowIsZero() {
        #expect(timeline.sample(at: 1).actionValues[0].progress == 0)
    }

    @Test func withinWindowInterpolates() {
        let value = timeline.sample(at: 5).actionValues[0]
        #expect(abs(value.progress - 0.5) < 1e-9)
    }

    @Test func afterWindowIsOne() {
        #expect(timeline.sample(at: 9).actionValues[0].progress == 1)
    }

    @Test func earlierBeatActionsStayCompleteInLaterBeats() {
        #expect(timeline.sample(at: 15).actionValues[0].progress == 1)
    }

    @Test func samplesCarryEveryActionInScriptOrder() {
        #expect(timeline.sample(at: 15).actionValues.count == 1)
        #expect(timeline.sample(at: 15).actionValues[0].target == .grass)
    }
}

struct EasingTests {
    @Test func endpointsArePreserved() {
        for easing: TourEasing in [.linear, .easeIn, .easeOut, .easeInOut] {
            #expect(easing.apply(0) == 0)
            #expect(easing.apply(1) == 1)
        }
    }

    @Test func valuesOutsideUnitRangeClamp() {
        #expect(TourEasing.easeInOut.apply(-1) == 0)
        #expect(TourEasing.easeInOut.apply(2) == 1)
    }

    @Test func easingIsMonotonic() {
        for easing: TourEasing in [.linear, .easeIn, .easeOut, .easeInOut] {
            var previous = -0.001
            for step in 0...20 {
                let value = easing.apply(Double(step) / 20)
                #expect(value >= previous)
                previous = value
            }
        }
    }
}

struct BeatIDTests {
    @Test func audioResourceNamesFollowConvention() {
        #expect(BeatID.racecar.audioResourceName == "intro-01-racecar")
        #expect(BeatID.noSurroundings.audioResourceName == "intro-02-no-surroundings")
        #expect(BeatID.zoomHome.audioResourceName == "intro-09-zoom-home")
    }

    @Test func scriptContainsEveryBeatExactlyOnceInOrder() {
        #expect(IntroScript.script.beats.map(\.id) == BeatID.allCases)
    }
}
