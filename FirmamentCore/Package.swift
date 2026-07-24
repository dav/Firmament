// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FirmamentCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "FirmamentCore", targets: ["FirmamentCore"])
    ],
    targets: [
        .target(name: "FirmamentCore"),
        .testTarget(name: "FirmamentCoreTests", dependencies: ["FirmamentCore"])
    ]
)
