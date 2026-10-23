# Step 03: tests, CI and release tooling

Branch `feat/mac-app-2026-10` (worktree `.claude/worktrees/mac-app`). Not pushed, no PR. Nothing was provisioned or uploaded: App Store Connect answers every API request with HTTP 403 for an unaccepted agreement, and both scripts now say so.

## Commits

- `55aedef` The sidebar's routing and the composer's Return key, made testable, with tests.
- `6ad0ec5` The snapshot harness's launch arguments (`MacSnapshotOptions`), opaque store shots, a store screenshot script, tests that read the scripts.
- `088cad5` Release tooling: `provision.sh --platform mac` / `--check`, `release.sh --platform mac`, `ExportOptionsMac.plist`, `asc-api.sh`, `mac-bundle-check.sh`, release-settings tests.
- `97629d3` CI: the `mac` job.
- `a544a43` The pure view helpers marked `nonisolated` (for CI's Swift 6.0).
- `9052b57` The opaque corner fill moved into AppFeature, with tests.
- (this commit) These notes, `FOUNDER_STEPS.md`, `APP_STORE_LISTING.md` §7, PLAN.md, CLAUDE.md, the iOS README.

## Tests

`swift test`: **994 tests in 147 suites pass** (951 before; 43 new, 6 new suites). All run on CI's existing `spm` job, since they are package tests (`#if os(macOS)` where they need AppKit).

| Suite | Tests | What it pins |
|---|---|---|
| `MacSidebarTests` | 11 | A click on empty space keeps the selection and the open lesson; a row closes it; nothing behind the gate; saved threads newest first, empty ones hidden; a saved thread opens in the chat; a thread that can't open falls back (below); deleting the open or another thread; the unit rows' VoiceOver label and numbering; a thread row's mode name, including the betas' `direct`. |
| `ComposerSendRulesTests` | 4 | When the composer sends: text that isn't only spaces and line breaks, or a photo; never mid-reply or while a photo is prepared. Shared with iOS (the send button uses it too). |
| `MacComposerReturnKeyTests` | 4 | Return sends; Shift-Return breaks the line (whatever else is held); Option-Return stays the field's; while an input method composes, Return is the input method's. |
| `MacSnapshotOptionsTests` | 10 | The harness's flags: off without `-MacSnapshot <dir>`, defaults, every flag read, sizes, problems reported (unreadable size, size under the 860 × 600 minimum, …), YES/true/number booleans, the store size, and the opaque corner fill on a synthetic picture. |
| `MacSnapshotScriptTests` | 7 | Reads `mac-snapshots.sh` and `mac-store-screenshots.sh`: every app flag has a value (a bare flag makes AppKit open the next word as a document and no window shows), every `-Mac…` flag is one the app reads, every size / appearance / window parses, the store variant is a Mac App Store size, and the store script accepts exactly the four Mac App Store sizes. Checked by breaking the script on purpose (a bare `-EnterShell`, a misspelt `-MacSnapshotSzie`): both caught, then restored. |
| `MacReleaseConfigTests` | 7 | `project.yml`, `ExportOptionsMac.plist`, `provision.sh` and `release.sh` agree on the bundle id (the iOS one in Release, `.macdev` in Debug) and the profile name; Release signs manually with Apple Distribution and the hardened runtime; the entitlements are exactly the sandbox, network client and user-selected read-only files; the Info.plist's category, encryption, ATS and URL scheme; the privacy manifest is in the target. |

Code changes that came with them:

- `MacShellModel.select(_:)` is the sidebar's selection setter (it was an inline closure).
- **A fix found while writing the tests:** clicking a saved thread that can't open (deleted meanwhile, or saved in the betas' retired `direct` mode, which an iPad-on-Mac container could hold) left the sidebar highlighting that thread while the chat stayed on another. The selection now goes back to the thread the chat shows.
- `MacComposerKeys.returnAction(modifiers:isComposing:)` is the Return-key rule as a pure function; `handleReturn` applies it. `ChatInputBar.canSend(…)` is the send rule as a static function. Behaviour is unchanged.

## CI: the `mac` job (`.github/workflows/ios.yml`)

On `macos-14` with the same `latest-stable` Xcode as the other two jobs (16.2, Swift 6.0, the macOS 15 SDK):

1. `xcodegen generate`.
2. `MercuriusMac`, Debug, `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`.
3. `MercuriusMac`, Release, `generic/platform=macOS` (arm64 + x86_64), unsigned. This compiles the app without its DEBUG code, as the store build will.
4. `scripts/mac-bundle-check.sh` on both bundles.
5. A launch smoke test: `mac-snapshots.sh` with `VARIANTS=min` takes the first-run gate and Today at 860 × 600 (it fits a runner's small screen). It proves the unsigned app starts, makes its window, reaches the gate and quits by itself. The PNGs are uploaded as the `mac-smoke` artifact.

Its unit tests are the package tests above, which the `spm` job runs.

**What I could and couldn't check here.** I ran every step's command locally, on Xcode 26.4:

- the unsigned Debug and Release builds succeeded (Release has x86_64 and arm64);
- both bundle checks passed;
- the smoke test passed.

The job itself hasn't run on GitHub (the branch isn't pushed), so whether CI's Swift 6.0 / macOS 15 SDK compiles the app target is still unproven. To reduce the risk I audited the branch's Swift:

- no `#available` anywhere, and every API it calls exists on macOS 14;
- no Swift 6.1+ syntax (trailing commas in argument lists, `nonisolated(nonsending)`, typed throws…);
- no `Double`·`CGFloat` mixing;
- the pure helpers on SwiftUI views are `nonisolated` (`a544a43`).

`mac-bundle-check.sh <Mercurius.app> debug|release` reads the built bundle. It checks:

- the bundle id for the configuration;
- the version and build number match iOS's;
- the macOS 14 minimum;
- category, encryption, ATS and the URL scheme;
- that the icon and the privacy manifest are compiled in;
- both architectures in Release;
- the sandbox entitlement when the app is signed.

## Release tooling (`ios/scripts/`)

**`asc-api.sh`** (sourced by both scripts) holds the shared App Store Connect plumbing:

- credentials, the ES256 JWT, and API calls that check the HTTP status;
- a missing agreement (HTTP 403 `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`) stops at the first request. It prints Apple's own words and says nothing was changed, who can fix it (the Account Holder) and where (developer.apple.com/account for the Program License Agreement, App Store Connect → Business). Exit 21;
- a refused key exits 20; an unreachable API or a failed read exits 22;
- xcodebuild and altool output is checked for the same refusal.

**`provision.sh --platform mac`** is additive only:

- It reuses the Apple Distribution certificate the iOS releases use. That certificate is in `mercurius-codesign.keychain-db` and is matched to App Store Connect by SHA-1.
- It adds a Mac Installer Distribution certificate if the keychain has none. It never revokes one; if Apple's limit is reached, it says where to revoke one by hand.
- It issues and installs the `Mercurius Mac App Store` profile (MAC_APP_STORE, `.provisionprofile`) for the iOS bundle id.
- It prints the bundle id's platform as App Store Connect reports it. If that says iOS only, it says what to check.
- The iOS path is the same as before. Its keychain set-up and profile function became shared functions.

**`provision.sh --check [--platform mac]`** is read-only (GET requests, no keychain writes). It reports what App Store Connect and this Mac have, and still shows the local half when the API refuses. Today on this Mac:

```
❌ App Store Connect refused the request: a required agreement hasn't
   been accepted (HTTP 403, FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED).
   Apple said: FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED — A required agreement is missing or has expired. — …
   Nothing was created, changed or uploaded.
   …
This Mac:
   keychain mercurius-codesign.keychain-db: present
   Apple Distribution identity: E28F88F8…
   Mac Installer Distribution identity: none (a run creates one)
   profile "Mercurius Mac App Store": not installed (a run creates and installs it)
exit: 21
```

**`release.sh --platform mac`** has the same flags as iOS (`--no-bump`, `--no-upload`, `--allow-dirty`) and runs:

1. archive `MercuriusMac` for generic macOS (universal);
2. export with `ExportOptionsMac.plist` to `Mercurius.pkg`;
3. `xcrun altool --upload-app --type macos`;
4. tag `mac/v<version>-<build>`.

Before bumping anything it runs a preflight. On the Mac path it checks that the profile is installed and that the keychain has both identities; if not, it exits 13 with what is missing and the command that makes it. On both paths it then asks App Store Connect:

- a missing agreement stops an uploading run (exit 21);
- with `--no-upload` it's a warning, and the run goes on to archive and export.

Output goes to `build/release-logs/`.

**`ExportOptionsMac.plist`** is set up like this:

- method `app-store-connect`, the current name of `app-store` (Xcode 15.3 renamed it; the old name still works, and the iOS plist still uses it);
- team TMBPRHZYW2, manual signing;
- `Apple Distribution` + the `Mercurius Mac App Store` profile for the app;
- the `Mac Installer Distribution` selector for the `.pkg`;
- symbols uploaded, destination `export`, Xcode doesn't manage the build number.

**Dry runs:**

- **Mac** (`release.sh --platform mac --no-upload --no-bump`): stops at the preflight, exit 13. The profile and the installer identity are missing, and making them needs the API, which is the 403.
- **iOS** (`release.sh --no-upload --no-bump`): checks that the refactor didn't break the iOS path. The probe warned about the 403, then **archive and export succeeded**: a signed `Mercurius.ipa`, with the installed iOS profiles. I deleted the archive and export afterwards; `ios/build` is inside the iCloud-synced worktree.

## Mac App Store screenshots

`scripts/mac-store-screenshots.sh <dir> [state …]` takes, in store order: `path`, `lesson`, `chat`, `today`, `gate-consent`, `chat-thread`. It runs `mac-snapshots.sh` with `VARIANTS=store`. Each shot is:

- light, isolated, at `STORE_SIZE` points (default 1280 × 800);
- passed through `-MacSnapshotOpaque YES` (corners filled, no alpha);
- checked for one of the four Mac App Store sizes and for no alpha;
- numbered `01-path.png` ….

**Size: 2560 × 1600, not 2880 × 1800.** 2880 × 1800 needs a 1440 × 900-point window. macOS keeps a window within the screen's visible frame, which on this 14-inch MacBook Pro is 1512 × 888 points. I measured what happens instead:

- asked for 1440 × 900, the window came out 1440 × 888;
- resizing it after it's moved off screen gives a blank picture at a fractional scale.

So the harness reports a size that doesn't fit as a problem, and the script fails rather than produce a wrong picture. 2560 × 1600 is one of the four accepted sizes. On a display with at least 900 points of visible height, `STORE_SIZE=1440x900` gives 2880 × 1800.

**No store pictures in this commit.** The Mac's screen was locked for the whole capture window. It slept on 1% battery at 23:31, woke on mains power, and stayed locked; `CGSSessionScreenIsLocked` was true. With the screen locked, the window server draws nothing for the window: every capture came back blank, at a 1.8× scale instead of 2×. That includes a re-run of `path` at 1280 × 800, the size that gave good 2560 × 1600 pictures in step 02.

The script's checks did their job: it rejected those pictures (wrong size). The opaque corner fill is unit-tested on a synthetic picture instead (`MacSnapshotOptionsTests`). The founder runs the script on an unlocked Mac (FOUNDER_STEPS.md, step 6). I couldn't look at the store set, so the cautions in `APP_STORE_LISTING.md` §7.2 come from the step 02 pictures:

- the glass toolbar band shows the thread's text behind the mode picker in `chat-thread`;
- `chat-thread`'s seeded demo replies explain directly, not Socratically;
- a fresh install shows 0/4 per unit.

## Docs

- `docs/APP_STORE_LISTING.md` §7 covers:
  - what the macOS version shares with iOS (name, subtitle, category, age rating, privacy label, price) and what is its own;
  - a Mac description (2,138 characters, measured): click rather than tap, right-click to report, a "Made for the Mac" block, and the sentence that a Mac and an iPhone keep separate progress;
  - promotional text and keywords unchanged;
  - screenshot sizes, states, captions and cautions;
  - Mac App Review notes;
  - a checklist.
- In the review notes, one difference from iOS matters. On a Mac, deleting an app doesn't delete its data, so the under-13 stop survives a reinstall; the notes ask the reviewer to use another macOS user account if they try it. The crisis section says where the selectable numbers appear: unit-check and quiz crisis responses, and Help → Get Help. The AI-limits step gives them as plain text.
- `docs/mac-app/FOUNDER_STEPS.md` lists the App Store Connect steps for the universal purchase:
  1. accept the agreement;
  2. check that the App ID covers macOS;
  3. `provision.sh --platform mac`;
  4. add the macOS platform to the record;
  5. upload to TestFlight and rehearse, including what happens to an iPad-on-Mac install;
  6. fill in the version page;
  7. submit.

  It also lists the decisions waiting on the founder.
- `STORE_AND_HIG.md`, which the brief named as the source for those steps, doesn't exist in the repo or on this Mac (searched by name with Spotlight and `find`). The steps are written from Apple's documentation instead, and say so.
- PLAN.md, CLAUDE.md (release tooling, CI) and `ios/README.md` are updated.

## iOS doesn't regress

- `build-for-testing` of the `Mercurius` scheme succeeds on the final code (iPhone 16 simulator, iOS 26.4).
- 18 of 18 UI-test anchors pass, no reruns, on the build of `97629d3`:
  - boot, the tab bar, the chat header's Home and Settings, the starter prompts;
  - the mode pills and the first-tap / already-seen mode sheets;
  - the empty-chat hint;
  - Settings' Appearance section, its feedback and How it teaches rows, and the delete-failure device-only reset;
  - Home's next stop and the curriculum's units;
  - the first-run gate, the consent sentence, under-13, Not now, and the existing-install gate.

  The later commits change no iOS behaviour: `a544a43` adds `nonisolated` to two pure helpers, and `9052b57` touches DEBUG Mac code only.
- The iOS release path archived and exported (above).
- No snapshot record runs. I didn't run the full UI suite.

## Skipped, and why

- **Provisioning and uploading:** blocked by the 403. Only the Account Holder can accept the agreement. A real `provision.sh` run would also create a certificate and a profile on the team, which is the founder's call.
- **2880 × 1800 screenshots:** this display can't hold the window (above).
- **The store screenshots themselves:** the screen was locked.
- **A Mac UI-test target.** It would drive the real pointer and keyboard of the Mac it runs on, and macOS asks an administrator to allow UI automation. It belongs on CI, not on the founder's Mac.
- **The `X-Mercurius-Client` header:** not in this step's brief. It's still a recommendation in PLAN.md, and the server change that would read it is separate.
- **Running the CI job on GitHub:** the branch isn't pushed.
