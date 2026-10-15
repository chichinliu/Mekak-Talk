// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MekakTalk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MekakTalk", targets: ["MekakTalk"])],
    targets: [
        .target(name: "TalkCore"),
        .executableTarget(name: "MekakTalk", dependencies: ["TalkCore"]),
        .testTarget(name: "TalkCoreTests", dependencies: ["TalkCore"])
    ]
)
