// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalPackages",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NetworkingKit", targets: ["NetworkingKit"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    targets: [
        // MARK: DesignSystem
        .target(
            name: "DesignSystem",
            path: "DesignSystem/Sources"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["DesignSystem"],
            path: "DesignSystem/Tests"
        ),

        // MARK: NetworkingKit
        .target(
            name: "NetworkingKit",
            path: "NetworkingKit/Sources"
        ),
        .testTarget(
            name: "NetworkingKitTests",
            dependencies: ["NetworkingKit"],
            path: "NetworkingKit/Tests"
        ),

        // MARK: AppFeature
        .target(
            name: "AppFeature",
            dependencies: ["DesignSystem", "NetworkingKit"],
            path: "AppFeature/Sources"
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"],
            path: "AppFeature/Tests"
        ),
    ]
)
