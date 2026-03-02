// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Bobber",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Bobber",
            path: "Sources/Bobber"
        ),
        .testTarget(
            name: "BobberTests",
            dependencies: ["Bobber"],
            path: "Tests/BobberTests"
        )
    ]
)
