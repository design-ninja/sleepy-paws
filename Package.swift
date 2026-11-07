// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SleepyPaws",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "SleepyPaws", targets: ["SleepyPaws"])],
    targets: [
        .target(name: "SleepyPawsCore"),
        .executableTarget(name: "SleepyPaws", dependencies: ["SleepyPawsCore"]),
        .testTarget(name: "SleepyPawsCoreTests", dependencies: ["SleepyPawsCore"])
    ]
)
