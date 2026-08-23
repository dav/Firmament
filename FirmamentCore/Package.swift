// swift-tools-version: 6.2
import PackageDescription

// Warnings are fatal in Release for this package's own code.
//
// The project-level SWIFT_TREAT_WARNINGS_AS_ERRORS in ../project.yml cannot do
// this job: a build setting declared in the .xcodeproj never reaches SwiftPM
// package targets. Passing it on the xcodebuild command line would reach them,
// but a command-line override also hits remote dependencies that Xcode compiles
// with -suppress-warnings, and the two are mutually exclusive. So the package
// declares its own half, using SwiftPM's mechanism, which needs tools 6.2+.
//
// Release-scoped so `swift build`, `make build` and `make test` still merely
// warn — a warning mid-refactor should annotate the build, not stop it.
//
// Spread into EVERY target. A target that omits it is silently ungated, so the
// two counts below must agree:
//   grep -c '^[^/]*swiftSettings: strictWarnings' Package.swift  # expect 2
//   grep -cE '^\s+\.(target|testTarget)\(' Package.swift    # expect 2
let strictWarnings: [SwiftSetting] = [
    .treatAllWarnings(as: .error, .when(configuration: .release))
]

let package = Package(
    name: "FirmamentCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FirmamentCore", targets: ["FirmamentCore"])
    ],
    targets: [
        .target(name: "FirmamentCore", swiftSettings: strictWarnings),
        .testTarget(
            name: "FirmamentCoreTests",
            dependencies: ["FirmamentCore"],
            swiftSettings: strictWarnings
        )
    ]
)
