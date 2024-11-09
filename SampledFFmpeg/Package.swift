// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SampledFFmpeg",
  platforms: [.macOS(.v15)],
  products: [.library(name: "SampledFFmpeg", targets: ["SampledFFmpeg"])],
  targets: [
    .target(name: "SampledFFmpeg", dependencies: ["CoreFFmpeg"]),
    .target(name: "CoreFFmpeg", dependencies: ["CFFmpeg"]),
    .target(
      name: "CFFmpeg",
      path: "Sources/CFFmpeg",
      exclude: ["share"],
      linkerSettings: [
        .linkedLibrary("bz2"),
        .linkedLibrary("iconv"),
        .linkedLibrary("z"),
        // Libraries of interest
        .linkedLibrary("opus"),
      ]
    )
  ]
)
