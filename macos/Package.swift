// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HomeworkMac",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "HomeworkKit", path: "Sources/HomeworkKit"),
        .executableTarget(
            name: "HomeworkMac",
            dependencies: ["HomeworkKit"],
            path: "Sources/HomeworkMac",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HomeworkKitTests", dependencies: ["HomeworkKit"], path: "Tests/HomeworkKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
