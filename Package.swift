// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SwiftNote AI",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "SwiftNote AI",
            targets: ["SwiftNote AI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0"),
    ],
    targets: [
        .target(
            name: "SwiftNote AI",
            dependencies: ["Down"]),
        .testTarget(
            name: "SwiftNote AITests",
            dependencies: ["SwiftNote AI"]),
    ]
)
