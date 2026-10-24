// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DevKeeper",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DevKeeper", targets: ["DevKeeper"]),
        .executable(name: "devkeeper-cli", targets: ["devkeeper-cli"]),
        .library(name: "DevKeeperCore", targets: ["DevKeeperCore"])
    ],
    targets: [
        // Foundation-only logic shared by the macOS app and the Linux command-line tool.
        .target(name: "DevKeeperCore", path: "Sources/DevKeeperCore"),
        .executableTarget(name: "DevKeeper", dependencies: ["DevKeeperCore"], path: "Sources/DevKeeper"),
        .executableTarget(name: "devkeeper-cli", dependencies: ["DevKeeperCore"], path: "Sources/devkeeper-cli"),
        .testTarget(name: "DevKeeperCoreTests", dependencies: ["DevKeeperCore"], path: "Tests/DevKeeperCoreTests")
    ]
)
