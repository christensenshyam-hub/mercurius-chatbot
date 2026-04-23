import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignSystem
@testable import NetworkingKit
@testable import ChatFeature
@testable import ClubFeature
@testable import CurriculumFeature
@testable import SettingsFeature

// Snapshot tests for key views.
//
// Captures pixel-level references for high-value screens in both
// light and dark appearance, at default and accessibility-XXL
// Dynamic Type. The first run writes the reference images to
// `__Snapshots__/`; subsequent runs fail if the pixels diverge.
//
// What this catches that other tests can't:
// - Color regressions (a BrandColor accidentally flipped from navy
//   to green wouldn't fail any unit test, but the snapshot diff
//   lights it up).
// - Font/weight regressions after refactors like Phase 3f.
// - Layout shifts at extreme Dynamic Type that visual-only UI tests
//   (which just check existence) can miss.
// - Accidental dark-mode holes (white-on-white text, etc.).
//
// Scope choices for this first pass:
// - Small, self-contained views: EmptyChatView, BrandLogo mark.
//   Views that depend on a live ChatViewModel or NavigationStack
//   tend to be flakier as snapshots; those stay in UI-tests land.
// - iPhone 13 layout. A specific device keeps the pixel hash stable
//   across sim versions; our ci matrix pins iPhone 16 but iPhone 13
//   is a representative portrait size that stays close to the
//   default reading layout most users see.
//
// To re-record after an intentional change:
//   Change `.image(...)` to `.image(record: .all)` for the test,
//   run once, then revert. Per-project doctrine: keep records OFF
//   in committed code.

@MainActor
final class ViewSnapshotTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Deterministic diff precision. Default (100%) flakes at anti-
        // aliased edges across simulator versions; 98% / 0.02 tolerates
        // single-pixel noise without hiding real regressions.
        // Applied locally per-test via the `precision` parameter.
    }

    // MARK: - BrandLogo

    func testBrandLogoFullLightMode() {
        let view = BrandLogo(style: .full, size: 180)
            .frame(width: 220, height: 220)
            .background(BrandColor.background)
            .environment(\.colorScheme, .light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 220, height: 220),
                traits: .init(userInterfaceStyle: .light)
            )
        )
    }

    func testBrandLogoFullDarkMode() {
        let view = BrandLogo(style: .full, size: 180)
            .frame(width: 220, height: 220)
            .background(BrandColor.background)
            .environment(\.colorScheme, .dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 220, height: 220),
                traits: .init(userInterfaceStyle: .dark)
            )
        )
    }

    func testBrandLogoMark() {
        let view = BrandLogo(style: .mark, size: 64)
            .frame(width: 80, height: 80)
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 80, height: 80)
            )
        )
    }

    // MARK: - EmptyChatView

    func testEmptyChatViewLight() {
        let view = EmptyChatView { _ in }
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13),
                traits: .init(userInterfaceStyle: .light)
            )
        )
    }

    func testEmptyChatViewDark() {
        let view = EmptyChatView { _ in }
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13),
                traits: .init(userInterfaceStyle: .dark)
            )
        )
    }

    func testEmptyChatViewAccessibilityXXL() {
        // Phase 3f canary: Dynamic Type scales the typography but layout
        // guards keep the header readable. If the cap ever disappears
        // (e.g. someone drops `lineLimit(1) + minimumScaleFactor`), the
        // snapshot diff shows the regression visually.
        let view = EmptyChatView { _ in }
            .background(BrandColor.background)
            .environment(\.dynamicTypeSize, .accessibility3)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .device(config: .iPhone13)
            )
        )
    }

    // MARK: - BrandButton

    func testBrandButtonPrimary() {
        let view = BrandButton("Start lesson", style: .primary) { }
            .frame(width: 280, height: 50)
            .padding()
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 312, height: 82)
            )
        )
    }

    func testBrandButtonSecondary() {
        let view = BrandButton("Cancel", style: .secondary) { }
            .frame(width: 280, height: 50)
            .padding()
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 312, height: 82)
            )
        )
    }

    // MARK: - ModeSelectorView
    //
    // Uses a live ChatViewModel with a stub client so the pills render
    // in their default (Socratic selected, Direct locked) state.

    func testModeSelectorDefault() {
        let model = makeChatModel()
        let view = ModeSelectorView(model: model)
            .background(BrandColor.background)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                layout: .fixed(width: 393, height: 60)
            )
        )
    }
}

// MARK: - Helpers

@MainActor
private func makeChatModel() -> ChatViewModel {
    final class StubChatClient: ChatStreaming, @unchecked Sendable {
        func streamChat(
            messages: [ChatMessageDTO],
            sessionId: String
        ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
            AsyncThrowingStream { continuation in continuation.finish() }
        }
    }
    final class StubModeClient: ModeChanging, @unchecked Sendable {
        func changeMode(to mode: ChatMode, sessionId: String) async throws -> APIClient.ModeChange {
            APIClient.ModeChange(mode: mode.rawValue, unlocked: false)
        }
    }
    return ChatViewModel(
        chatClient: StubChatClient(),
        modeClient: StubModeClient(),
        sessionIdProvider: { "snapshot-session" }
    )
}
