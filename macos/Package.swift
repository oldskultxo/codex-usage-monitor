// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexUsageMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexUsageMonitor", targets: ["UsageMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "UsageMonitor",
            path: "Sources/UsageMonitor"
        )
    ]
)
