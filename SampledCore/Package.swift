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
  products: [
    .library(name: "SampledCore", targets: ["SampledCore"]),
    .library(name: "SampledOpenSubsonicAPI", targets: ["SampledOpenSubsonicAPI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-openapi-generator", revision: "83e8301d6d62c423f8e11d6fcb0c8276d4dbb032"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", revision: "f039fa6d6338aab5164f3d1be16281524c9a8f89"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", revision: "576a65b4ffb8c12ddad4950dc21eea2ef071bec2"),
  ],
  targets: [
    // TODO: Remove.
    //
    // We only need CFFmpeg and CoreFFmpeg.
    .target(name: "SampledCore", dependencies: ["CoreFFmpeg"]),
    .target(name: "CoreFFmpeg", dependencies: ["CFFmpeg"]),
    .target(
      name: "CFFmpeg",
      path: "Sources/CFFmpeg/\(arch)",
      exclude: ["share", "src"],
      linkerSettings: [.linkedLibrary("iconv")],
    ),
    .target(
      name: "SampledOpenSubsonicAPI",
      dependencies: [
        .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
        .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
      ],
      resources: [
        .process("openapi.json"),
      ],
      plugins: [
        .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator"),
      ],
    )
  ],
)
