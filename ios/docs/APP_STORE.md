# App Store shipping checklist

Tracks what's already in the repo, what needs manual work per submission, and what needs action only before the very first review.

_Last touched: Phase 4j._

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
| Privacy manifest | ✅ | `Mercurius/Resources/PrivacyInfo.xcprivacy` — declares no tracking, no tracking domains, two collected data types (user ID + other user content, both for app functionality, neither linked/tracked), one required-reason API (UserDefaults / `CA92.1`). |
| Privacy policy URL | ⬜ | Needs a hosted URL for App Store Connect. Draft at `PRIVACY_POLICY.md` below. |
| Support URL | ⬜ | Needs a public page (e.g. `mayoailiteracy.com/support`). |
| Screenshots | ⬜ | Required sizes in §Screenshots below. Not committed to the repo — uploaded directly to App Store Connect. |
| App Review notes | ⬜ | Not a file. Paste into App Store Connect per submission. See §Reviewer notes. |
| Development team | ⬜ | `DEVELOPMENT_TEAM` is empty in `project.yml`. Fill in before archiving for distribution. |

## Data types we declare

Every entry in `PrivacyInfo.xcprivacy` must also appear in the App Store Connect privacy nutrition label. Make sure the two agree:

- **User ID** — device-scoped random session id kept in Keychain, sent to the Mercurius backend with each request so conversations stitch together across app launches. Not linked to any identity. Not used for tracking.
- **Other User Content** — the text of chat messages, sent to the backend so Claude can respond. Not linked. Not tracking.

## Required-reason APIs we declare

Only one in our own code:

- **UserDefaults** (`NSPrivacyAccessedAPICategoryUserDefaults`), reason `CA92.1` — persisting theme preference and completed-lesson set on-device.

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

3–5 screenshots per size is the usual submission bundle. Suggested shots that reflect what the app actually does:

1. Empty chat (light mode) — shows the tutor's framing + starter prompts
2. Mid-conversation chat with a streamed assistant reply
3. Quiz sheet mid-session (loaded state)
4. Curriculum tab, first unit expanded
5. Report card sheet with real scores

## Reviewer notes (paste into App Store Connect)

> Mercurius AI is the native companion to the web-based Mayo AI Literacy Club tutor. It uses a small device-scoped session id (random 32-char string, stored in Keychain) to stitch conversations together across launches. There is no user account, no login, no ad network, and no third-party analytics. Chat content is sent to our own backend (mercurius-chatbot-production.up.railway.app) which proxies through the Anthropic API; the backend logs interactions against the session id only.
>
> To exercise the app: launch → tap one of the four starter prompts on the Chat tab → observe a streamed response → switch to the Curriculum tab → tap any unit → tap Start on a lesson. The Club tab surfaces schedule + blog content that lives on our public site at mayoailiteracy.com.

## Privacy policy template

Paste into your hosted privacy-policy page. Keep it aligned with `PrivacyInfo.xcprivacy` and the App Store nutrition label — any drift becomes a review rejection.

> **Mercurius AI — Privacy Policy**
>
> *Last updated: [DATE]*
>
> Mercurius AI is an AI literacy tutor built by the Mayo AI Literacy Club. We collect the minimum needed to make the tutor work.
>
> **What we collect**
> - A device-scoped session identifier (32-char random string) kept in Keychain. This survives reinstalls on the same device so your streak and chat history stay continuous. It is not linked to your identity.
> - The text of messages you send, and the responses the tutor generates. These are sent to our backend (Railway) and forwarded to Anthropic's Claude API so the tutor can respond.
>
> **What we do not collect**
> - Names, email addresses, phone numbers, or other contact info.
> - Location.
> - Advertising identifiers.
> - Any third-party analytics data. There are no trackers.
>
> **How we use data**
> - Only to make the tutor function: answer your questions, keep your conversation coherent across sessions, and display your own progress on the leaderboard.
>
> **How long we keep data**
> - Session identifiers and associated message logs are retained for the lifetime of the session record on our backend. You can reset everything from Settings → Start Over.
>
> **Children**
> - The tutor is designed for high-school-aged users and up. We do not knowingly collect additional identifying information from children under 13.
>
> **Contact**
> - mayoailiteracy.com — send questions to [CONTACT EMAIL].

## Version-bump checklist (each submission)

1. Bump `MARKETING_VERSION` and/or `CURRENT_PROJECT_VERSION` in `project.yml`.
2. `xcodegen generate`.
3. Run the full test suite: `./scripts/coverage.sh all` (or just `swift test` + `xcodebuild test`).
4. Archive + validate as above.
5. Review privacy nutrition label in App Store Connect — should match `PrivacyInfo.xcprivacy`.
6. Capture / refresh screenshots if any UI changed.
7. Upload via Xcode's Organizer or `xcrun altool --upload-app` once you're happy.
