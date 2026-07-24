import Foundation

/// A lattice node identified by its integer index triple.
/// Its position is always `(i, j, k) × unitSpacing` — never stored.
public struct LatticeNode: Hashable, Sendable {
    public let i: Int
    public let j: Int
    public let k: Int

    public init(i: Int, j: Int, k: Int) {
        self.i = i
        self.j = j
        self.k = k
    }

    public func positionKm(unitSpacingKm: Double) -> Vector3 {
        Vector3(x: Double(i) * unitSpacingKm, y: Double(j) * unitSpacingKm, z: Double(k) * unitSpacingKm)
    }
}

public enum Lattice {
    /// All lattice nodes within an anisotropic bubble around a heliocentric point:
    /// a cylinder of `inPlaneRadiusKm` in the ecliptic (x-y) plane, cut to
    /// `outOfPlaneHalfExtentKm` above and below it. Earth's orbital motion lies in
    /// the x-y plane, so this keeps reach where the sweep happens and trims the
    /// far poles that barely change. Capped at roughly `maxNodes` by shrinking both
    /// reaches proportionally, preserving the volume's aspect ratio.
    public static func candidateNodes(
        aroundHeliocentricKm center: Vector3,
        unitSpacingKm: Double,
        inPlaneRadiusKm: Double,
        outOfPlaneHalfExtentKm: Double,
        maxNodes: Int = 10_000
    ) -> [LatticeNode] {
        guard unitSpacingKm > 0, inPlaneRadiusKm > 0, outOfPlaneHalfExtentKm > 0, maxNodes > 0 else {
            return []
        }

        var radius = inPlaneRadiusKm
        var halfExtent = outOfPlaneHalfExtentKm
        for _ in 0..<4 {
            let estimatedCount = .pi * pow(radius / unitSpacingKm, 2)
                * (2 * halfExtent / unitSpacingKm + 1)
            guard estimatedCount > Double(maxNodes) else { break }
            let shrink = cbrt(Double(maxNodes) / estimatedCount)
            radius *= shrink
            halfExtent *= shrink
        }
        // Never shrink below the nearest lattice plane/column, or the set goes empty.
        radius = max(radius, unitSpacingKm)
        halfExtent = max(halfExtent, unitSpacingKm / 2)

        let centerI = Int((center.x / unitSpacingKm).rounded())
        let centerJ = Int((center.y / unitSpacingKm).rounded())
        let centerK = Int((center.z / unitSpacingKm).rounded())
        let reachXY = Int((radius / unitSpacingKm).rounded(.up))
        let reachZ = Int((halfExtent / unitSpacingKm).rounded(.up))

        var nodes: [LatticeNode] = []
        for i in (centerI - reachXY)...(centerI + reachXY) {
            for j in (centerJ - reachXY)...(centerJ + reachXY) {
                let inPlaneX = Double(i) * unitSpacingKm - center.x
                let inPlaneY = Double(j) * unitSpacingKm - center.y
                guard (inPlaneX * inPlaneX + inPlaneY * inPlaneY).squareRoot() <= radius else { continue }
                for k in (centerK - reachZ)...(centerK + reachZ) {
                    let outOfPlane = Double(k) * unitSpacingKm - center.z
                    if abs(outOfPlane) <= halfExtent {
                        nodes.append(LatticeNode(i: i, j: j, k: k))
                    }
                }
            }
        }
        return nodes
    }

    /// Nodes lying exactly on the ecliptic plane (k = 0) within an in-plane radius of
    /// the center. Used to keep the plane visible even when the main bubble's
    /// out-of-plane extent doesn't reach it — the plane can sit up to an Earth radius
    /// above or below the observer.
    public static func candidatePlaneNodes(
        aroundHeliocentricKm center: Vector3,
        unitSpacingKm: Double,
        inPlaneRadiusKm: Double,
        maxNodes: Int = 600
    ) -> [LatticeNode] {
        guard unitSpacingKm > 0, inPlaneRadiusKm > 0, maxNodes > 0 else { return [] }

        var radius = inPlaneRadiusKm
        let estimatedCount = .pi * pow(radius / unitSpacingKm, 2)
        if estimatedCount > Double(maxNodes) {
            radius = unitSpacingKm * (Double(maxNodes) / .pi).squareRoot()
        }
        radius = max(radius, unitSpacingKm)

        let centerI = Int((center.x / unitSpacingKm).rounded())
        let centerJ = Int((center.y / unitSpacingKm).rounded())
        let reach = Int((radius / unitSpacingKm).rounded(.up))

        var nodes: [LatticeNode] = []
        for i in (centerI - reach)...(centerI + reach) {
            for j in (centerJ - reach)...(centerJ + reach) {
                let inPlaneX = Double(i) * unitSpacingKm - center.x
                let inPlaneY = Double(j) * unitSpacingKm - center.y
                if (inPlaneX * inPlaneX + inPlaneY * inPlaneY).squareRoot() <= radius {
                    nodes.append(LatticeNode(i: i, j: j, k: 0))
                }
            }
        }
        return nodes
    }
}
