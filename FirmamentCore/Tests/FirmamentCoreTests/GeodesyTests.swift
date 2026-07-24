import Foundation
import Testing
@testable import FirmamentCore

struct GeodesyTests {
    @Test func equatorPrimeMeridian() {
        let ecef = Geodesy.ecefKm(latitudeDegrees: 0, longitudeDegrees: 0, altitudeMeters: 0)
        #expect(abs(ecef.x - 6_378.137) < 1e-6)
        #expect(abs(ecef.y) < 1e-9)
        #expect(abs(ecef.z) < 1e-9)
    }

    @Test func northPole() {
        let ecef = Geodesy.ecefKm(latitudeDegrees: 90, longitudeDegrees: 0, altitudeMeters: 0)
        #expect(abs(ecef.x) < 1e-6)
        #expect(abs(ecef.z - 6_356.752_314_2) < 1e-4)
    }

    @Test func altitudeAddsAlongUp() {
        let sea = Geodesy.ecefKm(latitudeDegrees: 0, longitudeDegrees: 90, altitudeMeters: 0)
        let high = Geodesy.ecefKm(latitudeDegrees: 0, longitudeDegrees: 90, altitudeMeters: 1_000)
        #expect(abs((high - sea).length - 1.0) < 1e-9)
        #expect(abs(high.y - sea.y - 1.0) < 1e-9)
    }
}
