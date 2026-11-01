// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Push2Talk",
  platforms: [.macOS(.v13)],
  products: [.library(name: "Push2TalkCore", targets: ["Push2TalkCore"])],
  targets: [
    .target(name: "Push2TalkCore"),
    .testTarget(name: "Push2TalkCoreTests", dependencies: ["Push2TalkCore"]),
  ]
)
