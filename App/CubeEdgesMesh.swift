import RealityKit

/// The 12 edges of a unit cube as thin boxes, merged into one mesh. Added as a
/// child of a node cube, it renders as an outline that scales with its parent.
enum CubeEdgesMesh {
    static func make(thickness: Float = 0.07) -> MeshResource {
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        let half: Float = 0.5
        let halfT = thickness / 2
        for axis in 0..<3 {
            let crossA = (axis + 1) % 3
            let crossB = (axis + 2) % 3
            for signA in [-half, half] {
                for signB in [-half, half] {
                    var minCorner = SIMD3<Float>(repeating: 0)
                    var maxCorner = SIMD3<Float>(repeating: 0)
                    minCorner[axis] = -half - halfT
                    maxCorner[axis] = half + halfT
                    minCorner[crossA] = signA - halfT
                    maxCorner[crossA] = signA + halfT
                    minCorner[crossB] = signB - halfT
                    maxCorner[crossB] = signB + halfT
                    appendBox(
                        min: minCorner,
                        max: maxCorner,
                        positions: &positions,
                        normals: &normals,
                        indices: &indices
                    )
                }
            }
        }

        var descriptor = MeshDescriptor(name: "cubeEdges")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            fatalError("Failed to generate cube edge mesh: \(error)")
        }
    }

    private static func appendBox(
        min minCorner: SIMD3<Float>,
        max maxCorner: SIMD3<Float>,
        positions: inout [SIMD3<Float>],
        normals: inout [SIMD3<Float>],
        indices: inout [UInt32]
    ) {
        let base = UInt32(positions.count)
        let corners = [
            SIMD3(minCorner.x, minCorner.y, minCorner.z),
            SIMD3(maxCorner.x, minCorner.y, minCorner.z),
            SIMD3(maxCorner.x, maxCorner.y, minCorner.z),
            SIMD3(minCorner.x, maxCorner.y, minCorner.z),
            SIMD3(minCorner.x, minCorner.y, maxCorner.z),
            SIMD3(maxCorner.x, minCorner.y, maxCorner.z),
            SIMD3(maxCorner.x, maxCorner.y, maxCorner.z),
            SIMD3(minCorner.x, maxCorner.y, maxCorner.z)
        ]
        positions.append(contentsOf: corners)
        let center = (minCorner + maxCorner) / 2
        normals.append(contentsOf: corners.map { simd_normalize($0 - center) })

        let faces: [[UInt32]] = [
            [0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
            [2, 3, 7, 6], [1, 2, 6, 5], [0, 4, 7, 3]
        ]
        for face in faces {
            indices.append(contentsOf: [
                base + face[0], base + face[1], base + face[2],
                base + face[0], base + face[2], base + face[3]
            ])
        }
    }
}
