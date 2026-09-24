# App Store shipping checklist

Tracks what's already in the repo, what needs manual work per submission, and what needs action only before the very first review.

_Last touched: 2.3.0 (build 15) — product interaction (synced lesson progress) added to the nutrition label, on top of build 14's photos, 13+ age rating and first-run disclosure._

## Status of each gate

| Gate | State | Notes |
|---|---|---|
| Bundle identifier | ✅ | `com.mayoailiteracy.mercurius.native` — reserve this in App Store Connect before the first upload. |
| Display name | ✅ | `Mercurius` in Info.plist (`CFBundleDisplayName`). |
| Version / build | ✅ | Driven by `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`. Bump both for each submission. |
| 1024×1024 App Icon | ✅ | `Mercurius/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Single-size + Xcode auto-derive. |
| Launch screen | ✅ | `UILaunchScreen` with `UIColorName: LaunchBackground`. |
| Orientation lock | ✅ | Portrait only (`UIInterfaceOrientationPortrait`). |
| App Transport Security | ✅ | `NSAllowsArbitraryLoads: false` — strict HTTPS only. |
| Encryption declaration | ✅ | `ITSAppUsesNonExemptEncryption: false` — skips the export-compliance questionnaire each submission. |
| App Store category | ✅ | `LSApplicationCategoryType: public.app-category.education` |
| Privacy manifest | ✅ | `Mercurius/Resources/PrivacyInfo.xcprivacy` — declares no tracking, no tracking domains, four collected data types (user ID, other user content, photos or videos — app functionality; product interaction — app functionality + analytics; none linked/tracked), one required-reason API (UserDefaults / `CA92.1`). |
| Age rating | ✅ | 13+ in App Store Connect. The app asks for age on first run and stops under-13 users at a terminal screen; see §Age rating and first-run disclosure. |
| Privacy policy URL | ⬜ | Needs a hosted URL for App Store Connect. Draft at `PRIVACY_POLICY.md` below. |
| Support URL | ⬜ | Needs a public page (e.g. `mayoailiteracy.com/support`). |
| Screenshots | ⬜ | Required sizes in §Screenshots below. Not committed to the repo — uploaded directly to App Store Connect. |
| App Review notes | ⬜ | Not a file. Paste into App Store Connect per submission. See §Reviewer notes. |
| Development team | ⬜ | `DEVELOPMENT_TEAM` is empty in `project.yml`. Fill in before archiving for distribution. |

## Data types we declare

Every entry in `PrivacyInfo.xcprivacy` must also appear in the App Store Connect privacy nutrition label. Make sure the two agree:

- **User ID** — device-scoped random session id kept in Keychain, sent to the Mercurius backend with each request so conversations stitch together across app launches. Not linked to any identity. Not used for tracking.
- **Other User Content** — the text of chat messages, sent to the backend so Claude can respond. Not linked. Not tracking.
- **Photos or Videos** — a photo the student chooses to attach to a chat message (system `PhotosPicker`, so no photo-library permission string is needed). Uploaded to the backend and forwarded to Anthropic so Claude can respond about it. App functionality only. Not linked. Not tracking. _Added in 2.3.0 — set it in the App Store Connect label before submitting build 14._
- **Product Interaction** (Usage Data) — which lessons are finished or mastered, synced to the backend under the session id (`GET`/`PUT /api/progress`) so progress survives a reinstall, plus the lesson start/finish rows the backend keeps to see whether lessons work. App functionality and analytics. Not linked. Not tracking. _Added for build 15 — set it in the App Store Connect label before submitting._

Not a data type: the age picked on first run. It is used once to gate the flow and is never persisted or logged, so it does not appear in the manifest or the label.

## Age rating and first-run disclosure

Decided for 2.3.0:

- **Rating: 13+.** The first-run flow asks "How old are you?" (12 or younger, 13 … 18 or older). Under 13 lands on a terminal screen with no way forward; the age is not stored, so there is nothing to delete and nothing new on the label. Existing installs (onboarding already finished) see only the gate — age, disclosure, limits — once, then Home. The flow is owned by `AppFeature` (`ConsentGate.currentVersion`, UserDefaults key `consentVersion`); bumping the version re-shows the gate on the next launch.
- **The disclosure names Anthropic/Claude.** Before any network call, the student is told that messages and attached photos go to our backend and are forwarded to Anthropic's Claude, and must tick a box to continue. "Not now" pauses on a screen that offers to review the disclosure again; nothing is sent while paused. Keep this copy, the hosted privacy policy, the reviewer notes below, and the nutrition label saying the same thing — drift between them is a review rejection.
- **Limits screen.** After agreeing, a short "what Merc can't do" screen (no medical/legal advice, may be wrong, crisis resources) must be acknowledged before the app opens.

The UI tests in `MercuriusUITests` walk every branch of the gate with the `onboarding.*` accessibility identifiers; every other test bypasses it with `-consentVersion 1`.

## Required-reason APIs we declare

Only one in our own code:

- **UserDefaults** (`NSPrivacyAccessedAPICategoryUserDefaults`), reason `CA92.1` — persisting theme preference, the completed-lesson set, streak, reminder settings, last-activity time and the review-prompt counter on-device.

Keychain, SwiftData, and URLSession internals that Apple frameworks call do not need app-level declarations — those are Apple's responsibility.

## Archive + validate (dry run, no upload)

```bash
cd ios
xcodegen generate
xcodebuild \
  -project Mercurius.xcodeproj \
  -scheme Mercurius \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Mercurius.xcarchive \
  archive
```

Export an `.ipa` for local inspection:

```bash
cat > build/export-options.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>development</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

xcodebuild \
  -exportArchive \
  -archivePath build/Mercurius.xcarchive \
  -exportOptionsPlist build/export-options.plist \
  -exportPath build/export
```

Validate the archive against App Store Connect's rules (requires a signed-in Apple ID in Xcode's Accounts preferences; does **not** upload):

```bash
xcrun altool --validate-app \
  -f build/export/Mercurius.ipa \
  -t ios \
  --apiKey $ASC_API_KEY_ID \
  --apiIssuer $ASC_API_ISSUER_ID
```

Alternative notary-style check that doesn't need ASC credentials:

```bash
xcrun notarytool submit build/export/Mercurius.ipa \
  --dry-run \
  --wait
```

## Screenshots

App Store Connect accepts one "required" device size per supported family; all other sizes are optional but recommended. Capture via iOS simulator at these exact screen sizes (Xcode → Simulator → Screenshot):

| Family | Simulator | Screen points | Pixel size (Retina) |
|---|---|---|---|
| iPhone 6.7″ (required) | iPhone 16 Pro Max | 430 × 932 | 1290 × 2796 |
| iPhone 6.1″ (required) | iPhone 16 | 393 × 852 | 1179 × 2556 |
| iPhone 5.5″ (legacy) | iPhone 8 Plus | 414 × 736 | 1242 × 2208 |
| iPad 13″ (if iPad supported) | iPad Pro 13-inch (M4) | 1024 × 1366 | 2048 × 2732 |

3–5 screenshots per size is the usual submission bundle. `./scripts/screenshots.sh` captures the network-free ones from a seeded app (`00-home`, `01-chat`, `02-settings`, `03-curriculum`, `04-history`); the rest are captured by hand. Suggested shots that reflect what the app actually does:

1. Home — Merc with the next-stop button ("Start Lesson 1 …") and "Chat with Merc" (`00-home`)
2. Mid-conversation chat with a streamed assistant reply (`01-chat`, seeded)
3. Curriculum tab — the learning path (`03-curriculum`)
4. Lesson complete — the celebration overlay with its share button (DEBUG build: `-LessonPreview -LessonSkipIntro -ForceCelebrate`)
5. Quiz sheet mid-session (loaded state; needs the live backend)

`02-settings` changed in build 15: About now lists "How Mercurius teaches" and "Send feedback". Re-capture it if Settings is in the bundle.

## Reviewer notes (paste into App Store Connect)

> Mercurius AI is the native companion to the web-based Mayo AI Literacy Club tutor. It uses a small device-scoped session id (random 32-char string, stored in Keychain) to stitch conversations together across launches. There is no user account, no login, no ad network, and no third-party analytics. Chat content and any photo the student attaches are sent to our own backend (mercurius-chatbot-production.up.railway.app) which proxies through the Anthropic API; the backend logs interactions against the session id only, and keeps the student's lesson progress under the same id so it survives a reinstall.
>
> On first launch the app asks for the user's age (13+; under 13 is stopped and nothing is stored), shows a disclosure that messages and photos are forwarded to Anthropic's Claude, and asks for agreement before any request is made. To exercise the app on a fresh install: launch → tap Continue on the Meet Merc screen → spin the age wheel to 13 or older (it opens on "12 or younger") → tap Continue → turn on the "I understand my messages and photos are sent to Anthropic's Claude…" switch (Agree and continue stays disabled until it is on) → tap Agree and continue → tap Got it on the "What Merc can't do" screen → on "Your path" tap Just chat instead → tap one of the four starter prompts on the Chat tab → observe a streamed reply. The app may ask for notification permission for weekly lesson reminders (Wednesday and Sunday) and an optional daily streak reminder; declining leaves everything else working.

## Privacy policy

The hosted policy — `marketing/privacy.html` in this repo, served at trymercurius.com/privacy and linked from the in-app disclosure — is the source of truth. Do not keep a second copy here; it drifted last time (it still said logs were kept "for the lifetime of the session record" and pointed at a "Start Over" button that no longer exists).

What the hosted policy must keep saying, because the app, `PrivacyInfo.xcprivacy` and the nutrition label say it too (drift is a review rejection):

- Retention: messages 90 days, photos 24 hours, reports 180 days, usage/lesson rows 400 days; sessions idle for 365 days are erased.
- Deletion: the in-app "Delete my data & start over" (Settings → Privacy) erases the session on the server under the old id, then rotates the id on the device. "Reset this device only" is the offline fallback and leaves server data in place until it ages out.
- Under 13 is stopped on-device and the age is never stored; the disclosure names Anthropic's Claude as the model provider.
- Lesson progress (finished and mastered lessons) is kept on the server under the session id as well as on the phone, for as long as the session exists; deleting the data or the session's idle purge removes it. _New for build 15 — `marketing/privacy.html` still says the progress checklist lives only on the phone._

## Version-bump checklist (each submission)

1. Bump `MARKETING_VERSION` and/or `CURRENT_PROJECT_VERSION` in `project.yml`.
2. `xcodegen generate`.
3. Run the full test suite: `./scripts/coverage.sh all` (or just `swift test` + `xcodebuild test`).
4. Archive + validate as above.
5. Review privacy nutrition label in App Store Connect — should match `PrivacyInfo.xcprivacy` (User ID, Other User Content, Photos or Videos, Product Interaction). Confirm the age rating is still 13+.
6. Capture / refresh screenshots if any UI changed.
7. Upload via Xcode's Organizer or `xcrun altool --upload-app` once you're happy.
