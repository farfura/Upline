// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Upline",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Upline",
            path: "Sources/Upline"
        )
    ]
)
