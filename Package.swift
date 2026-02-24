// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignalMacOS",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SignalMacOS",
            path: "Sources"
        )
    ]
)
