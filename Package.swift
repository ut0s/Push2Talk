// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Push2Talk",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "Push2TalkCore", targets: ["Push2TalkCore"]),
    .library(name: "Push2TalkInput", targets: ["Push2TalkInput"]),
  ],
  targets: [
    .target(name: "Push2TalkCore"),
    .target(name: "Push2TalkInput", dependencies: ["Push2TalkCore"]),
    .testTarget(name: "Push2TalkCoreTests", dependencies: ["Push2TalkCore"]),
    .testTarget(name: "Push2TalkInputTests", dependencies: ["Push2TalkInput"]),
  ]
)
