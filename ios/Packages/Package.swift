// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LocalPackages",
    // macOS listed alongside iOS so `swift test` can run the logic
    // tests from the command line — and for the native Mac app
    // (MercuriusMac in ios/project.yml), whose window lives in AppFeature
    // behind `#if os(macOS)` (AppFeature/Sources/Mac). macOS 14 matches
    // the iOS 17-era SwiftUI API surface we depend on.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "NetworkingKit", targets: ["NetworkingKit"]),
        .library(name: "PersistenceKit", targets: ["PersistenceKit"]),
        .library(name: "LessonInteractives", targets: ["LessonInteractives"]),
        .library(name: "ChatFeature", targets: ["ChatFeature"]),
        .library(name: "CurriculumFeature", targets: ["CurriculumFeature"]),
        .library(name: "SettingsFeature", targets: ["SettingsFeature"]),
        .library(name: "EngagementFeature", targets: ["EngagementFeature"]),
        .library(name: "MercuriusActivity", targets: ["MercuriusActivity"]),
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
            path: "DesignSystem/Sources",
            // Reading-font candidates for the tutor's replies (Lexend,
            // Atkinson Hyperlegible + their OFL licenses). Registered at
            // runtime by BrandFontRegistrar — no UIAppFonts/project.yml
            // involvement, so the generated app target stays untouched.
            resources: [.copy("Fonts")]
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

        // MARK: LessonInteractives
        //
        // The lesson interactives' content, logic, copy and views (every
        // card but Lesson 1.1's, which stays in ChatFeature for now), plus
        // the registry that says which lesson holds which card. DesignSystem
        // only: no NetworkingKit, no PersistenceKit, so a card can't send or
        // store anything (DependencyGraphTests enforces it; NoIOTests scans
        // the sources). Where a card sits in a thread is ChatFeature's
        // (LessonInteractiveAnchor). See docs/interactives/FRAMEWORK.md.
        .target(
            name: "LessonInteractives",
            dependencies: ["DesignSystem"],
            path: "LessonInteractives/Sources"
        ),
        .testTarget(
            name: "LessonInteractivesTests",
            dependencies: ["LessonInteractives"],
            path: "LessonInteractives/Tests"
        ),

        // MARK: ChatFeature
        .target(
            name: "ChatFeature",
            dependencies: [
                "DesignSystem",
                "NetworkingKit",
                "PersistenceKit",
                "LessonInteractives",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "ChatFeature/Sources"
        ),
        .testTarget(
            name: "ChatFeatureTests",
            dependencies: ["ChatFeature", "LessonInteractives"],
            path: "ChatFeature/Tests"
        ),

        // MARK: CurriculumFeature
        .target(
            name: "CurriculumFeature",
            dependencies: ["DesignSystem", "SettingsFeature", "PersistenceKit"],
            path: "CurriculumFeature/Sources"
        ),
        .testTarget(
            name: "CurriculumFeatureTests",
            dependencies: ["CurriculumFeature", "SettingsFeature"],
            path: "CurriculumFeature/Tests"
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

        // MARK: EngagementFeature
        .target(
            name: "EngagementFeature",
            dependencies: ["DesignSystem", "NetworkingKit", "PersistenceKit"],
            path: "EngagementFeature/Sources"
        ),
        .testTarget(
            name: "EngagementFeatureTests",
            dependencies: ["EngagementFeature"],
            path: "EngagementFeature/Tests"
        ),

        // MARK: MercuriusActivity (Live Activity — shared by app + widget extension)
        .target(
            name: "MercuriusActivity",
            dependencies: ["DesignSystem"],
            path: "MercuriusActivity/Sources"
        ),
        .testTarget(
            name: "MercuriusActivityTests",
            dependencies: ["MercuriusActivity"],
            path: "MercuriusActivity/Tests"
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
                "SettingsFeature",
                "EngagementFeature",
                "MercuriusActivity",
                "LessonInteractives",
            ],
            path: "AppFeature/Sources"
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature", "ChatFeature", "CurriculumFeature", "EngagementFeature",
                           "NetworkingKit", "PersistenceKit", "SettingsFeature", "LessonInteractives"],
            path: "AppFeature/Tests"
        ),

        // MARK: ArchitectureTests
        //
        // Meta-tests that validate the package's dependency graph itself.
        // Deliberately has no target dependencies — it reads a pinned
        // `manifest.json` fixture (generated offline from
        // `swift package dump-package`) and asserts the graph matches
        // what we intend. Regenerate the fixture whenever Package.swift
        // changes, via:
        //   swift package dump-package > \
        //     ArchitectureTests/Tests/Fixtures/manifest.json
        .testTarget(
            name: "ArchitectureTests",
            path: "ArchitectureTests/Tests",
            resources: [.process("Fixtures")]
        ),
    ]
)
