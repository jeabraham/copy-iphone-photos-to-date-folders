// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImporterRegression",
    platforms: [.macOS(.v15)],
    products: [],
    targets: [
        .target(name: "ImporterCoreLibrary", swiftSettings: [.define("IMPORTER_LIBRARY")]),
        .testTarget(name: "ImporterRegressionTests", dependencies: ["ImporterCoreLibrary"])
    ],
    swiftLanguageModes: [.v5]
)
