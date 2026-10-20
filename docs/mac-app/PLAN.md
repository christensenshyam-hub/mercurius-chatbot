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
| Consent/age gate before **any** network call | Step 1: the shared `AppEntryView` gate runs in the Mac window's detail column. While it shows, the sidebar is hidden and disabled, the menu commands are off (`MacShellModel.isGated`), the Settings window shows a placeholder, and the shell's server tasks (progress pull, Progress hub) wait. Bootstrap's server fetches only run when consent is already current, as on iOS. |
| Crisis support shows the numbers as readable, selectable text | **Step 2.** `CrisisSupportView` uses `tel:`/`sms:` `Link`s; on a Mac those open FaceTime or Messages, or nothing. |
| Delete my data | Step 1 wires it: the Settings window (⌘,) and the chat header's Settings sheet both use the iOS `SettingsSheet`, including server erasure and consent withdrawal, and withdrawal puts the window back on the gate. Step 2 verifies it end to end on the Mac. |
| Report a reply | Step 1 leaves the iOS flow in place (`ChatView` → `MessageListView` `onReport`), but its long-press entry point needs a Mac equivalent (context menu). **Step 2.** |

## Client identification (server unchanged)

Today the server can't tell a Mac from an iPhone. Every request carries only `Content-Type`, `Accept`, `x-trace-id` and CFNetwork's default `User-Agent` (`Mercurius/<build> CFNetwork/… Darwin/…`), and that is the same shape on both platforms. `/api/chat` also sends `capabilities: ["blocks_v1"]`, which is identical on both.

**Recommendation: yes, add a hint, and make it an additive header,** for example `X-Mercurius-Client: macos/2.3.0 (16)` (and `ios/…` from the iPhone app), set in `APIClient.buildRequest` and `buildChatRequest`. The server ignores unknown headers today. Later it would let support, analytics and the per-IP quota tuning for school NATs tell the platforms apart. **Don't add a body field.** Several routes validate bodies with `.strict()` zod schemas (`lib/schemas.js`: the report context, progress items), so an unknown key there is a 400. Not done in step 1; it fits the release step together with the server change that reads it.

## Steps

1. **Target and shell** (done; `01-target-shell.md`). Includes dark mode for the Mac (BrandColor had no macOS dark variant). Covers the macOS target (sandbox, hardened runtime, Mac icon, privacy manifest, scheme); the App with WindowGroup + Settings + Commands; the NavigationSplitView shell; DEBUG state arguments; the `-MacSnapshot` harness; and tests.
2. **Safety parity.** Crisis numbers as selectable text on macOS. A Mac entry point for reporting a reply (context menu). Delete my data and consent withdrawal driven end to end in the Settings window. Gate controls checked by eye on screen: the consent checkbox, and the age pop-up, which replaces the iOS wheel. The age step's "on the wheel" VoiceOver hint is wrong on a Mac.
3. **Mac-native chat and lessons.** Return sends and Shift-Return adds a newline. The composer's text-field style (it draws a dark bezel inside the capsule). A readable message width in a wide window. Focus, hover, a toolbar (New Chat, mode), paste and drag-and-drop for images, and window titles.
4. **Notifications.** `NotificationScheduler` / `NotificationRouter` are iOS-only today. On the Mac the Your path step's reminder choices are stored but schedule nothing, and Today hides the weekly-nudge card. Also deep links (`mercurius://lesson/<id>`).
5. **Polish.** Help menu (How Mercurius teaches, support resources), the Settings window layout, a dark-mode pass, VoiceOver and keyboard navigation, window state restoration, the App Store review prompt (not wired on the Mac), and Mac-sized path and Today layouts.
6. **Release.** Create the Mac App Store provisioning profile "Mercurius Mac App Store" for the real id and a Mac Installer Distribution certificate. Add a `release.sh --mac` path (archive → export → `.pkg` → upload). In App Store Connect, add the macOS platform to the existing app record (universal purchase), plus Mac screenshots and the same privacy label. Add a CI job that builds `MercuriusMac` on macos-14 / Xcode 16.2, plus the `X-Mercurius-Client` header.

## Open questions for the founder

- **iPad-on-Mac users.** Once the native app ships, the Mac App Store replaces an installed iPad version. The native app then reads that version's container (consent, the local progress cache, and its chats in the SwiftData store). It does **not** read its Keychain session id: iPad apps use the data-protection keychain, while this app uses the login keychain. Such a student would see their old chats and progress locally under a **new** anonymous session, and the progress would push to that new session. Possible fix: use the data-protection keychain on macOS. That needs the app's keychain access group, which an App Store build has, and it keeps the old id. Not verified yet; it needs a TestFlight-for-Mac build.
- Keep or drop the Debug-only `.macdev` bundle id (above).
