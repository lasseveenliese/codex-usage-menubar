// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexLimitBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexLimitBar",
            targets: ["CodexLimitBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexLimitBar"
        ),
        .testTarget(
            name: "CodexLimitBarTests",
            dependencies: ["CodexLimitBar"]
        )
    ]
)
