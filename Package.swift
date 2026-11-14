// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "micinput",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "micinput"),
        .testTarget(name: "micinputTests", dependencies: ["micinput"]),
    ]
)
