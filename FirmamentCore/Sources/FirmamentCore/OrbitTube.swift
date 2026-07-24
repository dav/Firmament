import Foundation

/// A node on the orbit tube: its stable lattice identity plus its fixed
/// heliocentric position (tube positions are not derivable from the index
/// triple the way grid positions are).
public struct TubeNode: Sendable {
    public let node: LatticeNode
    public let positionKm: Vector3
}

/// The "orbit tube" layout: rings of nodes on the surface of an imaginary tube
/// that follows Earth's orbital path around the Sun. Rings are anchored at fixed
/// stations along the orbit — the orbit position at fixed time steps from J2000 —
/// so the tube never moves; Earth travels through it, passing one ring per
/// spacing unit of orbital arc.
public enum OrbitTube {
    /// Mean orbital speed, used to convert ring spacing (km of arc) into a time
    /// step along the orbit. True spacing varies ±1.7% with actual orbital speed.
    public static let meanOrbitalSpeedKmPerDay = 2 * Double.pi * Astronomy.astronomicalUnitKm / 365.256_363

    private static let epochJulianDay = 2_451_545.0

    /// Stable node identity: `i` is the ring station index, `j` the position
    /// around the ring, and `k` reuses the grid's plane convention — 0 for the
    /// two nodes on the tube's horizontal midline (level with the axis, parallel
    /// to the ecliptic plane), 1 for all others.
    public static func nodeKey(ring: Int, index: Int, nodesPerRing: Int) -> LatticeNode {
        let isOnPlane = index == 0 || index == nodesPerRing / 2
        return LatticeNode(i: ring, j: index, k: isOnPlane ? 0 : 1)
    }

    /// Forces the ring node count even (so two nodes straddle the ecliptic plane)
    /// with a floor of 4.
    public static func sanitizedNodesPerRing(_ nodesPerRing: Int) -> Int {
        max(nodesPerRing - nodesPerRing % 2, 4)
    }

    /// The ring station nearest a traveler along the orbit. Pass the observer's
    /// along-track offset so the station tracks the observer rather than Earth's
    /// center — an observer on the leading face of the planet rides thousands of
    /// kilometers ahead of the center.
    public static func currentStation(
        julianDay: Double,
        unitSpacingKm: Double,
        alongTrackOffsetKm: Double = 0
    ) -> Int {
        guard unitSpacingKm > 0 else { return 0 }
        let spacingDays = unitSpacingKm / meanOrbitalSpeedKmPerDay
        return Int(((julianDay - epochJulianDay) / spacingDays + alongTrackOffsetKm / unitSpacingKm).rounded())
    }

    /// The along-orbit component of an offset from Earth's center, km.
    public static func alongTrackOffsetKm(julianDay: Double, offsetFromEarthCenterKm: Vector3) -> Double {
        let ahead = Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay + 0.01)
        let behind = Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay - 0.01)
        return offsetFromEarthCenterKm.dot((ahead - behind).normalized)
    }

    /// All tube nodes in a fixed window of `halfSpanRings` rings ahead of and
    /// behind Earth's current station. Ring count never depends on the ring node
    /// count, so the visible tube length is set by ring spacing alone.
    ///
    /// `axisOffsetKm` translates the whole tube rigidly — pass the observer's
    /// offset from Earth's center to thread the tunnel through the observer, so
    /// a small tube radius stays overhead anywhere on the globe instead of only
    /// along the one great circle nearest the orbit path.
    public static func candidateNodes(
        julianDay: Double,
        unitSpacingKm: Double,
        tubeRadiusKm: Double,
        nodesPerRing: Int,
        halfSpanRings: Int,
        axisOffsetKm: Vector3 = .zero,
        alongTrackOffsetKm: Double = 0
    ) -> [TubeNode] {
        guard unitSpacingKm > 0, tubeRadiusKm > 0, halfSpanRings >= 0 else { return [] }
        let perRing = sanitizedNodesPerRing(nodesPerRing)

        let spacingDays = unitSpacingKm / meanOrbitalSpeedKmPerDay
        let currentRing = currentStation(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            alongTrackOffsetKm: alongTrackOffsetKm
        )

        var nodes: [TubeNode] = []
        nodes.reserveCapacity((2 * halfSpanRings + 1) * perRing)
        for ring in (currentRing - halfSpanRings)...(currentRing + halfSpanRings) {
            let stationDay = epochJulianDay + Double(ring) * spacingDays
            let circle = ringCircle(
                stationDay: stationDay,
                tubeRadiusKm: tubeRadiusKm,
                points: perRing,
                axisOffsetKm: axisOffsetKm
            )
            for (index, position) in circle.enumerated() {
                nodes.append(TubeNode(
                    node: nodeKey(ring: ring, index: index, nodesPerRing: perRing),
                    positionKm: position
                ))
            }
        }
        return nodes
    }

    /// A distant tube ring: its absolute station index and outline points.
    public struct FarRing: Sendable {
        public let stationIndex: Int
        public let pointsKm: [Vector3]
    }

    // swiftlint:disable function_parameter_count
    /// Outline rings continuing the tube beyond the node window, so the bore is
    /// visible from anywhere on the globe even when the node window is short.
    /// Stations snap to multiples of twice the window half-span: the set stays
    /// put while Earth travels through it, and a ring entering the node window
    /// keeps its station index, so its nodes hand off seamlessly. Returns
    /// nothing when the node window already reaches `farHalfLengthKm`.
    public static func farRings(
        julianDay: Double,
        unitSpacingKm: Double,
        tubeRadiusKm: Double,
        pointsPerRing: Int,
        halfSpanRings: Int,
        farHalfLengthKm: Double,
        axisOffsetKm: Vector3 = .zero,
        alongTrackOffsetKm: Double = 0
    ) -> [FarRing] {
        // swiftlint:enable function_parameter_count
        let stride = halfSpanRings * 2
        let stations = farStations(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            halfSpanRings: halfSpanRings,
            maxOffsetRings: unitSpacingKm > 0 ? Int(farHalfLengthKm / unitSpacingKm) : 0,
            alongTrackOffsetKm: alongTrackOffsetKm
        )
        guard !stations.isEmpty, tubeRadiusKm > 0, stride > 0 else { return [] }

        let points = max(pointsPerRing, 8)
        let spacingDays = unitSpacingKm / meanOrbitalSpeedKmPerDay
        return stations.map { station in
            FarRing(
                stationIndex: station,
                pointsKm: ringCircle(
                    stationDay: epochJulianDay + Double(station) * spacingDays,
                    tubeRadiusKm: tubeRadiusKm,
                    points: points,
                    axisOffsetKm: axisOffsetKm
                )
            )
        }
    }

    /// The nearest far-ring stations that also carry cube nodes: up to
    /// `maxStrides` stride-multiples out on each side of the node window.
    public static func farNodeStations(
        julianDay: Double,
        unitSpacingKm: Double,
        halfSpanRings: Int,
        alongTrackOffsetKm: Double = 0,
        maxStrides: Int = 3
    ) -> [Int] {
        farStations(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            halfSpanRings: halfSpanRings,
            maxOffsetRings: halfSpanRings * 2 * maxStrides,
            alongTrackOffsetKm: alongTrackOffsetKm
        )
    }

    /// Full node rings for specific stations, with the same identities the node
    /// window would assign — an approaching far ring keeps its entities as it
    /// enters the window.
    public static func nodes(
        forStations stations: [Int],
        unitSpacingKm: Double,
        tubeRadiusKm: Double,
        nodesPerRing: Int,
        axisOffsetKm: Vector3 = .zero
    ) -> [TubeNode] {
        guard unitSpacingKm > 0, tubeRadiusKm > 0 else { return [] }
        let perRing = sanitizedNodesPerRing(nodesPerRing)
        let spacingDays = unitSpacingKm / meanOrbitalSpeedKmPerDay

        var nodes: [TubeNode] = []
        nodes.reserveCapacity(stations.count * perRing)
        for station in stations {
            let circle = ringCircle(
                stationDay: epochJulianDay + Double(station) * spacingDays,
                tubeRadiusKm: tubeRadiusKm,
                points: perRing,
                axisOffsetKm: axisOffsetKm
            )
            for (index, position) in circle.enumerated() {
                nodes.append(TubeNode(
                    node: nodeKey(ring: station, index: index, nodesPerRing: perRing),
                    positionKm: position
                ))
            }
        }
        return nodes
    }

    /// Stations at stride multiples outside the node window but within
    /// `maxOffsetRings` of the current station, capped at 64.
    private static func farStations(
        julianDay: Double,
        unitSpacingKm: Double,
        halfSpanRings: Int,
        maxOffsetRings: Int,
        alongTrackOffsetKm: Double = 0
    ) -> [Int] {
        guard unitSpacingKm > 0, halfSpanRings >= 1 else { return [] }
        let stride = halfSpanRings * 2
        guard stride <= maxOffsetRings else { return [] }

        let currentRing = currentStation(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            alongTrackOffsetKm: alongTrackOffsetKm
        )

        var stations: [Int] = []
        var station = ((currentRing - maxOffsetRings) / stride) * stride
        while station <= currentRing + maxOffsetRings && stations.count < 64 {
            if abs(station - currentRing) > halfSpanRings && abs(station - currentRing) <= maxOffsetRings {
                stations.append(station)
            }
            station += stride
        }
        return stations
    }

    /// The evenly spaced points of one ring, ordered so index 0 is the outward
    /// in-plane point — indices 0 and count/2 sit level with the axis.
    private static func ringCircle(
        stationDay: Double,
        tubeRadiusKm: Double,
        points: Int,
        axisOffsetKm: Vector3
    ) -> [Vector3] {
        let center = Astronomy.earthHeliocentricEclipticKm(julianDay: stationDay) + axisOffsetKm
        // Central difference over ±0.01 d gives the along-orbit tangent; the
        // low-precision orbit lies in the ecliptic plane, so so does the tangent.
        let ahead = Astronomy.earthHeliocentricEclipticKm(julianDay: stationDay + 0.01)
        let behind = Astronomy.earthHeliocentricEclipticKm(julianDay: stationDay - 0.01)
        let tangent = (ahead - behind).normalized
        // Ring basis: in-plane normal to the tangent, and the ecliptic pole.
        let outward = Vector3(x: -tangent.y, y: tangent.x, z: 0).normalized
        return (0..<points).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(points)
            return center + outward * (cos(angle) * tubeRadiusKm)
                + Vector3(x: 0, y: 0, z: sin(angle) * tubeRadiusKm)
        }
    }
}
