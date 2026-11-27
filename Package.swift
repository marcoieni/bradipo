// swift-tools-version: 6.4
import Foundation
import PackageDescription

// With the Command Line Tools, Swift 6.4's build system sometimes leaves out the
// Swift Testing plug-in path, so `swift test` fails with "plugin for module
// 'TestingMacros' not found" (https://github.com/swiftlang/swift-build/issues/1870).
// This checks which toolchain evaluates the manifest, so Xcode builds are unaffected.
// The fix is https://github.com/swiftlang/swift-build/pull/1872. The extra path stays
// harmless after it, so remove this once the Command Line Tools you build with include it.
let usesCommandLineTools = Bundle(for: Package.self).bundlePath
    .hasPrefix("/Library/Developer/CommandLineTools/")

let package = Package(
    name: "bradipo",
    platforms: [.macOS("27.2.1")],
    targets: [
        .target(name: "BradipoCore"),
        .executableTarget(name: "bradipo", dependencies: ["BradipoCore"]),
        .testTarget(
            name: "BradipoCoreTests",
            dependencies: ["BradipoCore"],
            swiftSettings: usesCommandLineTools ? [
                .unsafeFlags([
                    "-plugin-path",
                    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing",
                ]),
            ] : []
        ),
    ]
)
