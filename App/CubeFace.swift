import SwiftUI

/// The six faces of a lattice cube. Every cube is oriented to the lattice's
/// ecliptic axes (one rigid grid), so each face points at a fixed spot on the
/// celestial sphere: local +x at the vernal equinox (the First Point of
/// Aries), +y at the June-solstice point 90° ahead along the ecliptic, and
/// +z at the ecliptic north pole. Case order is the cube mesh's material
/// order and the persisted color-array order — don't reorder.
enum CubeFace: Int, CaseIterable, Identifiable {
    case vernalEquinox
    case autumnalEquinox
    case juneSolstice
    case decemberSolstice
    case eclipticNorth
    case eclipticSouth

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .vernalEquinox: "Vernal equinox (+x)"
        case .autumnalEquinox: "Autumnal equinox (−x)"
        case .juneSolstice: "June solstice (+y)"
        case .decemberSolstice: "December solstice (−y)"
        case .eclipticNorth: "Ecliptic north (+z)"
        case .eclipticSouth: "Ecliptic south (−z)"
        }
    }

    var defaultColor: Color.Resolved {
        switch self {
        case .vernalEquinox: Color.Resolved(red: 0.400, green: 0.616, blue: 0.204, opacity: 1)
        case .autumnalEquinox: Color.Resolved(red: 1.00, green: 0.60, blue: 0.00, opacity: 1)
        case .juneSolstice: Color.Resolved(red: 1.00, green: 0.92, blue: 0.23, opacity: 1)
        case .decemberSolstice: Color.Resolved(red: 0.004, green: 0.780, blue: 0.988, opacity: 1)
        case .eclipticNorth: Color.Resolved(red: 1.00, green: 0.228, blue: 0.187, opacity: 1)
        case .eclipticSouth: Color.Resolved(red: 0.61, green: 0.15, blue: 0.69, opacity: 1)
        }
    }

    static var defaultColors: [Color.Resolved] {
        allCases.map(\.defaultColor)
    }
}
