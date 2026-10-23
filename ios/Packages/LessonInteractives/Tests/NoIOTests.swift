import Foundation
import Testing
@testable import LessonInteractives

/// "Offline and deterministic" by construction: the module depends on
/// DesignSystem only (ArchitectureTests), and its sources name no network,
/// file or storage API. The one allowance: launch arguments read inside
/// `#if DEBUG` (`InteractiveLaunchOptions` reads `ProcessInfo`, which is
/// not on the list; UserDefaults would be allowed there too).
@Suite("Interactives: no network, nothing stored")
struct NoIOTests {
    static let forbidden: [String] = [
        "URLSession", "URLRequest", "import Network", "NWConnection", "FileManager", "@AppStorage", "SwiftData",
        "@Model", "UserDefaults", "Codable", "Encodable", "Decodable", "JSONEncoder", "PropertyListEncoder",
        "Data(contentsOf", "write(to", "NSUbiquitousKeyValueStore", "Keychain", "SecItem",
        "import NetworkingKit", "import PersistenceKit",
    ]
    static let allowedInDebug: Set<String> = ["UserDefaults"]

    /// The module's Swift sources, found from this file's path.
    static func sources() throws -> [URL] {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = tests.deletingLastPathComponent().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test("No source names a network, file or storage API")
    func scan() throws {
        let files = try Self.sources()
        #expect(files.count >= 10, "found \(files.count) sources")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            var debugDepth = 0
            var depth = 0
            for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("#if") {
                    depth += 1
                    if line.contains("DEBUG") && debugDepth == 0 { debugDepth = depth }
                } else if line.hasPrefix("#endif") {
                    if depth == debugDepth { debugDepth = 0 }
                    depth -= 1
                } else if line.hasPrefix("#else") || line.hasPrefix("#elseif"), depth == debugDepth {
                    debugDepth = 0
                }
                // Comments may name what the module doesn't do.
                if line.hasPrefix("//") { continue }
                let code = line.components(separatedBy: "//").first ?? line
                for word in Self.forbidden where code.contains(word) {
                    let allowed = debugDepth > 0 && Self.allowedInDebug.contains(word)
                    #expect(allowed, "\(file.lastPathComponent):\(number + 1) uses \(word)")
                }
            }
        }
    }

    @Test("The scan catches what it should")
    func catches() {
        let sample = "let session = URLSession.shared"
        #expect(Self.forbidden.contains { sample.contains($0) })
    }
}

@Suite("Interactives: state lives in memory only")
@MainActor
struct StateStoreTests {
    final class Probe {
        var value = 0
    }

    @Test("One state object per card, made once, kept across asks")
    func perCard() {
        let store = InteractiveStateStore()
        #expect(!store.hasState(for: .doubtDial))
        var made = 0
        let first = store.state(for: .doubtDial) { () -> Probe in made += 1; return Probe() }
        first.value = 3
        let again = store.state(for: .doubtDial) { () -> Probe in made += 1; return Probe() }
        #expect(again === first && again.value == 3 && made == 1)
        let other = store.state(for: .pageWithASecret) { Probe() }
        #expect(other !== first)
        // A new store (a new lesson screen) starts fresh.
        #expect(!InteractiveStateStore().hasState(for: .doubtDial))
    }

    @Test("The Mac's opened cards")
    func expanded() {
        let store = InteractiveStateStore()
        #expect(!store.isExpanded(.doubtDial))
        store.expand(.doubtDial)
        store.expand(.doubtDial)
        #expect(store.isExpanded(.doubtDial) && store.expanded.count == 1)
    }

    @Test("Nothing a card holds can be encoded")
    func notCodable() {
        #expect(!((InteractiveStateStore() as Any) is any Encodable))
        #expect(!((InteractiveStateStore() as Any) is any Decodable))
        #expect(!((PredictReveal(choices: [1, 2]) as Any) is any Encodable))
        #expect(!((StepThrough(count: 2) as Any) is any Encodable))
        #expect(!((InteractiveRegistry.all[0] as Any) is any Encodable))
    }

    @Test("The context hands a card its state, keyed by its id")
    func context() throws {
        let store = InteractiveStateStore()
        let spec = try #require(InteractiveRegistry.spec(for: .doubtDial))
        let context = InteractiveCardContext(spec: spec, spoiled: true, store: store)
        let probe = context.state { context -> Probe in
            let probe = Probe()
            probe.value = context.spoiled ? 1 : 0
            return probe
        }
        #expect(probe.value == 1)
        #expect(store.hasState(for: .doubtDial))
    }
}
