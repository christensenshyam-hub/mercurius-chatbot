import Foundation
import Testing

/// The Mac app's release settings agree across the files that each hold a
/// piece of them: project.yml (the target), ExportOptionsMac.plist (the
/// export), provision.sh and release.sh (the profile they make and look
/// for), and the entitlements the Mac App Store requires. A rename in one
/// and not the others fails here instead of at the end of a five-minute
/// archive. Reads the repo's own files, so it runs when the package is built
/// inside the repo (CI and local).
private let iosDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // Tests
    .deletingLastPathComponent()   // AppFeature
    .deletingLastPathComponent()   // Packages
    .deletingLastPathComponent()   // ios

private func text(_ path: String) -> String? {
    try? String(contentsOf: iosDir.appendingPathComponent(path), encoding: .utf8)
}

private func plist(_ path: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: iosDir.appendingPathComponent(path)) else { return nil }
    return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
}

/// project.yml's `MercuriusMac:` target block (up to the next target).
private let macTarget: String? = {
    guard let yml = text("project.yml"),
          let start = yml.range(of: "\n  MercuriusMac:\n") else { return nil }
    let rest = yml[start.upperBound...]
    let end = rest.range(of: "\n  MercuriusTests:\n")?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}()

/// The values of `key: value` lines in `block`, quotes removed, in order.
private func values(_ key: String, in block: String) -> [String] {
    block.split(separator: "\n").compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(key + ":") else { return nil }
        return trimmed.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

/// `NAME="value"` in a shell script.
private func shellValue(_ name: String, in script: String) -> String? {
    script.split(separator: "\n").lazy.compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(name + "=\"") else { return nil }
        return trimmed.dropFirst(name.count + 2).split(separator: "\"").first.map(String.init)
    }.first
}

private let universalBundleId = "com.mayoailiteracy.mercurius.native"
private let macProfile = "Mercurius Mac App Store"

@Suite("Mac release settings agree",
       .enabled(if: macTarget != nil && plist("scripts/ExportOptionsMac.plist") != nil))
struct MacReleaseConfigTests {

    @Test("Release builds the iOS app's bundle id (universal purchase); Debug keeps its own")
    func bundleIds() throws {
        let block = try #require(macTarget)
        let ids = values("PRODUCT_BUNDLE_IDENTIFIER", in: block)
        // base first, then the Debug override.
        #expect(ids.first == universalBundleId)
        #expect(ids.contains("\(universalBundleId).macdev"))
        #expect(ids.count == 2, "one base id and one Debug override, nothing for Release")
    }

    @Test("project.yml, ExportOptionsMac.plist, provision.sh and release.sh name the same Mac profile")
    func profileName() throws {
        let block = try #require(macTarget)
        #expect(values("PROVISIONING_PROFILE_SPECIFIER", in: block) == [macProfile])

        let options = try #require(plist("scripts/ExportOptionsMac.plist"))
        let profiles = options["provisioningProfiles"] as? [String: String]
        #expect(profiles == [universalBundleId: macProfile])

        #expect(shellValue("MAC_PROFILE_NAME", in: text("scripts/provision.sh") ?? "") == macProfile)
        #expect(shellValue("MAC_PROFILE_NAME", in: text("scripts/release.sh") ?? "") == macProfile)
    }

    @Test("The export is the App Store one, manually signed for the team, with an installer certificate")
    func exportOptions() throws {
        let options = try #require(plist("scripts/ExportOptionsMac.plist"))
        let iosOptions = try #require(plist("scripts/ExportOptions.plist"))
        #expect(["app-store-connect", "app-store"].contains(options["method"] as? String))
        #expect(options["teamID"] as? String == iosOptions["teamID"] as? String)
        #expect(options["signingStyle"] as? String == "manual")
        #expect(options["signingCertificate"] as? String == "Apple Distribution")
        #expect(options["installerSigningCertificate"] as? String == "Mac Installer Distribution")
        #expect(options["destination"] as? String == "export")
    }

    @Test("Release signs manually with Apple Distribution and the hardened runtime")
    func signing() throws {
        let block = try #require(macTarget)
        #expect(values("CODE_SIGN_IDENTITY", in: block).contains("Apple Distribution"))
        #expect(values("CODE_SIGN_STYLE", in: block).contains("Manual"))
        #expect(values("ENABLE_HARDENED_RUNTIME", in: block) == ["YES"])
        #expect(values("ASSETCATALOG_COMPILER_APPICON_NAME", in: block) == ["MacAppIcon"])
    }

    @Test("Entitlements: the sandbox (the Mac App Store requires it), the network, printing and the files the student picks — nothing else")
    func entitlements() throws {
        let entitlements = try #require(plist("MercuriusMac/MercuriusMac.entitlements"))
        #expect(Set(entitlements.keys) == [
            "com.apple.security.app-sandbox",
            "com.apple.security.network.client",
            // A photo to attach (read), and the certificate's Save as PDF…
            // (write), both only where the student picks in the panel.
            "com.apple.security.files.user-selected.read-write",
            // The certificate's Print… (a sandboxed app can't print without it).
            "com.apple.security.print",
        ])
        #expect(entitlements.values.allSatisfy { ($0 as? Bool) == true })
    }

    @Test("Info.plist: Education, no non-exempt encryption, HTTPS only, the mercurius:// scheme")
    func infoPlist() throws {
        let info = try #require(plist("MercuriusMac/Info.plist"))
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.education")
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect((info["NSAppTransportSecurity"] as? [String: Any])?["NSAllowsArbitraryLoads"] as? Bool == false)
        #expect(info["LSMinimumSystemVersion"] as? String == "$(MACOSX_DEPLOYMENT_TARGET)")
        let schemes = (info["CFBundleURLTypes"] as? [[String: Any]])?.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes == ["mercurius"])
    }

    @Test("The Mac app ships the iOS app's privacy manifest")
    func privacyManifest() throws {
        let block = try #require(macTarget)
        #expect(block.contains("- path: Mercurius/Resources/PrivacyInfo.xcprivacy"))
    }
}
