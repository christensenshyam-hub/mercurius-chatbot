import Foundation
import Testing

/// AUD-57: the privacy manifest and the planned App Store label must agree,
/// and both must call the collected data linked (Apple counts data kept
/// under a user ID as linked). Reads the repo's own files, so it runs when
/// the package is built inside the repo (CI and local).
private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // AppFeature
    .deletingLastPathComponent()   // Packages
    .deletingLastPathComponent()   // ios
    .deletingLastPathComponent()   // repo root

private let manifest: [String: Any]? = {
    let url = repoRoot.appendingPathComponent("ios/Mercurius/Resources/PrivacyInfo.xcprivacy")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}()

private let listing: String? = try? String(
    contentsOf: repoRoot.appendingPathComponent("docs/APP_STORE_LISTING.md"), encoding: .utf8)

@Suite("Privacy manifest matches the App Store label", .enabled(if: manifest != nil && listing != nil))
struct PrivacyManifestTests {

    private var collected: [[String: Any]] {
        (manifest?["NSPrivacyCollectedDataTypes"] as? [[String: Any]]) ?? []
    }

    /// The manifest's type names as the listing's §3 table names them.
    private static let labelNames: [String: String] = [
        "NSPrivacyCollectedDataTypeUserID": "User ID",
        "NSPrivacyCollectedDataTypeOtherUserContent": "Other User Content",
        "NSPrivacyCollectedDataTypePhotosorVideos": "Photos or Videos",
        "NSPrivacyCollectedDataTypeProductInteraction": "Product Interaction",
    ]

    @Test("Four types, every one linked and none used for tracking; no tracking at all")
    func manifestAnswers() {
        #expect(manifest?["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest?["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
        let types = collected.compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(Set(types) == Set(Self.labelNames.keys))
        for entry in collected {
            let type = entry["NSPrivacyCollectedDataType"] as? String ?? "?"
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool == true, "\(type) must be linked")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false, "\(type) must not track")
        }
    }

    @Test("The listing's §3 table says the same: collected, linked, not tracking, same purposes")
    func listingMatches() throws {
        let rows = (listing ?? "").split(separator: "\n").map(String.init)
        for entry in collected {
            let type = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            let name = try #require(Self.labelNames[type])
            let row = try #require(rows.first { $0.hasPrefix("|") && $0.contains("**\(name)**") },
                                   "no §3 row for \(name)")
            let cells = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // | type | collected | linked | tracking | purpose |
            #expect(cells.count == 5, "\(row)")
            guard cells.count == 5 else { continue }
            #expect(cells[1] == "Yes", "\(name): collected")
            #expect(cells[2] == "**Yes**", "\(name): linked")
            #expect(cells[3] == "**No**", "\(name): tracking")
            let purposes = (entry["NSPrivacyCollectedDataTypePurposes"] as? [String]) ?? []
            let expected = purposes.map {
                $0 == "NSPrivacyCollectedDataTypePurposeAnalytics" ? "Analytics" : "App Functionality"
            }.joined(separator: ", ")
            #expect(cells[4] == expected, "\(name): purposes")
        }
    }
}
