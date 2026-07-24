import FirmamentCore
import RealityKit

/// The pure, off-main frame computation for `SkyRenderer`. Everything here is
/// `nonisolated static` and free of RealityKit/renderer state, so it can run in a
/// detached task without stalling the render loop.
extension SkyRenderer {
    /// Computes the entire next frame from observer state and configuration.
    nonisolated static func computeFrame(
        observer: ObserverState,
        futureObserver: ObserverState,
        configuration: RenderConfiguration
    ) -> SkyFrame {
        // X-ray mode drops the horizon cutoff entirely; below-horizon nodes
        // already render ghost-style, which reads as "behind the planet".
        let minElevation: Double
        if configuration.showBelowHorizon {
            minElevation = -Double.pi
        } else if configuration.showGhostNodes {
            minElevation = -configuration.ghostBandDegrees * .pi / 180
        } else {
            minElevation = 0
        }
        let current = visible(for: observer, configuration: configuration, minElevation: minElevation)
        let future = visible(for: futureObserver, configuration: configuration, minElevation: minElevation)
        let futureByNode = Dictionary(uniqueKeysWithValues: future.map { ($0.node, $0) })

        let minDistance = current.first?.distanceKm ?? 0
        let maxDistance = current.last?.distanceKm ?? 0

        let placements = buildPlacements(
            current: current,
            futureByNode: futureByNode,
            observer: observer,
            configuration: configuration
        )
        let standardLineData = lineData(
            observer: observer,
            configuration: configuration,
            minElevation: minElevation,
            range: DistanceRange(minKm: minDistance, spanKm: maxDistance - minDistance)
        )

        let orientation = latticeOrientation(for: observer)

        let sun = Firmament.skyDirection(toHeliocentricKm: .zero, observer: observer)
        let sunPosition = domeDirection(
            azimuthRadians: sun.azimuthRadians,
            elevationRadians: sun.elevationRadians
        ) * Float(maxDomeRadiusMeters)
        let sunScale = Float(maxDomeRadiusMeters * (2 * sunRadiusKm / sun.distanceKm) * sunSizeBoost)

        let stats = stats(for: current, observer: observer, configuration: configuration, sun: sun)

        return SkyFrame(
            placements: placements,
            standardLineData: standardLineData,
            latticeOrientation: orientation,
            sunPosition: sunPosition,
            sunScale: sunScale,
            stats: stats
        )
    }

    private nonisolated static func buildPlacements(
        current: [SkyPosition],
        futureByNode: [LatticeNode: SkyPosition],
        observer: ObserverState,
        configuration: RenderConfiguration
    ) -> [NodePlacement] {
        // current is sorted nearest first, so the span is first...last.
        let minDistance = current.first?.distanceKm ?? 0
        let maxDistance = current.last?.distanceKm ?? 0
        let range = DistanceRange(minKm: minDistance, spanKm: maxDistance - minDistance)
        let effectiveEdgeKm = scaleInfo(for: configuration).cubeEdgeKm
        let sunwardDirection = -observer.heliocentricPositionKm.normalized
        let reachKm = max(range.minKm + range.spanKm, 1)

        var placements: [NodePlacement] = []
        placements.reserveCapacity(current.count)
        for position in current {
            let (nowPosition, nowScale) = domePositionScale(position, range: range, cubeEdgeKm: effectiveEdgeKm)
            let target = futureByNode[position.node] ?? position
            let (targetPosition, targetScale) = domePositionScale(target, range: range, cubeEdgeKm: effectiveEdgeKm)
            let style = style(
                for: position,
                observer: observer,
                sunwardDirection: sunwardDirection,
                reachKm: reachKm
            )
            placements.append(NodePlacement(
                node: position.node,
                nowPosition: nowPosition,
                nowScale: nowScale,
                targetPosition: targetPosition,
                targetScale: targetScale,
                style: style
            ))
        }
        return placements
    }

    private nonisolated static func stats(
        for current: [SkyPosition],
        observer: ObserverState,
        configuration: RenderConfiguration,
        sun: SkyDirection
    ) -> RenderStats {
        var nearWindowVisible = true
        if configuration.renderMode == .tube {
            let station = observerStation(observer: observer, unitSpacingKm: configuration.unitSpacingKm)
            nearWindowVisible = current.contains {
                abs($0.node.i - station) <= tubeRingHalfSpan && $0.isAboveHorizon
            }
        }

        return RenderStats(
            aboveHorizonCount: current.count { $0.isAboveHorizon },
            placedCount: current.count,
            nearestKm: current.first?.distanceKm ?? 0,
            farthestKm: current.last?.distanceKm ?? 0,
            sunAzimuthDegrees: sun.azimuthRadians * 180 / .pi,
            sunElevationDegrees: sun.elevationRadians * 180 / .pi,
            sunAboveHorizon: sun.elevationRadians >= 0,
            // Tube mode's ring window is fixed, never budget-capped.
            didCapNodes: configuration.renderMode == .grid && current.count >= maxRenderedNodes,
            isNearRingWindowVisible: nearWindowVisible
        )
    }

    /// The true scale of the current configuration, shared by the placement math
    /// and the on-screen HUD so the displayed numbers are exactly what renders.
    /// Tube and ride use their own cube-edge setting (their walls sit much
    /// farther/closer than grid nodes); the anti-touch cap honors the nearer of
    /// the ring gap and the around-ring chord. No hidden scaling — cube size
    /// must stay a truthful reference against the ring spacing.
    nonisolated static func scaleInfo(for configuration: RenderConfiguration) -> ScaleInfo {
        var edgeKm = configuration.cubeEdgeKm
        var betweenCubesKm = configuration.unitSpacingKm
        var neighborGapKm = configuration.unitSpacingKm
        var farRingGapKm: Double?
        if configuration.renderMode != .grid {
            edgeKm = configuration.tubeCubeEdgeKm
            let chordKm = 2 * configuration.tubeRadiusKm
                * sin(.pi / Double(configuration.sanitizedNodesPerRing))
            betweenCubesKm = chordKm
            neighborGapKm = min(neighborGapKm, chordKm)
        }
        if configuration.renderMode == .tube {
            let gapKm = Double(tubeRingHalfSpan * 2) * configuration.unitSpacingKm
            farRingGapKm = gapKm <= farTubeHalfLengthKm ? gapKm : nil
        }
        return ScaleInfo(
            cubeEdgeKm: min(edgeKm, maxEdgeFractionOfSpacing * neighborGapKm),
            betweenCubesKm: betweenCubesKm,
            betweenRingsKm: configuration.unitSpacingKm,
            farRingGapKm: farRingGapKm
        )
    }

    private nonisolated static func visible(
        for observer: ObserverState,
        configuration: RenderConfiguration,
        minElevation: Double
    ) -> [SkyPosition] {
        switch configuration.renderMode {
        case .grid:
            return Firmament.visibleNodes(
                observer: observer,
                unitSpacingKm: configuration.unitSpacingKm,
                inPlaneRadiusKm: configuration.inPlaneRadiusKm,
                outOfPlaneHalfExtentKm: configuration.outOfPlaneHalfExtentKm,
                minElevationRadians: minElevation,
                maxNodes: maxRenderedNodes
            )
        case .tube, .ride:
            var positions = Firmament.visibleTubeNodes(
                observer: observer,
                unitSpacingKm: configuration.unitSpacingKm,
                tubeRadiusKm: configuration.tubeRadiusKm,
                nodesPerRing: configuration.sanitizedNodesPerRing,
                halfSpanRings: tubeRingHalfSpan,
                axisThroughObserver: configuration.renderMode == .ride,
                minElevationRadians: minElevation
            )
            if configuration.renderMode == .tube {
                // Node rings on the nearest far stations, so the tube always has
                // nodes in view even when the node window hides below the horizon.
                positions += Firmament.visibleFarTubeNodes(
                    observer: observer,
                    unitSpacingKm: configuration.unitSpacingKm,
                    tubeRadiusKm: configuration.tubeRadiusKm,
                    nodesPerRing: configuration.sanitizedNodesPerRing,
                    halfSpanRings: tubeRingHalfSpan,
                    minElevationRadians: minElevation
                )
                positions.sort { $0.distanceKm < $1.distanceKm }
            }
            return positions
        }
    }

    /// Builds the merged line geometry off the main actor. Only tube mode
    /// draws lines now — the distant bore sketch, which is the tube itself,
    /// like the sun marker. (The user-toggleable lattice lines and the red
    /// ecliptic-plane grid were both retired: the three layouts plus the PiP
    /// orrery carry that explanatory job.)
    private nonisolated static func lineData(
        observer: ObserverState,
        configuration: RenderConfiguration,
        minElevation: Double,
        range: DistanceRange
    ) -> LineMeshData? {
        guard configuration.renderMode == .tube else { return nil }
        let segments = farTubeSegments(
            observer: observer,
            configuration: configuration,
            minElevation: minElevation,
            range: range
        )
        return LatticeLineMesh.buildData(segments: segments)
    }

    /// Outline hoops continuing the tube past the node window, mapped onto the
    /// dome at each point's own distance so they sit at consistent depth with
    /// the far node rings. Segments fully below the ghost cutoff are dropped;
    /// the rest sketch the bore receding fore and aft.
    private nonisolated static func farTubeSegments(
        observer: ObserverState,
        configuration: RenderConfiguration,
        minElevation: Double,
        range: DistanceRange
    ) -> [LineSegment] {
        let julianDay = Astronomy.julianDay(observer.date)
        let observerOffset = observer.heliocentricPositionKm
            - Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        let rings = OrbitTube.farRings(
            julianDay: julianDay,
            unitSpacingKm: configuration.unitSpacingKm,
            tubeRadiusKm: configuration.tubeRadiusKm,
            pointsPerRing: max(configuration.sanitizedNodesPerRing, 24),
            halfSpanRings: tubeRingHalfSpan,
            farHalfLengthKm: farTubeHalfLengthKm,
            alongTrackOffsetKm: OrbitTube.alongTrackOffsetKm(
                julianDay: julianDay,
                offsetFromEarthCenterKm: observerOffset
            )
        )
        var segments: [LineSegment] = []
        for ring in rings {
            let dome = ring.pointsKm.map { point -> (elevation: Double, position: SIMD3<Float>) in
                let direction = Firmament.skyDirection(toHeliocentricKm: point, observer: observer)
                let radius = domeRadius(forDistanceKm: direction.distanceKm, range: range)
                let position = domeDirection(
                    azimuthRadians: direction.azimuthRadians,
                    elevationRadians: direction.elevationRadians
                ) * Float(radius)
                return (direction.elevationRadians, position)
            }
            for index in 0..<dome.count {
                let start = dome[index]
                let end = dome[(index + 1) % dome.count]
                guard start.elevation >= minElevation || end.elevation >= minElevation else { continue }
                segments.append(LineSegment(start: start.position, end: end.position))
            }
        }
        return segments
    }

    /// The ring station nearest the observer (not Earth's center) along the orbit.
    private nonisolated static func observerStation(observer: ObserverState, unitSpacingKm: Double) -> Int {
        let julianDay = Astronomy.julianDay(observer.date)
        let observerOffset = observer.heliocentricPositionKm
            - Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        return OrbitTube.currentStation(
            julianDay: julianDay,
            unitSpacingKm: unitSpacingKm,
            alongTrackOffsetKm: OrbitTube.alongTrackOffsetKm(
                julianDay: julianDay,
                offsetFromEarthCenterKm: observerOffset
            )
        )
    }

    private nonisolated static func style(
        for position: SkyPosition,
        observer: ObserverState,
        sunwardDirection: Vector3,
        reachKm: Double
    ) -> NodeStyle {
        let sunward = (position.heliocentricKm - observer.heliocentricPositionKm).dot(sunwardDirection)
        let normalized = (sunward / reachKm + 1) / 2
        let level = min(
            max(Int(normalized * Double(brightnessLevels)), 0),
            brightnessLevels - 1
        )
        let isOnPlane = position.node.k == 0
        return NodeStyle(
            isGhost: !position.isAboveHorizon,
            isOnEclipticPlane: isOnPlane,
            brightnessLevel: isOnPlane ? brightnessLevels - 1 : level
        )
    }

    /// Dome-space position and cube scale. Scaling by true angular size at each
    /// node's own dome radius preserves both depth ordering and apparent size.
    private nonisolated static func domePositionScale(
        _ position: SkyPosition,
        range: DistanceRange,
        cubeEdgeKm: Double
    ) -> (position: SIMD3<Float>, scale: Float) {
        let radius = domeRadius(forDistanceKm: position.distanceKm, range: range)
        let translation = domeDirection(
            azimuthRadians: position.azimuthRadians,
            elevationRadians: position.elevationRadians
        ) * Float(radius)
        let apparentEdgeMeters = radius * cubeEdgeKm / position.distanceKm
        return (translation, Float(max(apparentEdgeMeters, 0.01)))
    }

    /// The rotation aligning cube-local axes with the lattice's ecliptic
    /// frame, expressed in the AR world frame: local +x faces the vernal
    /// equinox, +y the June-solstice point, +z ecliptic north. Shared by
    /// every cube in the frame — the lattice is one rigid grid.
    private nonisolated static func latticeOrientation(for observer: ObserverState) -> simd_quatf {
        func worldAxis(_ ecliptic: Vector3) -> SIMD3<Float> {
            let ecef = Frames.ecefFromEcliptic(
                ecliptic,
                gmstRadians: observer.gmstRadians,
                obliquityRadians: observer.obliquityRadians
            )
            let enu = Frames.enuComponents(
                ofEcef: ecef,
                latitudeRadians: observer.latitudeRadians,
                longitudeRadians: observer.longitudeRadians
            )
            // ENU → AR world under .gravityAndHeading (+x east, +y up, +z south).
            return SIMD3(Float(enu.x), Float(enu.z), Float(-enu.y))
        }
        return simd_quatf(simd_float3x3(columns: (
            worldAxis(Vector3(x: 1, y: 0, z: 0)),
            worldAxis(Vector3(x: 0, y: 1, z: 0)),
            worldAxis(Vector3(x: 0, y: 0, z: 1))
        )))
    }

    /// AR world frame under .gravityAndHeading: +x east, +y up, +z south.
    private nonisolated static func domeDirection(azimuthRadians: Double, elevationRadians: Double) -> SIMD3<Float> {
        let cosElevation = cos(elevationRadians)
        return SIMD3<Float>(
            Float(sin(azimuthRadians) * cosElevation),
            Float(sin(elevationRadians)),
            Float(-cos(azimuthRadians) * cosElevation)
        )
    }

    private nonisolated static func domeRadius(forDistanceKm distance: Double, range: DistanceRange) -> Double {
        let normalized = range.spanKm > 0
            ? min(max((distance - range.minKm) / range.spanKm, 0), 1)
            : 0.5
        return minDomeRadiusMeters
            + (maxDomeRadiusMeters - minDomeRadiusMeters) * normalized
    }
}
