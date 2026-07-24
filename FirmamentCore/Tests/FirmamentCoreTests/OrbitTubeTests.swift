import Foundation
import Testing
@testable import FirmamentCore

struct OrbitTubeTests {
    private let julianDay = Astronomy.julianDay(Date(timeIntervalSince1970: 1_782_936_000)) // 2026-06-20 20:00 UTC
    private let spacing = 3_185.0
    private let tubeRadius = 12_742.0

    @Test func ringGeometry() {
        let nodes = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 16,
            halfSpanRings: 7
        )
        // A fixed window: 7 rings each side of the current one, 16 nodes each.
        #expect(nodes.count == 15 * 16)

        // Rings straddle Earth's current position.
        let earth = Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        for tubeNode in nodes {
            let fromEarth = (tubeNode.positionKm - earth).length
            #expect(fromEarth < 7 * spacing + spacing + tubeRadius)
        }
    }

    @Test func ringCountIsIndependentOfNodesPerRing() {
        for perRing in [10, 24, 50] {
            let nodes = OrbitTube.candidateNodes(
                julianDay: julianDay,
                unitSpacingKm: spacing,
                tubeRadiusKm: tubeRadius,
                nodesPerRing: perRing,
                halfSpanRings: 20
            )
            #expect(Set(nodes.map(\.node.i)).count == 41)
            #expect(nodes.count == 41 * perRing)
        }
    }

    @Test func twoNodesPerRingSitOnEclipticPlane() {
        let nodes = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 16,
            halfSpanRings: 2
        )
        let planeNodes = nodes.filter { $0.node.k == 0 }
        let rings = Set(nodes.map(\.node.i))
        #expect(planeNodes.count == rings.count * 2)
        for tubeNode in planeNodes {
            #expect(abs(tubeNode.positionKm.z) < 1e-6)
        }
        // Off-plane nodes are genuinely off the plane.
        for tubeNode in nodes where tubeNode.node.k != 0 {
            #expect(abs(tubeNode.positionKm.z) > tubeRadius * 0.3)
        }
    }

    @Test func oddNodeCountIsForcedEven() {
        let nodes = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 15,
            halfSpanRings: 1
        )
        let perRing = Set(nodes.map(\.node.j)).count
        #expect(perRing == 14)
    }

    @Test func ringSpacingTracksUnitSpacing() {
        // Ring gaps must track the spacing slider at coarse AND fine spacing —
        // fine spacing pushes ring indices past 10^8, stressing time precision.
        for spacing in [100.0, 3_185.0] {
            let nodes = OrbitTube.candidateNodes(
                julianDay: julianDay,
                unitSpacingKm: spacing,
                tubeRadiusKm: tubeRadius,
                nodesPerRing: 10,
                halfSpanRings: 3
            )
            // Centers of adjacent rings (mean of each ring's nodes) sit ~one spacing
            // apart; time parameterization lets true spacing wander ±2% with orbital speed.
            var centers: [Int: Vector3] = [:]
            for tubeNode in nodes {
                let sum = centers[tubeNode.node.i] ?? .zero
                centers[tubeNode.node.i] = sum + tubeNode.positionKm * 0.1
            }
            let rings = centers.keys.sorted()
            for (ring, next) in zip(rings, rings.dropFirst()) {
                let gap = (centers[next]! - centers[ring]!).length
                #expect(abs(gap - spacing) < spacing * 0.02)
            }
        }
    }

    @Test func axisOffsetTranslatesTubeRigidly() {
        let offset = Vector3(x: 1_234, y: -5_678, z: 4_321)
        let centered = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: 50,
            nodesPerRing: 16,
            halfSpanRings: 2
        )
        let threaded = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: 50,
            nodesPerRing: 16,
            halfSpanRings: 2,
            axisOffsetKm: offset
        )
        #expect(centered.count == threaded.count)
        for (base, moved) in zip(centered, threaded) {
            #expect(base.node == moved.node)
            #expect((moved.positionKm - base.positionKm - offset).length < 1e-9)
        }
        // Midline nodes ride at the axis level, not the ecliptic plane.
        for tubeNode in threaded where tubeNode.node.k == 0 {
            #expect(abs(tubeNode.positionKm.z - offset.z) < 1e-6)
        }
    }

    @Test func farRingsExtendShortWindowsOnly() {
        // Tight spacing → short node window → snapped outline hoops carry the
        // bore out toward the far half-length: stations at multiples of 40 rings
        // within ±1,000 rings, outside the ±20-ring node window.
        let far = OrbitTube.farRings(
            julianDay: julianDay,
            unitSpacingKm: 100,
            tubeRadiusKm: tubeRadius,
            pointsPerRing: 24,
            halfSpanRings: 20,
            farHalfLengthKm: 100_000
        )
        #expect((48...51).contains(far.count))
        #expect(far.allSatisfy { $0.stationIndex % 40 == 0 })
        #expect(far.allSatisfy { $0.pointsKm.count == 24 })
        // Every point sits one tube radius from its ring's center.
        for ring in far {
            let center = ring.pointsKm.reduce(Vector3.zero, +) * (1.0 / 24.0)
            for point in ring.pointsKm {
                #expect(abs((point - center).length - tubeRadius) < tubeRadius * 0.001)
            }
        }

        // Coarse spacing → the node window already reaches past the far target,
        // so no outline hoops are needed.
        let none = OrbitTube.farRings(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            pointsPerRing: 24,
            halfSpanRings: 20,
            farHalfLengthKm: 100_000
        )
        #expect(none.isEmpty)
    }

    @Test func farNodeStationsHandOffIntoTheWindow() {
        let stations = OrbitTube.farNodeStations(
            julianDay: julianDay,
            unitSpacingKm: 100,
            halfSpanRings: 20
        )
        // Up to three stride-multiples out per side, all outside the node window.
        #expect((4...6).contains(stations.count))
        #expect(stations.allSatisfy { $0 % 40 == 0 })

        // Nodes for a far station carry the exact identities the node window
        // would assign, so an approaching ring keeps its entities on entry.
        let farNodes = OrbitTube.nodes(
            forStations: [stations[0]],
            unitSpacingKm: 100,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 16
        )
        #expect(farNodes.count == 16)
        for tubeNode in farNodes {
            #expect(tubeNode.node.i == stations[0])
            #expect(tubeNode.node == OrbitTube.nodeKey(ring: stations[0], index: tubeNode.node.j, nodesPerRing: 16))
        }
    }

    @Test func windowCentersOnTheTraveler() {
        // An observer 3,000 km ahead of Earth's center along the orbit gets a
        // ring window shifted 30 stations forward at 100 km spacing, keeping
        // them in the middle of the exact-spacing rings.
        let centered = OrbitTube.currentStation(julianDay: julianDay, unitSpacingKm: 100)
        let ahead = OrbitTube.currentStation(julianDay: julianDay, unitSpacingKm: 100, alongTrackOffsetKm: 3_000)
        #expect(ahead - centered == 30)

        let nodes = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: 100,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 10,
            halfSpanRings: 20,
            alongTrackOffsetKm: 3_000
        )
        let rings = nodes.map(\.node.i)
        #expect(rings.min() == ahead - 20)
        #expect(rings.max() == ahead + 20)
    }

    @Test func nodeKeysAreUniqueAndStable() {
        let nodes = OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 12,
            halfSpanRings: 3
        )
        #expect(Set(nodes.map(\.node)).count == nodes.count)
        // A tick later, the same window of stations yields identical positions.
        let later = OrbitTube.candidateNodes(
            julianDay: julianDay + 0.25 / 86_400,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 12,
            halfSpanRings: 3
        )
        let positionsByNode = Dictionary(uniqueKeysWithValues: nodes.map { ($0.node, $0.positionKm) })
        for tubeNode in later {
            guard let earlier = positionsByNode[tubeNode.node] else { continue }
            #expect((tubeNode.positionKm - earlier).length < 1e-6)
        }
    }

    @Test func degenerateInputsReturnEmpty() {
        #expect(OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: 0,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 16,
            halfSpanRings: 3
        ).isEmpty)
        #expect(OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: -1,
            nodesPerRing: 16,
            halfSpanRings: 3
        ).isEmpty)
        #expect(OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: spacing,
            tubeRadiusKm: tubeRadius,
            nodesPerRing: 16,
            halfSpanRings: -1
        ).isEmpty)
    }
}
