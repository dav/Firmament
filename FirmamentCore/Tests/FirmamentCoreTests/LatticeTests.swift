import Foundation
import Testing
@testable import FirmamentCore

struct LatticeTests {
    @Test func nodesAroundOrigin() {
        // In-plane radius 5000 with spacing 3185 reaches the center column, its 4 axis
        // neighbors (3185 km), and its 4 planar diagonals (4504 km) — 9 columns.
        // Out-of-plane extent 5000 allows k in {-1, 0, 1} for each: 27 nodes total.
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 5_000,
            outOfPlaneHalfExtentKm: 5_000
        )
        #expect(nodes.count == 27)
        #expect(nodes.contains(LatticeNode(i: 0, j: 0, k: 0)))
        #expect(nodes.contains(LatticeNode(i: 1, j: 1, k: -1)))
        #expect(!nodes.contains(LatticeNode(i: 2, j: 0, k: 0)))
    }

    @Test func allNodesWithinBounds() {
        let center = Vector3(x: 10_000, y: 5_000, z: -2_000)
        let spacing = 3_185.0
        let inPlaneRadius = 8_000.0
        let outOfPlaneHalfExtent = 4_000.0
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: center,
            unitSpacingKm: spacing,
            inPlaneRadiusKm: inPlaneRadius,
            outOfPlaneHalfExtentKm: outOfPlaneHalfExtent
        )
        #expect(!nodes.isEmpty)
        for node in nodes {
            let offset = node.positionKm(unitSpacingKm: spacing) - center
            let inPlaneDistance = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            #expect(inPlaneDistance <= inPlaneRadius)
            #expect(abs(offset.z) <= outOfPlaneHalfExtent)
        }
        #expect(nodes.contains(LatticeNode(i: 3, j: 2, k: -1)))
    }

    @Test func outOfPlaneExtentIsIndependentOfSpacing() {
        // A thin slab keeps only k = 0 columns even when the in-plane radius is generous.
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 20_000,
            outOfPlaneHalfExtentKm: 1_000
        )
        #expect(!nodes.isEmpty)
        #expect(nodes.allSatisfy { $0.k == 0 })
    }

    @Test func nodeCountIsCapped() {
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 100,
            inPlaneRadiusKm: 50_000,
            outOfPlaneHalfExtentKm: 1_000,
            maxNodes: 10_000
        )
        #expect(!nodes.isEmpty)
        #expect(nodes.count <= 11_000)
    }

    @Test func capPreservesNearestNodesEvenWhenTiny() {
        // Even an absurdly small budget must keep the lattice plane nearest the center.
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 20_000,
            outOfPlaneHalfExtentKm: 20_000,
            maxNodes: 1
        )
        #expect(!nodes.isEmpty)
        #expect(nodes.contains(LatticeNode(i: 0, j: 0, k: 0)))
    }

    @Test func capShrinksBothReachesProportionally() {
        // A wide, flat request over budget must stay wider than it is tall.
        let spacing = 3_185.0
        let nodes = Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: spacing,
            inPlaneRadiusKm: spacing * 24,
            outOfPlaneHalfExtentKm: spacing * 12,
            maxNodes: 2_000
        )
        #expect(nodes.count <= 2_400)
        let maxInPlane = nodes.map { max(abs($0.i), abs($0.j)) }.max() ?? 0
        let maxOutOfPlane = nodes.map { abs($0.k) }.max() ?? 0
        #expect(maxInPlane > maxOutOfPlane)
        #expect(maxOutOfPlane >= 2)
    }

    @Test func planeNodesAlwaysReachTheEclipticPlane() {
        // Center sits 6000 km above the plane — farther than a shrunken out-of-plane
        // extent would reach — yet the plane disc must still deliver k = 0 nodes.
        let center = Vector3(x: 123_456, y: -98_765, z: 6_000)
        let nodes = Lattice.candidatePlaneNodes(
            aroundHeliocentricKm: center,
            unitSpacingKm: 1_000,
            inPlaneRadiusKm: 76_452,
            maxNodes: 500
        )
        #expect(!nodes.isEmpty)
        #expect(nodes.count <= 600)
        #expect(nodes.allSatisfy { $0.k == 0 })
        let spacing = 1_000.0
        for node in nodes {
            let offset = node.positionKm(unitSpacingKm: spacing) - center
            let inPlaneDistance = (offset.x * offset.x + offset.y * offset.y).squareRoot()
            #expect(inPlaneDistance <= 76_452)
        }
    }

    @Test func degenerateInputsReturnEmpty() {
        #expect(Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 0,
            inPlaneRadiusKm: 100,
            outOfPlaneHalfExtentKm: 100
        ).isEmpty)
        #expect(Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 100,
            inPlaneRadiusKm: -1,
            outOfPlaneHalfExtentKm: 100
        ).isEmpty)
        #expect(Lattice.candidateNodes(
            aroundHeliocentricKm: .zero,
            unitSpacingKm: 100,
            inPlaneRadiusKm: 100,
            outOfPlaneHalfExtentKm: 0
        ).isEmpty)
    }
}
