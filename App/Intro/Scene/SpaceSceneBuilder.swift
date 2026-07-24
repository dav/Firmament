import RealityKit
import UIKit

/// Builds the heliocentric scene for beats 5–9: the sun, the stylized textured
/// Earth, the orbital path that draws on, the space grid that unfolds from the
/// sun, the lattice-node cubes, and the home marker at the device's
/// coordinates. Returns a `SpaceSceneState` that owns the progressive effects.
@MainActor
enum SpaceSceneBuilder {
    private static let orbitColor = UIColor(white: 0.92, alpha: 1)
    private static let gridColor = UIColor(red: 0.28, green: 0.38, blue: 0.52, alpha: 1)
    private static let markerColor = UIColor.systemRed
    private static let oceanFallbackColor = UIColor(red: 0.09, green: 0.22, blue: 0.42, alpha: 1)

    static func build(
        spaceRoot: Entity,
        earthRig: Entity,
        homeLatitudeDegrees: Double,
        homeLongitudeDegrees: Double
    ) -> SpaceSceneState {
        var groups: [TourEntityID: Entity] = [:]

        groups[.sun] = makeSun(under: spaceRoot)

        // A spin node carries the axial tilt and the per-frame rotation. Both
        // the textured globe and the home marker hang off it, so they turn
        // together and the marker stays locked to its geographic spot. The
        // texture keeps its own longitude offset, so it can be registered
        // against the marker independently.
        let earthSpin = Entity()
        earthSpin.name = "earthSpin"
        earthRig.addChild(earthSpin)

        let earth = makeEarth(under: earthSpin)
        groups[.earth] = earth
        groups[.homeMarker] = makeHomeMarker(
            under: earthSpin,
            latitudeDegrees: homeLatitudeDegrees,
            longitudeDegrees: homeLongitudeDegrees
        )

        let orbit = ModelEntity()
        orbit.name = "orbitPath"
        spaceRoot.addChild(orbit)
        groups[.orbitPath] = orbit

        let grid = ModelEntity()
        grid.name = "spaceGrid"
        spaceRoot.addChild(grid)
        groups[.spaceGrid] = grid

        let nodes = Entity()
        nodes.name = "gridNodes"
        spaceRoot.addChild(nodes)
        groups[.gridNodes] = nodes

        return SpaceSceneState(
            groups: groups,
            earthEntity: earth,
            earthSpin: earthSpin,
            orbitEntity: orbit,
            orbitMaterial: UnlitMaterial(color: orbitColor),
            gridEntity: grid,
            gridMaterial: UnlitMaterial(color: gridColor),
            nodeCubes: makeNodeCubes(under: nodes)
        )
    }

    private static func makeSun(under parent: Entity) -> Entity {
        let sun = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.sunRadius),
            materials: [UnlitMaterial(color: .systemOrange)]
        )
        sun.name = "sun"
        parent.addChild(sun)
        return sun
    }

    /// Stylized Earth. Built synchronously with a flat ocean-blue material so
    /// the tour never waits on asset loading; the equirectangular texture is
    /// swapped in by `SpaceSceneState.applyEarthTexture()` once it loads.
    private static func makeEarth(under parent: Entity) -> ModelEntity {
        let earth = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.earthRadius),
            materials: [UnlitMaterial(color: oceanFallbackColor)]
        )
        earth.name = "earth"
        // If the texture's prime meridian doesn't line up with the home
        // marker's longitude convention, tune this offset in TourTuning.
        earth.orientation = simd_quatf(
            angle: TourTuning.earthTextureLongitudeOffsetDegrees * .pi / 180,
            axis: [0, 1, 0]
        )
        parent.addChild(earth)
        return earth
    }

    private static func makeHomeMarker(
        under parent: Entity,
        latitudeDegrees: Double,
        longitudeDegrees: Double
    ) -> Entity {
        let marker = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.earthRadius * 0.05),
            materials: [UnlitMaterial(color: markerColor)]
        )
        marker.name = "homeMarker"
        marker.position = TourMath.sphereDirection(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees
        ) * (TourTuning.earthRadius * 1.01)
        parent.addChild(marker)
        return marker
    }

    /// Stylized lattice cubes in and around the ecliptic plane near the orbit
    /// ring, colored like the app's real nodes, ordered so the reveal sweeps
    /// outward from where the Earth is during the nodesAppear beat.
    private static func makeNodeCubes(under parent: Entity) -> [ModelEntity] {
        let mesh = CubeMesh.make()
        let materials = CubeFace.defaultColors.map { color in
            UnlitMaterial(
                color: UIColor(
                    red: CGFloat(color.red),
                    green: CGFloat(color.green),
                    blue: CGFloat(color.blue),
                    alpha: 1
                )
            )
        }

        let spacing = TourTuning.gridSpacing
        let edge = spacing * TourTuning.nodeCubeEdgeFraction
        let revealCenterAngle = TourTuning.nodeRevealCenterAngleDegrees * Float.pi / 180
        let revealCenter = TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: revealCenterAngle)

        var cubes: [(entity: ModelEntity, distance: Float)] = []
        let extent = Int((TourTuning.orbitRadius + 2 * spacing) / spacing)
        for i in -extent...extent {
            for k in -extent...extent {
                let x = Float(i) * spacing
                let z = Float(k) * spacing
                let ringDistance = abs(sqrt(x * x + z * z) - TourTuning.orbitRadius)
                guard ringDistance <= 2 * spacing else { continue }
                for j in -1...1 {
                    let position = SIMD3(x, Float(j) * spacing, z)
                    let cube = ModelEntity(mesh: mesh, materials: materials)
                    cube.position = position
                    cube.orientation = TourMath.latticeCubeOrientation
                    cube.scale = SIMD3(repeating: edge)
                    cube.isEnabled = false
                    parent.addChild(cube)
                    cubes.append((cube, simd_distance(position, revealCenter)))
                }
            }
        }
        return cubes.sorted { $0.distance < $1.distance }.map(\.entity)
    }
}
