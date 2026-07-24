# Dav's Firmament — Project Plan

An iOS/iPadOS AR app that renders a fixed, non-rotating 3D lattice of markers spanning the solar system, and lets you look up through your phone's camera to see which lattice nodes are currently above your horizon as Earth carries you through them.

---

## 1. The idea, in one paragraph

Picture the solar system threaded with an enormous, perfectly regular 3D lattice of markers, spaced roughly a quarter of Earth's diameter apart, fixed relative to the distant stars — they don't move, rotate, or track anything. Earth, meanwhile, is both spinning on its axis and orbiting the Sun, so relative to someone standing on its surface, this fixed lattice is constantly sweeping past: once around every day from Earth's rotation, and into an entirely new neighborhood every week from orbital motion. The app calculates, moment to moment, which of these fixed points are currently above the viewer's horizon and exactly where they'd appear in a given direction, then draws a marker there in the camera view — a permanent, invisible geometry etched across the solar system that the phone lets you see.

## 2. Goals and non-goals

**In scope for v1**
- A static, deterministic lattice defined purely by a unit spacing and an origin at the Sun's center — no stored data, computed on the fly.
- Correct geometry: given UTC time + GPS lat/lon/alt, compute which nodes are above the local horizon and their exact apparent position.
- AR camera view rendering nodes as simple cubes, scaled by apparent angular size.
- A pure, fully unit-tested "astronomy core" module with zero AR/UIKit dependencies.

**Explicitly out of scope for v1** (candidates for later phases)
- Real terrain/horizon occlusion (buildings, mountains).
- Precession/nutation/aberration-level precision (arcsecond accuracy). Arcminute accuracy is the target.
- Multiple selectable reference frames/origins (see §4.3) — ship with one, make it swappable in code, not necessarily in UI.
- Persistence, sharing, or multi-user features.

## 3. Naming

**Dav's Firmament.** *Firmament* — the old cosmological term for the sky as a fixed vault — is a nice inversion here: the "vault" really is fixed, it's the viewer who moves.

## 4. Core concept and reference frame

### 4.1 The lattice
- Origin: the Sun's center, `(0, 0, 0)`.
- Unit spacing: ~3,185 km (a quarter of Earth's mean diameter of 12,742 km) — tune later, see §11.
- Node positions are never stored. For any `(i, j, k)` integer triple, `node = (i, j, k) × unitSpacing`. The lattice is regenerated on demand from whichever integer range is near the observer's current position.

### 4.2 The frame is inertial (non-rotating)
Confirmed: the lattice is fixed relative to the distant stars, not co-rotating with Earth's orbit. This is what makes "Earth flies through it" meaningful — in a frame that co-rotated with Earth's orbit, Earth would just sit still.

### 4.3 Orientation reference — a decision to revisit, not a physics question
Any fixed inertial orientation is equally "static" — the question of *which* fixed direction defines the axes is a framing choice, not a geometry change. Two options:
- **v1 default:** standard J2000 ecliptic frame (X-axis toward the vernal equinox). This lets the astronomy core lean directly on well-documented, well-tested ephemeris formulas without any extra rotation.
- **Conceptual alternative:** orient an axis toward Alpha Centauri / Proxima Centauri (the nearest star system), for a "closest neighbor" framing.

Because switching between these is a single constant rotation offset applied once, this is safe to defer — implement against J2000 now, revisit the cosmetic axis orientation before launch if desired.

## 5. Architecture

Two cleanly separated layers, following ports-and-adapters:

**Astronomy core** (pure Swift, no imports of ARKit/SceneKit/CoreLocation/CoreMotion types in its public API — those get passed in as plain values)
- Ephemeris: UTC time → Sun's geocentric position → Earth's heliocentric position.
- Observer geometry: lat/lon/alt/time → observer's heliocentric position.
- Node visibility: observer position + node position → local East-North-Up vector, elevation, azimuth, distance.
- Lattice generation: observer position + render radius → set of candidate `(i, j, k)` triples.

This module is where nearly all the correctness risk lives, and it's the one place TDD pays for itself directly — every function above is a pure value transform, testable with no simulator, no device, no mocks.

**Rendering/platform adapter** (SceneKit or RealityKit, CoreLocation, CoreMotion)
- Feeds GPS + time into the astronomy core on a slow cadence (Earth's motion is slow; recomputing observer position and the visible node set a few times a second is plenty).
- Feeds live device attitude into the camera transform every frame (this needs to be fast/smooth; it's a separate, much simpler concern from the astronomy math).
- Owns skybox placement, angular-size scaling, and frustum culling.

```swift
// Astronomy core — illustrative shape, not final API
struct ENUVector { let east: Double; let north: Double; let up: Double }

struct ObserverState {
    let heliocentricPosition: Vector3   // km, ecliptic-aligned inertial frame
    let latitude: Double
    let longitude: Double
}

func observerState(at date: Date, latitude: Double, longitude: Double, altitude: Double) -> ObserverState { ... }

func visibleNodes(from observer: ObserverState, renderRadiusKm: Double, unitSpacingKm: Double) -> [LatticeNode] { ... }

func localENU(of node: LatticeNode, observer: ObserverState) -> ENUVector { ... }

func isAboveHorizon(_ v: ENUVector) -> Bool { v.up >= 0 }
```

## 6. The coordinate pipeline

**Stage A — Observer's heliocentric position**
1. UTC date/time → Sun's geocentric position (low-precision solar ephemeris, Meeus ch. 25 — accurate to ~0.5 arcminute, no need for full VSOP87).
2. Negate → Earth's heliocentric position.
3. GPS lat/lon/alt → observer's offset from Earth's center (ECEF), rotated by sidereal time (undo Earth's rotation) and by obliquity (~23.44°, align equatorial axes to ecliptic axes).
4. Add the rotated offset to Earth's heliocentric position → **observer's heliocentric position.**

**Stage B — Per-node visibility**
1. `vector = nodePosition − observerHeliocentricPosition`.
2. Rotate that vector back through obliquity and sidereal time into Earth-fixed (ECEF) coordinates.
3. Rotate into local East-North-Up using the observer's lat/lon.
4. `elevation = atan2(up, sqrt(east² + north²))`; `azimuth = atan2(east, north)`.
5. `elevation ≥ 0` → above horizon → hand off to rendering, combined with the phone's live attitude.

## 7. Horizon / occlusion test

No scene understanding, LiDAR, or image analysis needed. The elevation check above *is* the complete Earth-occlusion test: the tangent plane at the observer's location touches a spherical Earth at exactly one point, and the rest of the sphere lies entirely on the other side of that plane. Any ray leaving the observer at `elevation ≥ 0` can never re-intersect the Earth, at any distance. `elevation < 0` covers both "blocked by the curve of the Earth" and "node is literally inside the Earth" (which happens constantly here, since unit spacing, ~3,185 km, is smaller than Earth's radius, 6,371 km — there's always at least one node inside the planet somewhere).

Real terrain occlusion (mountains, buildings near the horizon) is a real v2+ candidate via ARKit's depth/LiDAR APIs, but isn't required for the core concept to work correctly.

## 8. Rendering strategy in AR

- **Skybox, not true-scale placement.** Even the nearest possible node is thousands of km away — vastly larger than any AR scene's real-world scale. Place all visible nodes on a fixed-radius dome using their computed direction (azimuth/elevation), the same technique planetarium apps use for "infinitely far" stars.
- **Angular size as the depth cue.** Give the cubes a fixed real-world edge length, and scale their rendered size by `edgeLength / trueDistance`. This gives a genuine, physically-grounded sense of near vs. far without needing true-scale placement — a cube at the nearest possible distance can meaningfully subtend a degree or more, while distant ones shrink toward a point.
- **Frustum culling before rendering.** The local candidate bubble might hold a few thousand nodes; only cull to the camera's field of view (`dot(cameraForward, direction) > cos(halfFOV)`) before instantiating render objects — no need to keep thousands of SceneKit/RealityKit nodes live.
- **Device orientation:** either `ARWorldTrackingConfiguration` with `.gravityAndHeading` world alignment, or a simpler `CMDeviceMotion` + `.xTrueNorthZVertical` attitude reference feeding a plain SceneKit/RealityKit camera over a raw camera feed. The latter avoids ARKit's SLAM/feature-tracking machinery entirely, which buys nothing here since there's no need to anchor to real-world surfaces — verify exact axis conventions against Apple's current docs when implementing either path.
- **Differentiated rendering for near-horizon/occluded nodes** (your own idea from the original conversation): render nodes that are just below the horizon as ghost/wireframe cubes rather than hiding them outright, so the lattice structure still reads even when partially blocked.

## 9. UX considerations

- **Compass calibration is the real risk, not the astronomy.** Magnetometer heading is the classic weak point of every AR-compass app (see: Pokémon Go's AR mode). Plan for: a calibration prompt, and a manual "sync" affordance — let the user tap on the Sun, Moon, or a known bright star (when visible) to correct heading drift, the way stargazing apps let you sync on a known object.
- **Tap-to-inspect.** Tapping a node could surface its `(i, j, k)` index, true distance, and heliocentric coordinates — useful both as a debugging tool during development and as a nice bit of "look how far away that actually is" flavor for users.
- **Update cadence split** (also an architecture point, §5): astronomical position updates can run slowly (seconds), device attitude must run every frame. Keeping these decoupled is both a performance win and a cleaner testing boundary.

## 10. Testing strategy

- **TDD the astronomy core first, before any UI exists.** Every function in §5's core module is a pure value transform — no mocks, no simulator, no device required.
- **Golden-value fixtures.** Pick a handful of known dates/locations and record expected outputs from a trusted source (JPL Horizons, Stellarium, or a solar-position calculator) as test fixtures. Assert the core module's output matches within a defined tolerance (arcminutes, not arcseconds).
- **SwiftAA** (MIT-licensed, actively maintained, available via SPM: `github.com/onekiloparsec/SwiftAA`) wraps the Meeus algorithms and is already used in production astronomy apps (including telescope-control apps from Vaonis). Worth using directly for the solar ephemeris rather than hand-rolling it, while keeping your own core module as the thin layer that owns the observer/node geometry on top.
- **Keep the rendering layer's test surface small.** Once the core module is solid and tested, the AR/rendering adapter's job is just "take an azimuth/elevation/distance and place a cube" — much less worth heavy automated testing, more suited to manual/visual verification on-device.

## 11. Open parameters to tune before launch

| Parameter | Starting point | Notes |
|---|---|---|
| Unit spacing | ~3,185 km (¼ Earth diameter) | Bigger = fewer, more widely separated nodes; smaller = denser but visually noisier sky |
| Render radius (candidate bubble) | A few thousand to tens of thousands of km | Trade-off between node count and "nothing nearby" moments |
| Cube edge length | TBD, tune against render radius | Drives apparent angular size — see §8 |
| Orientation axis reference | J2000 ecliptic (vernal equinox) | Cosmetic; single rotation offset to change later (§4.3) |
| Position/heading update cadence | Astronomy: ~1 Hz; device attitude: every frame | Decouple for both performance and testability |

## 12. Phased roadmap

- **Phase 0 — Astronomy core, test-first.** Ephemeris, observer position, node visibility, horizon test. No AR, no UI — just a Swift package and a test suite, validated against golden fixtures.
- **Phase 1 — Minimal AR render.** Static skybox rendering of visible nodes for a fixed date/location, no live device orientation yet. Confirms the geometry "looks right."
- **Phase 2 — Live orientation integration.** Wire up CoreMotion/ARKit attitude so the sky view responds to actually moving the phone.
- **Phase 3 — UX polish.** Compass calibration/sync affordance, angular-size tuning, occluded-node ghost rendering, tap-to-inspect.
- **Phase 4 — Stretch.** Real terrain occlusion via LiDAR/depth, alternate lattice origins or orientation references, historical/future date scrubbing.

## 13. References

- Jean Meeus, *Astronomical Algorithms* (2nd ed.) — the standard reference for the low-precision solar ephemeris and sidereal time formulas used throughout.
- SwiftAA — `github.com/onekiloparsec/SwiftAA` — Swift wrapper around Meeus's algorithms.
- Apple documentation for `ARWorldTrackingConfiguration.WorldAlignment`, `CMDeviceMotion`, and `CMAttitudeReferenceFrame` — verify exact axis conventions at implementation time.
