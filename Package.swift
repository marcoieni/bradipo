// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "bradipo",
    platforms: [.macOS("27.2.1")],
    targets: [
        .target(name: "BradipoCore"),
        .executableTarget(name: "bradipo", dependencies: ["BradipoCore"]),
        .testTarget(name: "BradipoCoreTests", dependencies: ["BradipoCore"]),
    ]
)
