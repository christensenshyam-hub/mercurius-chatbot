import Testing
import Foundation

// Architecture meta-tests.
//
// These tests validate the package manifest itself — the structure of
// the dependency graph, not the behavior of any module. The compiler
// already enforces that imports resolve against declared dependencies,
// so these tests catch a different class of mistake: someone updating
// `Package.swift` to add a cross-feature dependency that *would* let
// bad imports compile.
//
// Example failure this catches: a PR that adds `"CurriculumFeature"`
// to `ChatFeature.dependencies` so ChatFeature can reach into the
// curriculum — violating the layering without being flagged by a build.
//
// Implementation: the test bundles `manifest.json` — a pinned snapshot
// of `swift package dump-package` — as a resource and asserts the graph
// against it. An earlier version of this test spawned a `Process`
// running `swift package dump-package` at test time; that deadlocked
// because SwiftPM holds the build lock while test bundles run, and the
// dump command needs the same lock. Regenerating the fixture stays a
// one-line manual step documented in Package.swift.

// MARK: - Manifest loading

private struct Manifest: Decodable {
    let targets: [Target]

    struct Target: Decodable {
        let name: String
        let type: String
        let dependencies: [Dependency]

        struct Dependency: Decodable {
            /// `byName` entries look like `[["TargetName", null]]`.
            let byName: [StringOrNull]?
            /// `product` entries look like `[["ProductName", "package-identity", null, null]]`.
            let product: [StringOrNull]?

            /// Resolved dep name — pulls from whichever list is populated.
            var resolvedName: String? {
                if let byName = byName?.first?.stringValue { return byName }
                if let product = product?.first?.stringValue { return product }
                return nil
            }
        }

        /// Whether this is a real product target (not a test target).
        var isLibrary: Bool { type == "regular" || type == "library" }
    }
}

/// Swift's `swift package dump-package` emits dependency list entries
/// as mixed-type arrays like `["Name", null, null, null]`. Decode each
/// element defensively — we only care about the string names.
private enum StringOrNull: Decodable {
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        self = .null
    }

    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }
}

private func loadManifest() throws -> Manifest {
    guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json") else {
        throw NSError(
            domain: "ArchitectureTests",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "manifest.json fixture not found. Regenerate via: swift package dump-package > ArchitectureTests/Tests/Fixtures/manifest.json"]
        )
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Manifest.self, from: data)
}

// MARK: - Architecture rules
//
// These constants codify the intended layering. Change them deliberately
// when you intend to change the architecture.

/// Feature packages. They may depend on the infra layer (DesignSystem,
/// NetworkingKit, PersistenceKit) but NOT on each other, except via
/// the composition root (`AppFeature`).
private let featureModules: Set<String> = [
    "ChatFeature",
    "CurriculumFeature",
    "ClubFeature",
    "SettingsFeature",
]

/// Infra / core modules that features are allowed to depend on.
private let infraModules: Set<String> = [
    "DesignSystem",
    "NetworkingKit",
    "PersistenceKit",
]

/// Composition root. Only this module is allowed to fan out across
/// every feature.
private let appModule = "AppFeature"

/// Allowed external product deps (products from 3rd-party packages).
private let allowedExternalProducts: Set<String> = [
    "MarkdownUI",
]

/// Deliberate cross-feature deps, where one feature may import another.
/// Kept explicit so additions are reviewed.
private let allowedCrossFeatureDeps: [String: Set<String>] = [
    // CurriculumFeature uses SettingsFeature's `PreferenceStore` to
    // persist lesson progress — a narrow, deliberate coupling.
    "CurriculumFeature": ["SettingsFeature"],
]

// MARK: - Tests

@Suite("Architecture — package dependency graph")
struct DependencyGraphTests {

    @Test("manifest.json fixture exists and parses")
    func fixtureLoads() throws {
        let manifest = try loadManifest()
        #expect(!manifest.targets.isEmpty)
    }

    @Test("Every feature module lists only allowed dependencies")
    func featuresOnlyDependOnInfraOrApprovedFeatures() throws {
        let manifest = try loadManifest()

        for target in manifest.targets where featureModules.contains(target.name) {
            let depNames = Set(target.dependencies.compactMap(\.resolvedName))
            let allowed = infraModules
                .union(allowedExternalProducts)
                .union(allowedCrossFeatureDeps[target.name] ?? [])

            let unauthorized = depNames.subtracting(allowed)
            #expect(
                unauthorized.isEmpty,
                "\(target.name) has unauthorized deps: \(unauthorized.sorted()). If intentional, add them to the allowed-list in DependencyGraphTests.swift."
            )
        }
    }

    @Test("AppFeature (composition root) depends on every feature module")
    func appFeatureComposesEverything() throws {
        let manifest = try loadManifest()
        guard let app = manifest.targets.first(where: { $0.name == appModule }) else {
            Issue.record("AppFeature target missing from manifest")
            return
        }
        let depNames = Set(app.dependencies.compactMap(\.resolvedName))
        for feature in featureModules {
            #expect(
                depNames.contains(feature),
                "AppFeature is the composition root but doesn't depend on \(feature)"
            )
        }
        // AppFeature should also pull in every infra module — it's the
        // only place where clients are constructed.
        for infra in infraModules {
            #expect(
                depNames.contains(infra),
                "AppFeature should depend on infra module \(infra)"
            )
        }
    }

    @Test("Infra modules never depend on features")
    func infraDoesNotReachUp() throws {
        let manifest = try loadManifest()
        for target in manifest.targets where infraModules.contains(target.name) {
            let depNames = Set(target.dependencies.compactMap(\.resolvedName))
            let upwardLeaks = depNames
                .intersection(featureModules)
                .union(depNames.intersection([appModule]))
            #expect(
                upwardLeaks.isEmpty,
                "\(target.name) is infra but depends on feature/app modules: \(upwardLeaks.sorted()). Infra must stay below features."
            )
        }
    }

    @Test("Dependency graph has no cycles")
    func noCycles() throws {
        let manifest = try loadManifest()

        // Build adjacency map for library-type targets only — test
        // targets always fan up into their parent, which looks like a
        // cycle but isn't.
        var graph: [String: [String]] = [:]
        for target in manifest.targets where target.isLibrary {
            graph[target.name] = target.dependencies.compactMap(\.resolvedName)
        }

        // DFS with three-color marking. Grey = on stack, Black = done.
        enum Color { case white, grey, black }
        var color: [String: Color] = [:]
        for name in graph.keys { color[name] = .white }

        func visit(_ node: String, stack: [String]) -> [String]? {
            color[node] = .grey
            for neighbor in graph[node] ?? [] {
                switch color[neighbor] ?? .white {
                case .grey:
                    return stack + [node, neighbor]
                case .white:
                    if let cycle = visit(neighbor, stack: stack + [node]) { return cycle }
                case .black:
                    continue
                }
            }
            color[node] = .black
            return nil
        }

        for name in graph.keys where color[name] == .white {
            if let cycle = visit(name, stack: []) {
                Issue.record("Dependency cycle detected: \(cycle.joined(separator: " → "))")
            }
        }
    }

    @Test("Every expected module is present (catches accidental deletions)")
    func allExpectedModulesExist() throws {
        let manifest = try loadManifest()
        let present = Set(manifest.targets.filter(\.isLibrary).map(\.name))
        let expected = featureModules
            .union(infraModules)
            .union([appModule])
        let missing = expected.subtracting(present)
        #expect(missing.isEmpty, "Expected modules missing from manifest: \(missing.sorted())")
    }
}
