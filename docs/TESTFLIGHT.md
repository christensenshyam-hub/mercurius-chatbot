# TestFlight launch playbook

Once-through guide for getting Mercurius AI into TestFlight. Numbered
so you can resume mid-way if you stop. Anything that says "I'll do it"
means I already did it — that step is done.

## 0. Pre-flight (already done)

- [x] Apple Developer account (Kevin Nicholas Christensen)
- [x] **Team ID:** `TMBPRHZYW2` — wired into `ios/project.yml` and
      `ios/scripts/ExportOptions.plist`
- [x] Bundle identifier: `com.mayoailiteracy.mercurius.native`
- [x] App icon (Mercurius brand mark, 1024×1024, no alpha)
- [x] Encryption-exemption declared in `Info.plist`
      (`ITSAppUsesNonExemptEncryption: false`)
- [x] App category set to `public.app-category.education`
- [x] Marketing site live at `marketing/` for the privacy URL
- [x] Archive + export script: `ios/scripts/release.sh`

## 1. Confirm App ID is registered

In <https://developer.apple.com/account/resources/identifiers/list>:

Look for `com.mayoailiteracy.mercurius.native`. If it's already there,
skip. If not:

- Click **+** → App IDs → App
- Description: `Mercurius AI`
- Bundle ID: Explicit → `com.mayoailiteracy.mercurius.native`
- Capabilities: leave defaults
- Continue → Register

## 2. Create the App Store Connect app record

In <https://appstoreconnect.apple.com/apps>:

- Click **+** (top-left) → **New App**
- Platforms: **iOS**
- Name: **Mercurius AI**
- Primary Language: **English (U.S.)**
- Bundle ID: **com.mayoailiteracy.mercurius.native** (from dropdown —
  must match the App ID from step 1)
- SKU: **mercurius-ai-001** (or anything unique to your account)
- User Access: **Full Access**

## 3. One-time: provision the Distribution cert + profile

Before the very first archive (and only the first time), bootstrap the
Apple Distribution certificate and the "Mercurius App Store"
provisioning profile via the App Store Connect API:

```bash
cd ios
./scripts/provision.sh
```

What this does (so you know what's on your machine after):
1. Creates a dedicated `mercurius-codesign.keychain-db` keychain so
   codesign can use the private key non-interactively (no GUI prompts).
2. Generates a CSR, posts it to `/v1/certificates`, and imports the
   returned Apple Distribution cert + key into the dedicated keychain.
3. Creates an `IOS_APP_STORE` profile named "Mercurius App Store" tied
   to the cert and the bundle id, then installs the `.mobileprovision`
   into `~/Library/MobileDevice/Provisioning Profiles/`.

This whole dance exists because brand-new Apple Developer teams have
zero registered devices, and Xcode's automatic signing refuses to
archive without first being able to issue a *Development* profile (which
needs at least one device). Manual signing with a pre-created
Distribution profile sidesteps the deadlock entirely. The script is
idempotent — re-running it reuses what's already there, and rotates
the cert if the local private key has gone missing.

## 4. Archive + upload

From the repo root:

```bash
cd ios
./scripts/release.sh
```

The script:
1. Bumps `CURRENT_PROJECT_VERSION` by +1
2. Regenerates the `.xcodeproj` so the bump lands in the build
3. Unlocks the dedicated codesigning keychain (from `provision.sh`)
4. Cleans previous archives
5. Builds a signed Release archive to `ios/build/Mercurius.xcarchive`
6. Exports the signed `.ipa` to `ios/build/export/`
7. Uploads the `.ipa` to App Store Connect via `xcrun altool` and the
   App Store Connect API key

Apple processes the build (~10–20 minutes). It'll appear in
App Store Connect → Apps → Mercurius AI → **TestFlight** tab.

## 5. Fill in TestFlight Beta info

When you go to the TestFlight tab the first time, Apple asks for:

### App Information
- **Privacy Policy URL:** `https://trymercurius.com/privacy.html`
  *(or wherever you host `marketing/` — local IP if you're previewing,
  but real URL needed for actual external testing)*
- **First Name / Last Name:** your contact info on file
- **Email:** your beta-feedback inbox (or just your address)
- **Phone:** optional

### What to Test (this is the description testers see)

```
Mercurius AI is an AI literacy tutor for high school students. Beta build —
we're looking for feedback on:

• Onboarding clarity: does the 7-step tutorial feel useful or skippable?
• Response length: do replies feel snappy, or still too long?
• Mode behavior: try Socratic vs. Debate vs. Discussion — do they feel
  distinct?
• "Explain more" button: tap it after any reply; does the follow-up feel
  earned or repetitive?
• Anything that crashes, freezes, or feels broken.

You can email beta@trymercurius.com with feedback at any time, or use
TestFlight's "Send Beta Feedback" feature directly in the app.
```

### Beta App Description

```
Mercurius AI helps learners ask better questions, challenge ideas, and
build real understanding in the age of artificial intelligence.

Guided, not given. Mercurius asks questions back instead of handing you
the answer — and is honest about what it doesn't know.
```

### License Agreement

Default Apple beta license is fine for now.

## 6. Add internal testers

Internal testers are people on your developer team. They get instant
access — no Apple Beta Review needed.

In TestFlight → Internal Testing:
- Click **+** next to "Internal Testers"
- Create a group: `Core team`
- Add yourself + anyone else on the team
- Select the build → Save

They get an email with a TestFlight invite link. Install the
TestFlight app from the App Store, redeem the link, and Mercurius
shows up there.

## 7. Add external testers (when ready)

External testers can be anyone — up to 10,000. Requires a quick
Apple Beta App Review (~24–48 hours, sometimes faster).

In TestFlight → External Testing:
- Click **+** → create a group: `Beta`
- Add testers by email (one-by-one) OR get a Public Link (anyone
  can sign up)
- Select the build → Submit for review

When review approves, testers get the invite.

## 8. After the first build

Every subsequent build:
```bash
cd ios && ./scripts/release.sh
```
The build number auto-bumps so you don't hit "build version already
exists" errors. `provision.sh` does not need to be re-run unless the
Distribution cert or profile gets revoked / expires.

External testers see new builds automatically once they're approved.
The first build in a group requires review; minor follow-ups usually
don't.

---

## Troubleshooting

**"No signing certificate found"** — first run? Xcode needs to
generate one. Open `ios/Mercurius.xcodeproj`, go to the Signing &
Capabilities tab on the Mercurius target, and let Xcode prompt you
to grant access to your Apple account. After that, the script
handles it via `-allowProvisioningUpdates`.

**"ITMS-90183: Invalid Code Signing Entitlements"** — usually means
the App ID's capabilities don't match what the app declares. Check
that the App ID in step 1 has the same capabilities as
`ios/project.yml` (which has none beyond the defaults).

**"Missing privacy URL"** in App Store Connect — you set the URL in
the wrong tab. It lives under TestFlight → App Information →
Privacy Policy URL, NOT under the App Privacy questionnaire (that's
for the production App Store listing).

**"This build is processed but doesn't appear"** — wait 20 minutes.
If it still doesn't appear, check your email — App Store Connect
emails you about processing errors (most commonly missing
`ITSAppUsesNonExemptEncryption`, which we already declared).
