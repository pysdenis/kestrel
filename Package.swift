// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kestrel",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KestrelCore", targets: ["KestrelCore"]),
        .executable(name: "kestrel", targets: ["kestrel-cli"]),
        .executable(name: "kestrel-app", targets: ["KestrelApp"]),
    ],
    targets: [
        .target(
            name: "KestrelCore",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreServices"),
            ]
        ),
        .executableTarget(
            name: "kestrel-cli",
            dependencies: ["KestrelCore"]
        ),
        // SwiftUI menu-bar app (Phase 3). Compiles against Core; proper packaging
        // (LSUIElement bundle, signing, notarization) lands in Phase 7.
        .executableTarget(
            name: "KestrelApp",
            dependencies: ["KestrelCore"]
        ),
        // Dependency-free test runner that works with Command Line Tools only
        // (XCTest requires a full Xcode install — see Tests/ for the XCTest suite
        // that runs once Xcode is present).
        .executableTarget(
            name: "kestrel-tests",
            dependencies: ["KestrelCore"]
        ),
    ]
)
