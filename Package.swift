// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Status",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "StatusCore", targets: ["StatusCore"]),
        .library(name: "StatusUI", targets: ["StatusUI"])
    ],
    targets: [
        .target(
            name: "StatusCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(name: "StatusUI", dependencies: ["StatusCore"]),
        .testTarget(name: "StatusCoreTests", dependencies: ["StatusCore", "StatusUI"])
    ]
)
