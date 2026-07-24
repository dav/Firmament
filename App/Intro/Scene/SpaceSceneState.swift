import RealityKit

/// Owns the space scene's progressive effects: the orbit path drawing on, the
/// grid unfolding from the sun, and the node cubes revealing. Each setter is
/// idempotent per quantized step, so calling them every frame (including while
/// scrubbing backwards) is cheap — meshes rebuild only when a step changes.
@MainActor
final class SpaceSceneState {
    let groups: [TourEntityID: Entity]

    private let earthEntity: ModelEntity
    /// Carries the Earth's axial tilt and per-frame spin; both the globe and
    /// the home marker are its children.
    private let earthSpin: Entity
    private let orbitEntity: ModelEntity
    private let orbitMaterial: UnlitMaterial
    private let orbitSegments: [LineSegment]
    private var orbitDrawnCount = -1

    private let gridEntity: ModelEntity
    private let gridMaterial: UnlitMaterial
    private let gridBands: [[LineSegment]]
    private var gridBandCount = -1

    /// In reveal order: nearest to the Earth's position first.
    private let nodeCubes: [ModelEntity]
    /// The reveal front's last position, in cube indices. Only cubes between
    /// the old and new front change opacity, so a frame-rate sweep over
    /// hundreds of cubes touches just a handful of components per frame.
    private var lastNodeFront: Double = 0

    init(
        groups: [TourEntityID: Entity],
        earthEntity: ModelEntity,
        earthSpin: Entity,
        orbitEntity: ModelEntity,
        orbitMaterial: UnlitMaterial,
        gridEntity: ModelEntity,
        gridMaterial: UnlitMaterial,
        nodeCubes: [ModelEntity]
    ) {
        self.groups = groups
        self.earthEntity = earthEntity
        self.earthSpin = earthSpin
        self.orbitEntity = orbitEntity
        self.orbitMaterial = orbitMaterial
        self.gridEntity = gridEntity
        self.gridMaterial = gridMaterial
        self.nodeCubes = nodeCubes
        orbitSegments = Self.makeOrbitSegments()
        gridBands = Self.makeGridBands()
    }

    /// Swaps the placeholder ocean-blue Earth material for the bundled
    /// texture. Runs off the tour's boot path so a slow (or stuck) asset load
    /// can never black out the tour — worst case the Earth stays flat blue.
    func applyEarthTexture(_ texture: TextureResource) {
        earthEntity.model?.materials = [Self.earthMaterial(texture: texture)]
    }

    /// The stylized-Earth unlit material, shared by the space Earth and the
    /// hood-ornament globe so they match at the morph seam.
    static func earthMaterial(texture: TextureResource) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        return material
    }

    /// Orients the globe for tour time `t` (axial tilt + fast prograde spin).
    func setEarthSpin(time: Double) {
        earthSpin.orientation = TourMath.earthSpinOrientation(at: time)
    }

    /// Reveals the leading `fraction` of the orbit circle, sweeping forward
    /// from the draw start angle.
    func setOrbitDrawFraction(_ fraction: Double) {
        let count = Int((fraction * Double(orbitSegments.count)).rounded())
        guard count != orbitDrawnCount else { return }
        orbitDrawnCount = count
        setLineMesh(on: orbitEntity, segments: Array(orbitSegments.prefix(count)), material: orbitMaterial)
    }

    /// Unfolds the grid outward from the sun in radial bands.
    func setGridUnfoldFraction(_ fraction: Double) {
        let count = Int((fraction * Double(gridBands.count)).rounded())
        guard count != gridBandCount else { return }
        gridBandCount = count
        let segments = gridBands.prefix(count).flatMap(\.self)
        setLineMesh(on: gridEntity, segments: segments, material: gridMaterial)
    }

    /// Sweeps node opacity on in reveal order; each cube fades in softly as
    /// the front passes it. Only cubes between the previous and new front are
    /// touched, so this is cheap even called every frame — and scrub-safe in
    /// both directions.
    func setNodeRevealFraction(_ fraction: Double) {
        let front = min(max(fraction, 0), 1) * Double(nodeCubes.count)
        guard front != lastNodeFront, !nodeCubes.isEmpty else { return }
        let low = max(0, Int(min(front, lastNodeFront)) - 1)
        let high = min(nodeCubes.count - 1, Int(max(front, lastNodeFront)) + 1)
        lastNodeFront = front
        guard low <= high else { return }
        for index in low...high {
            let opacity = Float(min(max(front - Double(index), 0), 1))
            TourRenderer.applyOpacity(opacity, to: nodeCubes[index])
        }
    }

    private func setLineMesh(on entity: ModelEntity, segments: [LineSegment], material: UnlitMaterial) {
        guard
            let data = LatticeLineMesh.buildData(segments: segments),
            let mesh = LatticeLineMesh.resource(from: data)
        else {
            entity.model = nil
            return
        }
        entity.model = ModelComponent(mesh: mesh, materials: [material])
    }

    private static func makeOrbitSegments() -> [LineSegment] {
        let count = TourTuning.orbitSegmentCount
        let startAngle = TourTuning.orbitDrawStartAngleDegrees * Float.pi / 180
        return (0..<count).map { step in
            let from = startAngle + Float(step) / Float(count) * 2 * .pi
            let to = startAngle + Float(step + 1) / Float(count) * 2 * .pi
            return LineSegment(
                start: TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: from),
                end: TourMath.circlePoint(radius: TourTuning.orbitRadius, angle: to)
            )
        }
    }

    /// Grid lines in the ecliptic plane, chopped into cell-length pieces and
    /// grouped into radial bands so the unfold can sweep sun → orbit.
    private static func makeGridBands() -> [[LineSegment]] {
        let spacing = TourTuning.gridSpacing
        let maxRadius = TourTuning.orbitRadius + 3 * spacing
        let bandWidth = maxRadius / Float(TourTuning.gridUnfoldBands)
        var bands: [[LineSegment]] = Array(repeating: [], count: TourTuning.gridUnfoldBands)

        let lineCount = Int(maxRadius / spacing)
        for lineIndex in -lineCount...lineCount {
            let offset = Float(lineIndex) * spacing
            for pieceIndex in -lineCount..<lineCount {
                let start = Float(pieceIndex) * spacing
                let end = start + spacing
                for segment in [
                    LineSegment(start: SIMD3(offset, 0, start), end: SIMD3(offset, 0, end)),
                    LineSegment(start: SIMD3(start, 0, offset), end: SIMD3(end, 0, offset))
                ] {
                    let mid = (segment.start + segment.end) / 2
                    let radius = simd_length(mid)
                    guard radius <= maxRadius else { continue }
                    let band = min(Int(radius / bandWidth), TourTuning.gridUnfoldBands - 1)
                    bands[band].append(segment)
                }
            }
        }
        return bands
    }
}
