// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InfluTo",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "InfluTo", targets: ["InfluTo"]),
    ],
    dependencies: [],   // ZERO external dependencies
    targets: [
        .target(
            name: "InfluTo",
            path: "Sources/InfluTo",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "InfluToTests",
            dependencies: ["InfluTo"],
            path: "Tests/InfluToTests"
        ),
    ]
)
