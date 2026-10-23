// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DevKeeper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DevKeeper",
            path: "Sources/DevKeeper"
        )
    ]
)
