# Step 02: make it feel like a Mac app

Branch `feat/mac-app-2026-10` (worktree `.claude/worktrees/mac-app`). Not pushed. This step covers what PLAN.md had split across steps 2–5 (safety parity, Mac-native chat and lessons, notifications, polish); PLAN.md is updated to match.

Everything Mac-only is behind `#if os(macOS)`. The few shared helpers it needs (`macReadableColumn`, `macHoverHighlight`, `macPointingHand` in `DesignSystem/Sources/MacInteraction.swift`) return the view unchanged on iOS.

## Commits

- `de5fb8d` Shared chat and lesson views: composer, reading column, hover, Copy, toolbar, menu targets, lesson-complete card.
- `38a9850` Crisis numbers as large selectable text with Copy.
- `cab9ffb` Toolbar chat, menu commands, the Settings and Help windows, reminders.
- `ccf1695` Snapshot harness: Settings/Help windows, typing into the composer, light/dark at two sizes.
- `d9198a9` Polish from the screenshots (below).
- `dbddab5` The composer's ⌘V watcher reads its own window and live focus. Its closure had captured a copy of the view's state. It now also ignores a ⌘V in the Settings window, whose selectable session ID takes a field editor too.
- (this commit) Notes, PLAN.md, CLAUDE.md and screenshots.

## What was built

**Composer** (`ChatInputBar`)
- Return sends (the field's own `onSubmit`, as on iOS). Shift-Return puts a line break at the cursor (`onKeyPress` → the field editor's `insertNewlineIgnoringFieldEditor`). Option-Return still breaks the line too, as everywhere on the Mac. While an input method is composing, Return is left to it.
- The field takes focus when a chat or lesson opens, and again when a lesson's intro clears.
- Plain text-field style: the Mac's own bezel was the dark bar inside the capsule in step 01.
- Images: the attach button opens the open panel (`fileImporter`, images only; the sandbox's user-selected read-only entitlement covers it). A picture dropped anywhere on the chat or lesson attaches, with a "Drop to attach this image" highlight. ⌘V attaches a pasted picture when the pasteboard has no text, or an image file copied in Finder; otherwise ⌘V pastes text as usual. All three end in `ChatViewModel.attachImage(data:)`, the iPhone's downsample-and-upload path. Attach is off while a reply is coming, as the button is.
- Stop has the same button as iOS; the send button looks the same.

**Layout**
- A 720 pt reading column, centred: the thread, the composer, the empty chat's prompts, the lesson header, the lesson intro, the unit check. Replies may run to 580 pt (340 on a phone).
- The learning path keeps to a 560 pt column, so Merc stands beside the next stop instead of at the window's far edge.
- The gate keeps to a 720 × 700 box, so a tall window doesn't put each step's button far below its question.
- The lesson-complete celebration is a centred card (440 pt) with Merc bursting over its top, not a window-wide bottom sheet. Return takes its primary button, Escape (or a click on the backdrop) goes back to the lesson. A lesson intro's Continue is on Return too.

**Pointer and menus**
- Hover tint plus the pointing hand: the empty chat's prompt cards, the Explain more / Quiz me chips, Retry, [Q] options (only while answerable), unit-test options (until submitted). The pointing hand alone on open path nodes and on links.
- Right-click on any message: **Copy** (the student's text as typed; Merc's reply as plain text, without lesson markers or a [Q]'s answer key), then Merc's **Report response** submenu, the same report path as iOS's long press. This is the Mac's entry point to reporting.
- The shared views' buttons are borderless in the window's detail column. The Mac's default push-button bezel had drawn grey boxes around the streak chip, the hint's ✕, Retry and others.

**Toolbar (chat)**
- The streak chip, then a segmented Socratic / Debate / Discussion picker in the middle, then Explain More and New Chat.
- The picker follows the pills' rules: the mode explainer the first time a mode is chosen, no switching mid-reply or mid-switch, and the same "Couldn't switch modes" alert.
- The iPhone's in-chat header (Settings, Home) and pills are iOS-only now. Settings is ⌘, and Today is a sidebar row.
- The window title is "Chat", with the mode as its subtitle.

**Menu bar** (`MacCommands`)

| Menu | Item | Keys |
|---|---|---|
| File | New Chat | ⌘N |
| File | Attach Image… | ⇧⌘A |
| Chat | Socratic / Debate / Discussion (current one checked) | ⌘1 / ⌘2 / ⌘3 |
| Chat | Retry | ⌘R |
| Chat | Explain More | ⇧⌘E |
| View | Today / Learning Path / Chat | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 (moved from ⌘1–⌘3, which are now the modes) |
| Mercurius | Settings… | ⌘, |
| Help | Mercurius Help | ⌘? |
| Help | Help & FAQ, Send Feedback, Contact Support | links |

- Retry, Explain More and Attach Image act on whichever chat or lesson the window shows (`ChatCommandTarget`, published with `focusedSceneValue`). They're off when the action isn't available, and in a lesson while its intro or celebration covers it.
- A mode chosen from the menu opens the chat and goes through the toolbar picker's path, including the explainer.
- Everything that touches the shell is off while the gate shows.

**Settings window** (⌘,; `MacSettingsWindowView` in SettingsFeature, on the iPhone's `SettingsViewModel` and reset wiring)
- **General:** Appearance (System / Light / Dark); the progress-nudges switch, while that flag is on.
- **Privacy:**
  - The session ID, selectable, with a Copy that is current-host-only (off Universal Clipboard), marked concealed for clipboard managers, and cleared after 2 minutes unless something else was copied since.
  - Delete My Data & Start Over… with the same confirmation, failure alert and device-only reset sheet as iOS.
  - Privacy Choices… (the disclosure and withdrawing consent, in a sheet).
- **About:** the version, How Mercurius Teaches… (opens the Help window), Help & FAQ, Send Feedback, Contact Support, Terms, Privacy Policy.
- While Settings is deleting or resetting, the main window is disabled, even after Settings is closed. A message sent mid-erasure would go out under the old ID; the iPhone's sheet can't be left at that point, and the Mac's window can.
- The session-ID Copy in the shared `SettingsView` and in the device-reset sheet didn't copy anything on the Mac (UIKit only). Both now use the Mac pasteboard with the same care.

**Help window** (⌘?)
- A segmented control with three tabs: How Mercurius Teaches; On a Mac (the shortcuts, the three ways to attach a photo, and why this Mac's progress is separate from a phone's); Get Help (the support links and the crisis numbers).
- Static content only, so it opens before the gate too.
- It's a segmented control rather than a `TabView`: in this window on macOS 26, a `TabView` showed no tabs, only a toolbar overflow button.

**Crisis support** (`CrisisSupportView`, Mac branch `MacCrisisNumbers`)
- Each line is a card: what to do ("Call or text", "Text HOME to", "Call"), the number in 34 pt rounded bold and selectable, the service, and a Copy button.
- Under each number: "Call with FaceTime" / "Text with Messages" links (`tel:` / `sms:`, the app's own URLs, never model text), with a note that they need this Mac to be set up for calls or texts.
- VoiceOver reads the digits one by one, as on iOS.
- iOS keeps its tappable rows, unchanged.

**Reminders**
- `NotificationScheduler` and `NotificationRouter` run on macOS with the same weekly plan, streak defense and Merc art. `MacAppDelegate` installs the delegate in `applicationWillFinishLaunching`, so a reminder clicked while the app was closed opens its lesson.
- Today shows the iPhone Home's one-time weekly-nudge card, decided the same way (`ReminderCardStore.shows`).
- `mercurius://` links open in the existing window (`handlesExternalEvents`), not a second one.
- The Progress hub's "notifications are off" note names System Settings ▸ Notifications.
- `NotificationScheduler.center` is nil outside an app bundle. `UNUserNotificationCenter.current()` traps in `swift test`'s host, and the reset tests call the scheduler.

**Gate on the Mac**
- The age picker is a pop-up at its own size, with its bezel. The window's borderless button style had drawn it as bare accent text; it's restored. Its hints say "from the menu", not "on the wheel".

**Dark mode:** every window state was photographed in dark (below). The Settings window uses the system's grouped-form colours, as Mac settings windows do.

**Dynamic Type: not available to this app.**
- macOS has no Dynamic Type for SwiftUI apps. I measured it in a small SwiftUI host on this Mac: `.dynamicTypeSize(.accessibility5)` changed neither a `.body` font's height (18.5 pt either way), nor `Font.custom(…, relativeTo: .body)`, nor `@ScaledMetric` (17 at xSmall, default and AX5).
- The per-app Text Size slider in System Settings ▸ Accessibility ▸ Display has no key in `com.apple.Accessibility`, so there was nothing to set with `defaults` for this app, and nothing to test. Every layout was still checked at the 860 × 600 minimum window.
- Product gap: a Mac text-size control (View ▸ Bigger/Smaller) would need a scale factor threaded through `BrandFont` and the reply's MarkdownUI theme.

## Safety parity

| Requirement | Mac |
|---|---|
| Consent/age gate before any network call | Unchanged from step 01 (`MacShellModel.isGated`; menu, sidebar, Settings and shell tasks off). The new menu items are gated too; Help is static. |
| Crisis numbers readable and selectable | Done (above). |
| Delete my data | Settings ▸ Privacy, on the iPhone's model and reset wiring; the main window holds still while it runs. |
| Report a reply | Right-click a reply ▸ Report response ▸ reason; same `reportMessage` path and feedback alert as iOS. |

## Verification

- `swift test` (macOS host): **951 tests in 141 suites pass**, up from 937. The 14 new tests:
  - paste / drop / Copy rules, on private named pasteboards that never touch the clipboard (9, including the Explain More rule and the ⌘V guard);
  - menu mode requests, gating, ⌘1–⌘3 order, the erasure lock (4);
  - no notification centre in the test host (1).
- Mac app: Debug build, no warnings from the new code.
- **Return / Shift-Return with real key events.** The harness types into the real composer through the window (`-MacSnapshotType`). The field's text is logged as `COMPOSER` lines, in `shots/02/chat-typing.composer.txt` and `chat-failed.composer.txt`:
  - "Why do chatbots sound so sure?" then Shift-Return then "Even when they're wrong?" gives two lines in the field;
  - "What is a token?" then Return sends it: the field empties, the message appears, and the absent local server gives the Retry state in `chat-failed`.
- **iOS doesn't regress.**
  - `build-for-testing` of the `Mercurius` scheme (app, widgets, unit and UI tests) succeeds on an iPhone 16 simulator (iOS 26.4).
  - **18 UI-test anchors pass, 18 of 18, no reruns**, on the build of `d9198a9`:
    - boot, the tab bar, the chat header's Home and Settings, the starter prompts;
    - the mode pills (Debate) and the first-tap and already-seen mode sheets;
    - the empty-chat hint;
    - Settings' Appearance section, its feedback and How it teaches rows, and the delete-failure device-reset sheet;
    - Home's next stop and the curriculum's units;
    - the first-run gate, the consent sentence, under-13, Not now, and the existing-install gate.
  - `dbddab5` came after that run and only touches Mac code.
  - Not run: the rest of the UI suite and the snapshot tests; no snapshot record runs.
- **Not driven by a real pointer or keyboard:** hover, the pointing hand, right-click menus, drag-and-drop, ⌘V of a picture, the open panel, the menu shortcuts, Settings' delete / withdraw, and a reminder firing.
  - The harness can photograph and type, but can't hover, right-click, drag or answer system prompts. Notifications would need the founder's Mac to grant permission.
  - Their logic is unit-tested where it's logic, and the views are the same code paths as iOS.
  - Pasting a file copied in Finder relies on the sandbox's pasteboard file access. The test covering it runs unsandboxed.

## Screenshots (`shots/02/`)

Every main-window state is taken four ways:
- `<state>.png`: 1280 × 800 pt, light, @2x;
- `<state>-dark.png`;
- `<state>-min.png`: the 860 × 600 minimum, light;
- `<state>-min-dark.png`.

The variants are scaled to 1x to keep the repo small. Settings and Help have their own sizes, so they're light and dark only. All 68 were taken by `ios/scripts/mac-snapshots.sh` (isolated: in-memory chats and session ID, local server URL, nothing to production). I looked at every light full-size shot, every state at least once in dark and at the minimum size, and all the panels.

| State | Shows |
|---|---|
| `gate-meet`, `gate-age`, `gate-consent` | The gate in its box. The age pop-up has its bezel. `gate-age.controls.txt` / `gate-consent.controls.txt` list the AppKit controls. |
| `today` | Today with the sidebar. |
| `path` | Unit 1 in its 560 pt column, Merc beside the start node. |
| `lesson-intro` | A fresh lesson's intro in the column; Continue on Return. |
| `lesson` | A replayed lesson reply (EXAMPLE / KEY IDEA cards) at the Mac measure. |
| `lesson-complete` | The centred celebration card (`-ForceCelebrate`, no real completion). |
| `chat` | Empty chat: toolbar picker, Explain More (off), New Chat, prompt cards, hint, focused composer. |
| `chat-thread` | A 50-message seeded thread, opened at its latest reply, with Explain more / Quiz me. |
| `chat-typing` | Two lines typed with Shift-Return. |
| `chat-failed` | A sent message, the network failure line and Retry. |
| `unit-test` | The unit check reviewed (red / green rows) in the column. |
| `crisis` | The unit check's crisis support: selectable numbers, Copy, FaceTime / Messages links. |
| `settings-general`, `settings-privacy`, `settings-about` | The Settings window's tabs. |
| `help`, `help-mac`, `help-support` | The Help window's tabs. |

**Found in the screenshots and fixed (`d9198a9`):**
- **Saved threads opened at the top.** The window rebuilds the chat whenever its sidebar row is chosen, with the thread already loaded, so it opened at the thread's first message with "Jump to latest" showing. It now opens at the latest message. The jump repeats briefly while the lazy rows measure (in a debug run a single jump landed 212 pt short), and it stops if the student scrolls first.
- **The age pop-up** drew as bare accent text, and its 150 pt wheel frame centred it in empty space.
- **The gate's buttons** sat at the bottom of a tall window, far below their question.
- **Settings ▸ About** was cut off at Legal.
- **The Help window's tabs were invisible** (the `TabView` above).
- **Phone wording:** the "notifications are off" note told Mac users to open the iOS Settings app.

**Seen, not changed:**
- **Capture artefacts.** Liquid Glass surfaces still come out dark or washed-out in captures: the sidebar, the toolbar band (dark grey over the crisis view in dark mode), and the consent checkbox's bezel. How they look on screen is unverified.
- **The lesson intro** sits low in a tall window, with the speech bubble just above Merc as on iOS, leaving empty space above.
- **The path's streak bar** runs the full width of the detail column, while the path keeps to its column.

## Left for later, and why

- **"Try cellular data" on a Mac.** The network-blocked message and the network daily-limit message both suggest cellular data; on a Mac that means a phone's hotspot. Changing it needs a copy decision and platform-aware tests: several tests that run on the Mac host pin the iPhone wording.
- **The consent disclosure** says "Settings → Delete my data & start over". On the Mac the path is Settings ▸ Privacy ▸ Delete My Data & Start Over…. The consent text is versioned, so I didn't touch it.
- **Text size** (above).
- **CI still doesn't build the `MercuriusMac` target**; the shared Mac code is compiled by CI's `swift test`. A `X-Mercurius-Client` header is still recommended and not added. Both are in the release step.
- **The App Store review prompt and window state restoration** aren't on the Mac yet.
- **Cross-device sync:** a product gap, by design (PLAN.md).
