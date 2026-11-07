// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SleepyPaws",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "SleepyPaws", targets: ["SleepyPaws"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "SleepyPawsCore"),
        .executableTarget(
            name: "SleepyPaws",
            dependencies: ["SleepyPawsCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework ships in Contents/Frameworks of the app bundle.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SleepyPawsCoreTests", dependencies: ["SleepyPawsCore"])
    ]
)
