import RealityKit

/// Flat rings and discs in the XZ plane with +Y normals — the track pavement,
/// its painted edge lines, and the grass around it.
enum RingMesh {
    /// An annulus from `innerRadius` to `outerRadius`; pass 0 for a full disc.
    static func make(innerRadius: Float, outerRadius: Float, segments: Int = 128) -> MeshResource {
        precondition(outerRadius > innerRadius && innerRadius >= 0 && segments >= 3)
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let up = SIMD3<Float>(0, 1, 0)
        for step in 0...segments {
            let angle = Float(step) / Float(segments) * 2 * .pi
            let direction = SIMD3<Float>(cos(angle), 0, sin(angle))
            positions.append(direction * innerRadius)
            positions.append(direction * outerRadius)
            normals.append(up)
            normals.append(up)
        }
        for step in 0..<segments {
            let base = UInt32(step * 2)
            // Wound counterclockwise seen from +Y so the ring faces up.
            indices.append(contentsOf: [base, base + 2, base + 1, base + 1, base + 2, base + 3])
        }

        var descriptor = MeshDescriptor(name: "tourRing")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            fatalError("Failed to generate ring mesh: \(error)")
        }
    }
}
