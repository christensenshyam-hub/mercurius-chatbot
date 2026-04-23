// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalPackages",
    // macOS listed alongside iOS so `swift test` can run the logic
    // tests from the command line. The app itself only ships for iOS.
    // macOS 14 matches the iOS 17-era SwiftUI API surface we depend on.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NetworkingKit", targets: ["NetworkingKit"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .library(name: "CurriculumFeature", targets: ["CurriculumFeature"]),
        .library(name: "ClubFeature", targets: ["ClubFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
        // Third-party markdown renderer. Chosen over Apple's
        // AttributedString(markdown:) because Claude's responses
        // use headings, lists, and code fences that AttributedString
        // silently drops.
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
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

        // MARK: PersistenceKit
        .target(
            name: "PersistenceKit",
            dependencies: ["NetworkingKit"],
            path: "PersistenceKit/Sources"
        ),
        .testTarget(
            name: "PersistenceKitTests",
            dependencies: ["PersistenceKit"],
            path: "PersistenceKit/Tests"
        ),

        // MARK: ChatFeature
        .target(
            name: "ChatFeature",
            dependencies: [
                "DesignSystem",
                "NetworkingKit",
                "PersistenceKit",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "ChatFeature/Sources"
        ),
        .testTarget(
            name: "ChatFeatureTests",
            dependencies: ["ChatFeature"],
            path: "ChatFeature/Tests"
        ),

        // MARK: CurriculumFeature
        .target(
            name: "CurriculumFeature",
            dependencies: ["DesignSystem", "SettingsFeature"],
            path: "CurriculumFeature/Sources"
        ),
        .testTarget(
            name: "CurriculumFeatureTests",
            dependencies: ["CurriculumFeature", "SettingsFeature"],
            path: "CurriculumFeature/Tests"
        ),

        // MARK: ClubFeature
        .target(
            name: "ClubFeature",
            dependencies: ["DesignSystem", "NetworkingKit"],
            path: "ClubFeature/Sources"
        ),
        .testTarget(
            name: "ClubFeatureTests",
            dependencies: ["ClubFeature", "NetworkingKit"],
            path: "ClubFeature/Tests"
        ),

        // MARK: SettingsFeature
        .target(
            name: "SettingsFeature",
            dependencies: ["DesignSystem", "NetworkingKit"],
            path: "SettingsFeature/Sources"
        ),
        .testTarget(
            name: "SettingsFeatureTests",
            dependencies: ["SettingsFeature"],
            path: "SettingsFeature/Tests"
        ),

        // MARK: AppFeature
        .target(
            name: "AppFeature",
            dependencies: [
                "DesignSystem",
                "NetworkingKit",
                "PersistenceKit",
                "ChatFeature",
                "CurriculumFeature",
                "ClubFeature",
                "SettingsFeature",
            ],
            path: "AppFeature/Sources"
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature"],
            path: "AppFeature/Tests"
        ),
    ]
)
