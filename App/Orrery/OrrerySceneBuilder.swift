import RealityKit
import UIKit

/// A mode's node geometry, bucketed by orbit station so only the stations
/// near Earth render. `update(station:)` slides the visibility window as the
/// Earth travels: cube stations show inside `cubeHalfSpan`, outline hoops
/// (tube mode's distant bore sketch) show from there out to
/// `outlineHalfSpan`, and the far side of the orbit renders nothing at all.
@MainActor
final class OrreryNodeGroup {
    let root: Entity
    private let cubeStations: [Entity]
    private let outlineStations: [Entity]
    private let cubeHalfSpan: Int
    private let outlineHalfSpan: Int
    private var lastStation = Int.min

    init(
        root: Entity,
        cubeStations: [Entity],
        outlineStations: [Entity],
        cubeHalfSpan: Int,
        outlineHalfSpan: Int
    ) {
        self.root = root
        self.cubeStations = cubeStations
        self.outlineStations = outlineStations
        self.cubeHalfSpan = cubeHalfSpan
        self.outlineHalfSpan = outlineHalfSpan
    }

    /// Re-windows visibility around Earth's current station. Cheap enough for
    /// the frame loop: it early-outs until the station index actually changes
    /// (every couple of seconds).
    func update(station: Int) {
        guard station != lastStation else { return }
        lastStation = station
        for (index, entity) in cubeStations.enumerated() {
            entity.isEnabled = circularDelta(index, station) <= cubeHalfSpan
        }
        for (index, hoop) in outlineStations.enumerated() {
            let delta = circularDelta(index, station)
            hoop.isEnabled = delta > cubeHalfSpan && delta <= outlineHalfSpan
        }
    }

    private func circularDelta(_ lhs: Int, _ rhs: Int) -> Int {
        let count = cubeStations.count
        let raw = abs(lhs - rhs) % count
        return min(raw, count - raw)
    }
}

/// Builds the miniature heliocentric scene for the picture-in-picture orrery:
/// the sun, the full orbit ring, the textured Earth (tilt + spin + home
/// marker), and one node group per render mode. Deliberately the same visual
/// language as the intro tour's space scene — the PiP is a live, smaller
/// version of the tour's "Earth streaming through the markers" shot.
@MainActor
enum OrrerySceneBuilder {
    private static let orbitColor = UIColor(white: 0.92, alpha: 1)
    private static let markerColor = UIColor.systemRed
    private static let oceanFallbackColor = UIColor(red: 0.09, green: 0.22, blue: 0.42, alpha: 1)

    /// Angular width of one orbit station, radians — stations sit one grid
    /// spacing apart along the orbit, like the tour's cells and the real
    /// tube's rings.
    static var stationAngle: Float {
        2 * .pi / Float(OrreryTuning.orbitStationCount)
    }

    /// Everything except the per-mode node groups. Returns the Earth entity so
    /// the renderer can swap in the texture once it loads.
    static func buildStatics(
        spaceRoot: Entity,
        earthSpin: Entity,
        homeLatitudeDegrees: Double?,
        homeLongitudeDegrees: Double?
    ) -> ModelEntity {
        let sun = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.sunRadius),
            materials: [UnlitMaterial(color: .systemOrange)]
        )
        sun.name = "sun"
        spaceRoot.addChild(sun)

        spaceRoot.addChild(makeOrbitRing())

        let earth = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.earthRadius),
            materials: [UnlitMaterial(color: oceanFallbackColor)]
        )
        earth.name = "earth"
        earth.orientation = simd_quatf(
            angle: TourTuning.earthTextureLongitudeOffsetDegrees * .pi / 180,
            axis: [0, 1, 0]
        )
        earthSpin.addChild(earth)

        if let homeLatitudeDegrees, let homeLongitudeDegrees {
            let marker = ModelEntity(
                mesh: .generateSphere(radius: TourTuning.earthRadius * 0.05),
                materials: [UnlitMaterial(color: markerColor)]
            )
            marker.name = "homeMarker"
            marker.position = TourMath.sphereDirection(
                latitudeDegrees: homeLatitudeDegrees,
                longitudeDegrees: homeLongitudeDegrees
            ) * (TourTuning.earthRadius * 1.01)
            earthSpin.addChild(marker)
        }
        return earth
    }

    /// The node group depicting `mode`, built on demand and parented under
    /// `spaceRoot`. Everything starts disabled; the first `update(station:)`
    /// windows it in around the Earth.
    static func makeNodes(for mode: RenderMode, under spaceRoot: Entity) -> OrreryNodeGroup {
        switch mode {
        case .grid:
            return makeGridNodes(under: spaceRoot)
        case .tube:
            // Like the live view: a few cube rings around Earth, then white
            // outline hoops sketching the bore receding fore and aft.
            return makeRingNodes(
                under: spaceRoot,
                name: "tubeNodes",
                style: RingStyle(
                    ringRadius: OrreryTuning.tubeRingRadius,
                    nodesPerRing: OrreryTuning.tubeNodesPerRing,
                    cubeEdge: OrreryTuning.tubeCubeEdge,
                    outlineHalfSpan: OrreryTuning.tubeOutlineHalfSpan
                )
            )
        case .ride:
            // At real scale the ride tube threads through the observer; from
            // this far out that distinction is sub-pixel, so it reads as a
            // tight sleeve of rings hugging Earth's path. No distant bore —
            // the live ride mode doesn't sketch one either.
            return makeRingNodes(
                under: spaceRoot,
                name: "rideNodes",
                style: RingStyle(
                    ringRadius: OrreryTuning.rideRingRadius,
                    nodesPerRing: OrreryTuning.rideNodesPerRing,
                    cubeEdge: OrreryTuning.rideCubeEdge,
                    outlineHalfSpan: 0
                )
            )
        }
    }

    /// The shape of one tube-family layout: ring size, cubes per ring, and
    /// how far the outline bore extends past the cube window (0 = none).
    private struct RingStyle {
        let ringRadius: Float
        let nodesPerRing: Int
        let cubeEdge: Float
        let outlineHalfSpan: Int
    }

    /// The full orbit circle as a line-segment mesh (the tour draws this on
    /// progressively; the orrery always shows the whole ring).
    private static func makeOrbitRing() -> ModelEntity {
        let count = TourTuning.orbitSegmentCount
        let segments = (0..<count).map { step in
            let from = Float(step) / Float(count) * 2 * .pi
            let to = Float(step + 1) / Float(count) * 2 * .pi
            return LineSegment(
                start: TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: from),
                end: TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: to)
            )
        }
        let ring = ModelEntity()
        ring.name = "orbitRing"
        if let data = LatticeLineMesh.buildData(segments: segments),
           let mesh = LatticeLineMesh.resource(from: data) {
            ring.model = ModelComponent(mesh: mesh, materials: [UnlitMaterial(color: orbitColor)])
        }
        return ring
    }

    /// Grid mode: the stylized lattice cubes in and around the ecliptic plane
    /// near the orbit ring — the tour's layout — bucketed into angular
    /// stations so only the patch around Earth renders.
    private static func makeGridNodes(under parent: Entity) -> OrreryNodeGroup {
        let root = Entity()
        root.name = "gridNodes"
        let mesh = CubeMesh.make()
        let materials = cubeMaterials()
        let spacing = TourTuning.gridSpacing
        let edge = spacing * TourTuning.nodeCubeEdgeFraction

        let sectors = (0..<OrreryTuning.orbitStationCount).map { index in
            let sector = Entity()
            sector.name = "gridSector\(index)"
            sector.isEnabled = false
            root.addChild(sector)
            return sector
        }

        let extent = Int((TourTuning.orbitRadius + 2 * spacing) / spacing)
        for i in -extent...extent {
            for k in -extent...extent {
                let x = Float(i) * spacing
                let z = Float(k) * spacing
                let ringDistance = abs(sqrt(x * x + z * z) - TourTuning.orbitRadius)
                guard ringDistance <= 2 * spacing else { continue }
                // Invert circlePoint's θ → (cos θ, -sin θ) mapping to find the
                // column's orbit angle, then its station bucket.
                let theta = atan2(-z, x)
                let sector = sectors[wrappedStation(Int((theta / stationAngle).rounded()))]
                for j in -1...1 {
                    let cube = ModelEntity(mesh: mesh, materials: materials)
                    cube.position = SIMD3(x, Float(j) * spacing, z)
                    cube.orientation = TourMath.latticeCubeOrientation
                    cube.scale = SIMD3(repeating: edge)
                    sector.addChild(cube)
                }
            }
        }
        parent.addChild(root)
        return OrreryNodeGroup(
            root: root,
            cubeStations: sectors,
            outlineStations: [],
            cubeHalfSpan: OrreryTuning.gridSectorHalfSpan,
            outlineHalfSpan: 0
        )
    }

    /// Tube/ride modes: rings of cubes at grid-spacing stations along the
    /// orbit — the mini version of `OrbitTube.ringCircle` — plus, when
    /// `outlineHalfSpan` > 0, a white outline hoop per station continuing the
    /// bore past the cube window.
    private static func makeRingNodes(
        under parent: Entity,
        name: String,
        style: RingStyle
    ) -> OrreryNodeGroup {
        let root = Entity()
        root.name = name
        let mesh = CubeMesh.make()
        let materials = cubeMaterials()
        var cubeStations: [Entity] = []
        var outlineStations: [Entity] = []

        for station in 0..<OrreryTuning.orbitStationCount {
            let angle = Float(station) * stationAngle
            let center = TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: angle)
            let outward = simd_normalize(center)

            let ring = Entity()
            ring.name = "\(name)Ring\(station)"
            ring.isEnabled = false
            for index in 0..<style.nodesPerRing {
                let around = 2 * .pi * Float(index) / Float(style.nodesPerRing)
                let cube = ModelEntity(mesh: mesh, materials: materials)
                cube.position = center
                    + outward * (style.ringRadius * cos(around))
                    + SIMD3<Float>(0, style.ringRadius * sin(around), 0)
                cube.orientation = TourMath.latticeCubeOrientation
                cube.scale = SIMD3(repeating: style.cubeEdge)
                ring.addChild(cube)
            }
            root.addChild(ring)
            cubeStations.append(ring)

            if style.outlineHalfSpan > 0 {
                let hoop = makeOutlineHoop(center: center, outward: outward, ringRadius: style.ringRadius)
                hoop.name = "\(name)Hoop\(station)"
                hoop.isEnabled = false
                root.addChild(hoop)
                outlineStations.append(hoop)
            }
        }
        parent.addChild(root)
        return OrreryNodeGroup(
            root: root,
            cubeStations: cubeStations,
            outlineStations: outlineStations,
            cubeHalfSpan: OrreryTuning.tubeCubeRingHalfSpan,
            outlineHalfSpan: style.outlineHalfSpan
        )
    }

    /// One station's bore-sketch circle, spanned by the in-plane outward
    /// direction and the ecliptic pole — the mini `OrbitTube.farRings` hoop.
    private static func makeOutlineHoop(
        center: SIMD3<Float>,
        outward: SIMD3<Float>,
        ringRadius: Float
    ) -> ModelEntity {
        let points = OrreryTuning.outlinePointsPerHoop
        let corners = (0...points).map { index -> SIMD3<Float> in
            let around = 2 * .pi * Float(index % points) / Float(points)
            return center
                + outward * (ringRadius * cos(around))
                + SIMD3<Float>(0, ringRadius * sin(around), 0)
        }
        let segments = (0..<points).map { LineSegment(start: corners[$0], end: corners[$0 + 1]) }
        let hoop = ModelEntity()
        if let data = LatticeLineMesh.buildData(segments: segments),
           let meshResource = LatticeLineMesh.resource(from: data) {
            hoop.model = ModelComponent(mesh: meshResource, materials: [UnlitMaterial(color: orbitColor)])
        }
        return hoop
    }

    private static func wrappedStation(_ index: Int) -> Int {
        let count = OrreryTuning.orbitStationCount
        return ((index % count) + count) % count
    }

    private static func cubeMaterials() -> [UnlitMaterial] {
        CubeFace.defaultColors.map { color in
            UnlitMaterial(
                color: UIColor(
                    red: CGFloat(color.red),
                    green: CGFloat(color.green),
                    blue: CGFloat(color.blue),
                    alpha: 1
                )
            )
        }
    }
}
