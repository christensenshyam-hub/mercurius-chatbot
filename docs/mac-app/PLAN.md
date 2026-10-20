# Mercurius for Mac: plan

Branch `feat/mac-app-2026-10`, based on `fix/ios-student-2026-10` (PR #43). Step 1 found no plan file, so this one was written then. It records the decisions the later steps build on. Each step has its own notes in this folder (`01-target-shell.md`, …).

## The founder's decisions

- A **native SwiftUI Mac app**. Not Catalyst, not the iPhone/iPad app running on a Mac, not Electron.
- Shipped on the **Mac App Store** as a **universal purchase** with the iOS app. That means the same bundle id, `com.mayoailiteracy.mercurius.native`, in the same App Store Connect record.

## Shape

- **One more target, the same packages.** `MercuriusMac` in `ios/project.yml` is a thin `@main` shell. It holds the window scene, the Settings scene, the menu commands and the DEBUG screenshot harness. Everything else comes from the local packages, which already build for macOS 14 because `swift test` runs on the Mac host.
- **The Mac window is composed in AppFeature**, under `AppFeature/Sources/Mac`, with every file inside `#if os(macOS)`. AppFeature stays the one composition root, so there's no new package and no change to the dependency graph that `ArchitectureTests` pins. `swift test` compiles and tests the Mac code on every run, including CI's Xcode 16.2.
- **The gate logic is shared, not copied.** `RootView` (bootstrap) → `AppEntryView` (gate decision, reminder re-plan, consent withdrawal) runs on both platforms. On the Mac, `AppEntryView` mounts `MacShellView` instead of Home / `AppShellView`, and hands it the onboarding/consent flow while the gate shows.
- **The window:** a `NavigationSplitView`. The sidebar has three sections: **Today** (`HomeView`, the iOS doorman, as a page), **Learning path** (one row per unit, opening that unit's stretch of the path), and **Chats** (New Chat, then the saved threads). The detail column hosts the same views the iPhone shows: `CurriculumView`, `ChatView`, `CurriculumLessonView`, `UnitTestView` and `OnboardingFlow`.
- **Bundle ids:** Release (archive) uses `com.mayoailiteracy.mercurius.native`. Debug uses `com.mayoailiteracy.mercurius.native.macdev`. A Mac that has the App Store iPad app installed keeps that app's data in `~/Library/Containers/com.mayoailiteracy.mercurius.native` (the founder's Mac does). A Debug build with the real id would read and write that container: consent, chats (including a SwiftData store an older build may not be able to open after migration), and the URL scheme. Debug-only, so the store build is unaffected. It's a one-line change in `project.yml` if it should go.

## Facts that constrain every step

- Deployment targets are iOS 17 and macOS 14. Locally we build with Xcode 26.4 (Swift 6.3); CI uses Xcode 16.2 (Swift 6.0.3) on macos-14. So any API newer than macOS 14 / iOS 17 needs `#available` **and** has to compile on the macOS 15 SDK. Also avoid `Double`·`CGFloat` mixes, which Swift 6.0 rejects.
- Live Activity, ActivityKit, widgets and haptics are iOS-only. UserNotifications, the Keychain, SwiftData, PhotosPicker and URLSession SSE all work on macOS.
- **The server is unchanged.** The Mac talks to production exactly as iOS does (see Client identification).
- **Identity is per device.** `SessionIdentity` keeps an anonymous id in the Keychain. On macOS that is the login keychain, which doesn't sync through iCloud. A student's Mac and iPhone are therefore two separate anonymous sessions, each with its own progress, streak and chats. There are no accounts. **Product gap:** nothing carries progress from phone to Mac. Cross-device sync is out of scope here, because it needs accounts or a pairing scheme.

## Safety and consent parity (must match iOS)

| Requirement | Status |
|---|---|
| Consent/age gate before **any** network call | Step 1: the shared `AppEntryView` gate runs in the Mac window's detail column. While it shows, the sidebar is hidden and disabled, the menu commands are off (`MacShellModel.isGated`), the Settings window shows a placeholder, and the shell's server tasks (progress pull, Progress hub) wait. Bootstrap's server fetches only run when consent is already current, as on iOS. Step 2's new menu items are gated the same way; the Help window is static. |
| Crisis support shows the numbers as readable, selectable text | **Done in step 2.** `MacCrisisNumbers`: each number large and selectable with a Copy button, then FaceTime/Messages links. |
| Delete my data | **Step 2:** the native Settings window (Privacy tab) on the iPhone's `SettingsViewModel` and reset wiring; the main window is disabled while an erasure runs, even after Settings closes. Not clicked through end to end on the Mac (no Mac UI automation yet). |
| Report a reply | **Step 2:** right-click a reply ▸ Report response ▸ reason (Copy is the first item), the same `reportMessage` path and feedback alert as iOS. |

## Client identification (server unchanged)

Today the server can't tell a Mac from an iPhone. Every request carries only `Content-Type`, `Accept`, `x-trace-id` and CFNetwork's default `User-Agent` (`Mercurius/<build> CFNetwork/… Darwin/…`), and that is the same shape on both platforms. `/api/chat` also sends `capabilities: ["blocks_v1"]`, which is identical on both.

**Recommendation: yes, add a hint, and make it an additive header,** for example `X-Mercurius-Client: macos/2.3.0 (16)` (and `ios/…` from the iPhone app), set in `APIClient.buildRequest` and `buildChatRequest`. The server ignores unknown headers today. Later it would let support, analytics and the per-IP quota tuning for school NATs tell the platforms apart. **Don't add a body field.** Several routes validate bodies with `.strict()` zod schemas (`lib/schemas.js`: the report context, progress items), so an unknown key there is a 400. Not done in step 1; it fits the release step together with the server change that reads it.

## Steps

1. **Target and shell** (done; `01-target-shell.md`). Includes dark mode for the Mac (BrandColor had no macOS dark variant). Covers the macOS target (sandbox, hardened runtime, Mac icon, privacy manifest, scheme); the App with WindowGroup + Settings + Commands; the NavigationSplitView shell; DEBUG state arguments; the `-MacSnapshot` harness; and tests.
2. **Mac-native** (done; `02-mac-native.md`). This took in what the first plan split across steps 2–5:
   - safety parity (crisis numbers, Report by right-click, delete in the Settings window, the age step's Mac wording);
   - the composer: Return sends, Shift-Return breaks the line, focus on open; images by button, drop or paste;
   - reading columns, hover and the pointing hand, Copy;
   - the chat toolbar (mode, Explain More, New Chat) and the menu bar (⌘N, ⌘1–⌘3 modes, ⌘R, ⇧⌘E, ⇧⌘A, ⌥⌘1–⌥⌘3, ⌘?);
   - the native Settings window and a Help window;
   - reminders through UserNotifications, with the click-to-lesson link;
   - the lesson-complete card;
   - dark mode checked in every state.
   It also found that macOS gives SwiftUI apps no Dynamic Type (measured).
3. **Tests, CI and release tooling** (done; `03-tests-ci-release.md`).
   - Tests for the sidebar's routing, the composer's Return key and send rule, the snapshot harness's arguments (and the scripts that pass them), and the release settings across `project.yml`, the export options and the scripts.
   - A `mac` CI job: unsigned Debug and universal Release builds, `mac-bundle-check.sh`, a launch smoke test.
   - `provision.sh --platform mac` / `--check`, `release.sh --platform mac`, `ExportOptionsMac.plist`, `asc-api.sh` (a plain message for the App Store Connect 403 about an unaccepted agreement).
   - `mac-store-screenshots.sh` (2560 × 1600; 2880 × 1800 needs a taller display).
   - `docs/APP_STORE_LISTING.md` §7 and `FOUNDER_STEPS.md`.
4. **Full verification** (done; `VERIFY.md`).
   - Passing: the branch is clean; `swift test` 994/994 from an empty scratch path; iOS build plus CI-flag `xcodebuild test` 31/31; Mac Debug, plus unsigned universal Release without the DEBUG harness.
   - No network before consent, by code reading and by fresh-container launches against a logging server.
   - No screenshots: the screen stayed locked.
   - Two low findings: Release honours launch arguments on a Mac (`-UITests`, the argument domain); `mac-snapshots.sh` accepts blank pictures.
5. **Founder: ship it** (`FOUNDER_STEPS.md`). Accept the agreement that makes App Store Connect answer 403, run `provision.sh --platform mac`, add the macOS platform to the record, `release.sh --platform mac`, rehearse from TestFlight, take the store screenshots on an unlocked Mac, submit.

Still open (not started):
- the `X-Mercurius-Client` header (client side; the server change that reads it is separate);
- window state restoration and the App Store review prompt on the Mac;
- a Mac UI-test target (clicking through delete, withdraw and report). It would drive the real pointer and keyboard of whatever Mac runs it, and macOS asks for an administrator to allow UI automation, so it suits CI better than the founder's Mac;
- the Mac wording of the network messages ("try cellular data") and of the consent disclosure's Settings path;
- a text-size control.

## Open questions for the founder

- **iPad-on-Mac users.** Once the native app ships, the Mac App Store replaces an installed iPad version. The native app then reads that version's container (consent, the local progress cache, and its chats in the SwiftData store). It does **not** read its Keychain session id: iPad apps use the data-protection keychain, while this app uses the login keychain. Such a student would see their old chats and progress locally under a **new** anonymous session, and the progress would push to that new session. Possible fix: use the data-protection keychain on macOS. That needs the app's keychain access group, which an App Store build has, and it keeps the old id. Not verified yet; it needs a TestFlight-for-Mac build.
- Keep or drop the Debug-only `.macdev` bundle id (above).
