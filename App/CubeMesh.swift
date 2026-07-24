import RealityKit

/// Builds the shared unit-cube mesh with one material slot per face, in the
/// `CubeFace` order, so each face can carry its own configurable color.
enum CubeMesh {
    static func make() -> MeshResource {
        let half: Float = 0.5
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        var faceMaterialIndices: [UInt32] = []

        // Basis chosen so uAxis × vAxis = normal (outward-facing winding), in CubeFace order:
        // east +X, west −X, up +Y, down −Y, south +Z, north −Z.
        let faces: [FaceBasis] = [
            FaceBasis(normal: SIMD3(1, 0, 0), uAxis: SIMD3(0, 1, 0), vAxis: SIMD3(0, 0, 1)),
            FaceBasis(normal: SIMD3(-1, 0, 0), uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(0, 1, 0)),
            FaceBasis(normal: SIMD3(0, 1, 0), uAxis: SIMD3(0, 0, 1), vAxis: SIMD3(1, 0, 0)),
            FaceBasis(normal: SIMD3(0, -1, 0), uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 0, 1)),
            FaceBasis(normal: SIMD3(0, 0, 1), uAxis: SIMD3(1, 0, 0), vAxis: SIMD3(0, 1, 0)),
            FaceBasis(normal: SIMD3(0, 0, -1), uAxis: SIMD3(0, 1, 0), vAxis: SIMD3(1, 0, 0))
        ]

        for (materialIndex, face) in faces.enumerated() {
            let (normal, uAxis, vAxis) = (face.normal, face.uAxis, face.vAxis)
            let center = normal * half
            let base = UInt32(positions.count)
            positions.append(center - uAxis * half - vAxis * half)
            positions.append(center + uAxis * half - vAxis * half)
            positions.append(center + uAxis * half + vAxis * half)
            positions.append(center - uAxis * half + vAxis * half)
            normals.append(contentsOf: [normal, normal, normal, normal])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
            faceMaterialIndices.append(contentsOf: [UInt32(materialIndex), UInt32(materialIndex)])
        }

        var descriptor = MeshDescriptor(name: "latticeCube")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(faceMaterialIndices)

        do {
            return try MeshResource.generate(from: [descriptor])
        } catch {
            fatalError("Failed to generate lattice cube mesh: \(error)")
        }
    }

    private struct FaceBasis {
        let normal: SIMD3<Float>
        let uAxis: SIMD3<Float>
        let vAxis: SIMD3<Float>
    }
}
