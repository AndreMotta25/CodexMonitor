// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexMonitorCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CodexMonitorCore", targets: ["CodexMonitorCore"])],
    targets: [
        .target(name: "CodexMonitorCore", path: "CodexMonitor/Shared",
                exclude: ["SharedSnapshotStore.swift", "RefreshQuotaIntent.swift"]),
        .testTarget(name: "CodexMonitorCoreTests", dependencies: ["CodexMonitorCore"], path: "Tests")
    ]
)
