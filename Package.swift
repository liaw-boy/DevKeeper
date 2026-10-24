// swift-tools-version:5.10
import PackageDescription

var products: [Product] = [
    .executable(name: "devkeeper-cli", targets: ["devkeeper-cli"]),
    .library(name: "DevKeeperCore", targets: ["DevKeeperCore"])
]

var targets: [Target] = [
    // Foundation-only logic shared by the macOS app and the command-line tool.
    .target(name: "DevKeeperCore", path: "Sources/DevKeeperCore"),
    .executableTarget(name: "devkeeper-cli", dependencies: ["DevKeeperCore"], path: "Sources/devkeeper-cli"),
    .testTarget(name: "DevKeeperCoreTests", dependencies: ["DevKeeperCore"], path: "Tests/DevKeeperCoreTests")
]

#if os(macOS)
// The SwiftUI app only exists on macOS.
products.append(.executable(name: "DevKeeper", targets: ["DevKeeper"]))
targets.append(.executableTarget(name: "DevKeeper", dependencies: ["DevKeeperCore"], path: "Sources/DevKeeper"))
#endif

let package = Package(
    name: "DevKeeper",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
