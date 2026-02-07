// swift-tools-version: 6.2.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#if arch(arm64)
let arch = "arm64"

#elseif arch(x86_64)
let arch = "x86_64"

#else
fatalError("Unknown architecture")

#endif

let package = Package(
  name: "SampledCore",
  platforms: [.macOS(.v15)],
  products: [.library(name: "SampledCore", targets: ["SampledCore"])],
  targets: [
    // TODO: Remove.
    //
    // We only need CFFmpeg and CoreFFmpeg.
    .target(name: "SampledCore", dependencies: ["CoreFFmpeg"]),
    .target(name: "CoreFFmpeg", dependencies: ["CFFmpeg"]),
    .target(
      name: "CFFmpeg",
      path: "Sources/CFFmpeg/\(arch)",
      exclude: ["share"],
      linkerSettings: [
        .linkedLibrary("bz2"),
        .linkedLibrary("iconv"),
        .linkedLibrary("z"),
        // Libraries of interest
        .linkedLibrary("opus"),
      ],
    ),
  ],
)
