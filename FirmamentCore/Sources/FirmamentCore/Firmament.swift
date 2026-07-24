import Foundation

/// Where a lattice node appears in the observer's local sky.
public struct SkyPosition: Sendable {
    public let node: LatticeNode
    /// Radians clockwise from true north, in [0, 2π).
    public let azimuthRadians: Double
    /// Radians above the local horizon plane; negative means below.
    public let elevationRadians: Double
    public let distanceKm: Double
    /// The node's heliocentric position, km. Carried here because tube-layout
    /// positions cannot be recovered from the index triple alone.
    public let heliocentricKm: Vector3

    public var isAboveHorizon: Bool { elevationRadians >= 0 }
}

/// The direction and distance to an arbitrary heliocentric point from the observer.
public struct SkyDirection: Sendable {
    public let azimuthRadians: Double
    public let elevationRadians: Double
    public let distanceKm: Double
}

/// Facade over the astronomy core: observer state in, visible sky positions out.
public enum Firmament {
    public static func skyPosition(
        of node: LatticeNode,
        observer: ObserverState,
        unitSpacingKm: Double
    ) -> SkyPosition {
        skyPosition(of: node, atHeliocentricKm: node.positionKm(unitSpacingKm: unitSpacingKm), observer: observer)
    }

    static func skyPosition(
        of node: LatticeNode,
        atHeliocentricKm point: Vector3,
        observer: ObserverState
    ) -> SkyPosition {
        let direction = skyDirection(toHeliocentricKm: point, observer: observer)
        return SkyPosition(
            node: node,
            azimuthRadians: direction.azimuthRadians,
            elevationRadians: direction.elevationRadians,
            distanceKm: direction.distanceKm,
            heliocentricKm: point
        )
    }

    /// Azimuth/elevation/distance of an arbitrary heliocentric point (ecliptic-of-date frame).
    public static func skyDirection(
        toHeliocentricKm point: Vector3,
        observer: ObserverState
    ) -> SkyDirection {
        let offsetEcliptic = point - observer.heliocentricPositionKm
        let offsetEcef = Frames.ecefFromEcliptic(
            offsetEcliptic,
            gmstRadians: observer.gmstRadians,
            obliquityRadians: observer.obliquityRadians
        )
        let enu = Frames.enuComponents(
            ofEcef: offsetEcef,
            latitudeRadians: observer.latitudeRadians,
            longitudeRadians: observer.longitudeRadians
        )
        let azimuth = Astronomy.normalizedRadians(atan2(enu.x, enu.y))
        let elevation = atan2(enu.z, (enu.x * enu.x + enu.y * enu.y).squareRoot())
        return SkyDirection(azimuthRadians: azimuth, elevationRadians: elevation, distanceKm: offsetEcliptic.length)
    }

    /// All lattice nodes near the observer whose elevation is at least `minElevationRadians`,
    /// sorted nearest first. Pass a negative minimum elevation to include ghost-band nodes
    /// just below the horizon. The candidate volume is a cylinder in the ecliptic plane
    /// (see `Lattice.candidateNodes`).
    public static func visibleNodes(
        observer: ObserverState,
        unitSpacingKm: Double,
        inPlaneRadiusKm: Double,
        outOfPlaneHalfExtentKm: Double,
        includeEclipticPlaneNodes: Bool = false,
        minElevationRadians: Double = 0,
        maxNodes: Int = 10_000
    ) -> [SkyPosition] {
        var candidates = Lattice.candidateNodes(
            aroundHeliocentricKm: observer.heliocentricPositionKm,
            unitSpacingKm: unitSpacingKm,
            inPlaneRadiusKm: inPlaneRadiusKm,
            outOfPlaneHalfExtentKm: outOfPlaneHalfExtentKm,
            maxNodes: maxNodes
        )
        if includeEclipticPlaneNodes {
            let planeNodes = Lattice.candidatePlaneNodes(
                aroundHeliocentricKm: observer.heliocentricPositionKm,
                unitSpacingKm: unitSpacingKm,
                inPlaneRadiusKm: inPlaneRadiusKm,
                maxNodes: max(maxNodes / 4, 100)
            )
            candidates = Array(Set(candidates).union(planeNodes))
        }
        return candidates
            .map { skyPosition(of: $0, observer: observer, unitSpacingKm: unitSpacingKm) }
            .filter { $0.elevationRadians >= minElevationRadians }
            .sorted { $0.distanceKm < $1.distanceKm }
    }

    /// All orbit-tube nodes in a fixed ring window around Earth's current orbital
    /// station whose elevation is at least `minElevationRadians`, sorted nearest
    /// first. With `axisThroughObserver` the tube is threaded through the
    /// observer's position, so the wall is `tubeRadiusKm` away in every direction
    /// around the direction of travel; otherwise the axis is Earth's orbital path
    /// itself (see `OrbitTube`).
    public static func visibleTubeNodes(
        observer: ObserverState,
        unitSpacingKm: Double,
        tubeRadiusKm: Double,
        nodesPerRing: Int,
        halfSpanRings: Int,
        axisThroughObserver: Bool = false,
        minElevationRadians: Double = 0
    ) -> [SkyPosition] {
        let julianDay = Astronomy.julianDay(observer.date)
        let observerOffset = observer.heliocentricPositionKm
            - Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        // The ring window centers on the observer's own along-track position:
        // an observer on the planet's leading face rides thousands of km ahead
        // of Earth's center and would otherwise sit past the window's front
        // edge. When the axis threads the observer, the rigid offset already
        // recenters the rings, so no extra shift is needed.
        return OrbitTube.candidateNodes(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            tubeRadiusKm: tubeRadiusKm,
            nodesPerRing: nodesPerRing,
            halfSpanRings: halfSpanRings,
            axisOffsetKm: axisThroughObserver ? observerOffset : .zero,
            alongTrackOffsetKm: axisThroughObserver
                ? 0
                : OrbitTube.alongTrackOffsetKm(julianDay: julianDay, offsetFromEarthCenterKm: observerOffset)
        )
        .map { skyPosition(of: $0.node, atHeliocentricKm: $0.positionKm, observer: observer) }
        .filter { $0.elevationRadians >= minElevationRadians }
        .sorted { $0.distanceKm < $1.distanceKm }
    }

    /// Node rings on the nearest far-ring stations beyond the node window (see
    /// `OrbitTube.farNodeStations`), so tube mode always has nodes in view even
    /// when tight spacing keeps the whole node window below the horizon.
    public static func visibleFarTubeNodes(
        observer: ObserverState,
        unitSpacingKm: Double,
        tubeRadiusKm: Double,
        nodesPerRing: Int,
        halfSpanRings: Int,
        minElevationRadians: Double = 0
    ) -> [SkyPosition] {
        let julianDay = Astronomy.julianDay(observer.date)
        let observerOffset = observer.heliocentricPositionKm
            - Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        let stations = OrbitTube.farNodeStations(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            halfSpanRings: halfSpanRings,
            alongTrackOffsetKm: OrbitTube.alongTrackOffsetKm(
                julianDay: julianDay,
                offsetFromEarthCenterKm: observerOffset
            )
        )
        return OrbitTube.nodes(
            forStations: stations,
            unitSpacingKm: unitSpacingKm,
            tubeRadiusKm: tubeRadiusKm,
            nodesPerRing: nodesPerRing
        )
        .map { skyPosition(of: $0.node, atHeliocentricKm: $0.positionKm, observer: observer) }
        .filter { $0.elevationRadians >= minElevationRadians }
    }
}
