// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OsaHub",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OsaHub",
            path: "Sources/OsaHub",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
