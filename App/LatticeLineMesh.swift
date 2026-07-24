import RealityKit
import simd

nonisolated struct LineSegment: Sendable {
    let start: SIMD3<Float>
    let end: SIMD3<Float>
}

/// The CPU-built geometry for a grid-line mesh: `Sendable` so it can be produced
/// off the main actor and handed to `MeshResource.generate` on it. Building these
/// arrays is the expensive part; the GPU upload in `resource(from:)` is cheap.
nonisolated struct LineMeshData: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let indices: [UInt32]
}

/// Merges all lattice grid lines into a single mesh (one draw call): each segment
/// becomes a thin four-sided prism whose thickness tracks its dome radius, so all
/// lines have a similar apparent width.
enum LatticeLineMesh {
    private nonisolated static let thicknessFraction: Float = 0.004

    /// Off-main: builds the merged prism geometry for all segments.
    nonisolated static func buildData(segments: [LineSegment]) -> LineMeshData? {
        guard !segments.isEmpty else { return nil }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(segments.count * 8)
        normals.reserveCapacity(segments.count * 8)
        indices.reserveCapacity(segments.count * 24)

        for segment in segments {
            let axis = segment.end - segment.start
            let length = simd_length(axis)
            guard length > 0.001 else { continue }
            let direction = axis / length

            let reference: SIMD3<Float> = abs(direction.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            let uAxis = simd_normalize(simd_cross(direction, reference))
            let vAxis = simd_cross(direction, uAxis)

            let meanRadius = (simd_length(segment.start) + simd_length(segment.end)) / 2
            let halfThickness = max(meanRadius * thicknessFraction, 0.02) / 2
            let uOffset = uAxis * halfThickness
            let vOffset = vAxis * halfThickness

            let base = UInt32(positions.count)
            for anchor in [segment.start, segment.end] {
                positions.append(anchor - uOffset - vOffset)
                positions.append(anchor + uOffset - vOffset)
                positions.append(anchor + uOffset + vOffset)
                positions.append(anchor - uOffset + vOffset)
                normals.append(contentsOf: [
                    simd_normalize(-uAxis - vAxis),
                    simd_normalize(uAxis - vAxis),
                    simd_normalize(uAxis + vAxis),
                    simd_normalize(-uAxis + vAxis)
                ])
            }

            // Four side quads of the prism; end caps are invisibly small.
            let quadCorners: [[UInt32]] = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
            for quad in quadCorners {
                indices.append(contentsOf: [
                    base + quad[0], base + quad[1], base + quad[2],
                    base + quad[0], base + quad[2], base + quad[3]
                ])
            }
        }

        guard !positions.isEmpty else { return nil }
        return LineMeshData(positions: positions, normals: normals, indices: indices)
    }

    /// Uploads prebuilt geometry to a `MeshResource` (cheap GPU work).
    static func resource(from data: LineMeshData) -> MeshResource? {
        var descriptor = MeshDescriptor(name: "latticeLines")
        descriptor.positions = MeshBuffers.Positions(data.positions)
        descriptor.normals = MeshBuffers.Normals(data.normals)
        descriptor.primitives = .triangles(data.indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
