// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HydayTalk",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "HydayTalk", targets: ["HydayTalk"])],
    targets: [
        .target(name: "TalkCore"),
        .executableTarget(name: "HydayTalk", dependencies: ["TalkCore"]),
        .testTarget(name: "TalkCoreTests", dependencies: ["TalkCore"])
    ]
)
