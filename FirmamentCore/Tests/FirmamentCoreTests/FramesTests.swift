import Foundation
import Testing
@testable import FirmamentCore

struct FramesTests {
    @Test func eclipticEcefRoundTrip() {
        let original = Vector3(x: 123_456.7, y: -89_012.3, z: 45_678.9)
        let gmst = 4.123
        let obliquity = 0.409_09
        let ecliptic = Frames.eclipticFromEcef(original, gmstRadians: gmst, obliquityRadians: obliquity)
        let back = Frames.ecefFromEcliptic(ecliptic, gmstRadians: gmst, obliquityRadians: obliquity)
        #expect((back - original).length < 1e-6)
    }

    @Test func identityWhenAnglesZero() {
        let vector = Vector3(x: 1, y: 2, z: 3)
        let transformed = Frames.eclipticFromEcef(vector, gmstRadians: 0, obliquityRadians: 0)
        #expect((transformed - vector).length < 1e-12)
    }

    @Test func rotationPreservesLength() {
        let vector = Vector3(x: 3, y: -4, z: 12)
        let rotated = Frames.eclipticFromEcef(vector, gmstRadians: 1.234, obliquityRadians: 0.567)
        #expect(abs(rotated.length - vector.length) < 1e-9)
    }

    @Test func enuAtEquatorPrimeMeridian() {
        // At lat 0, lon 0: ECEF +y is east, +z is north, +x is up.
        let east = Frames.enuComponents(ofEcef: Vector3(x: 0, y: 1, z: 0), latitudeRadians: 0, longitudeRadians: 0)
        #expect(abs(east.x - 1) < 1e-12 && abs(east.y) < 1e-12 && abs(east.z) < 1e-12)

        let north = Frames.enuComponents(ofEcef: Vector3(x: 0, y: 0, z: 1), latitudeRadians: 0, longitudeRadians: 0)
        #expect(abs(north.y - 1) < 1e-12 && abs(north.x) < 1e-12 && abs(north.z) < 1e-12)

        let up = Frames.enuComponents(ofEcef: Vector3(x: 1, y: 0, z: 0), latitudeRadians: 0, longitudeRadians: 0)
        #expect(abs(up.z - 1) < 1e-12 && abs(up.x) < 1e-12 && abs(up.y) < 1e-12)
    }

    @Test func enuAtNorthPole() {
        // At the north pole (lon 0), ECEF -x is north and +z is up.
        let halfPi = Double.pi / 2
        let up = Frames.enuComponents(ofEcef: Vector3(x: 0, y: 0, z: 1), latitudeRadians: halfPi, longitudeRadians: 0)
        #expect(abs(up.z - 1) < 1e-12)

        let northward = Vector3(x: -1, y: 0, z: 0)
        let north = Frames.enuComponents(ofEcef: northward, latitudeRadians: halfPi, longitudeRadians: 0)
        #expect(abs(north.y - 1) < 1e-12)
    }
}
