// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Push2Talk",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "Push2Talk", targets: ["Push2Talk"])],
  targets: [
    .target(name: "Push2TalkCore"),
    .target(name: "Push2TalkInput", dependencies: ["Push2TalkCore"]),
    .executableTarget(name: "Push2Talk", dependencies: ["Push2TalkCore", "Push2TalkInput"]),
    .testTarget(name: "Push2TalkCoreTests", dependencies: ["Push2TalkCore"]),
    .testTarget(name: "Push2TalkInputTests", dependencies: ["Push2TalkInput"]),
  ]
)
