// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexUsageMenubar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "CodexUsageMenubar",
            targets: ["CodexUsageMenubar"]
        )
    ],
    targets: [
        .executableTarget(name: "CodexUsageMenubar")
    ]
)
