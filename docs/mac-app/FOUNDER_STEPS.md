# Mercurius for Mac: what the founder does

The Mac app ships on the Mac App Store as a **universal purchase** with the
iPhone/iPad app: the same bundle id, `com.mayoailiteracy.mercurius.native`,
added as a macOS platform to the existing **Mercurius AI** record in App Store
Connect (app id 6773192313). Nothing here needs a new app record, a new
bundle id or a price change. The scripts do the signing and the upload; the
steps below are the ones only the Account Holder or an App Store Connect
admin can do, in order.

The brief for this step pointed to a `STORE_AND_HIG.md` for these steps. No
such file exists in the repo or on this Mac, so they are written here from
Apple's App Store Connect and Developer documentation as of October 2026.
Labels in Apple's web pages move; where one differs, the step's intent is
what matters.

## 1. Accept the pending agreement (blocks everything else)

**Status on 2026-10-20:** the App Store Connect API answers every request with
HTTP 403 `FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` ("A required
agreement is missing or has expired"). Until it's accepted, nothing can be
provisioned or uploaded, for iOS or Mac. `./scripts/provision.sh --check
--platform mac` shows it; both scripts now stop at the first request and say
this.

Only the team's **Account Holder** can accept:

1. Sign in at <https://developer.apple.com/account>. If a banner asks you to
   review an updated Apple Developer Program License Agreement, accept it.
2. Sign in at <https://appstoreconnect.apple.com> → **Business** (Agreements,
   Tax, and Banking). Accept any agreement shown as pending or expired.
3. Wait a few minutes, then run `cd ios && ./scripts/provision.sh --check
   --platform mac`. It should list the bundle id, certificates and profiles
   instead of the 403.

## 2. Make sure the App ID can be used on macOS

<https://developer.apple.com/account/resources/identifiers/list> → open
`com.mayoailiteracy.mercurius.native`. Universal purchase needs this one App
ID for both platforms. `provision.sh --check` prints the platform App Store
Connect reports for it. If it says `IOS` and step 3 is refused with a
platform error, enable macOS for the identifier here (identifiers registered
in the portal in recent years usually cover every platform already).

Capabilities: none are needed. The Mac app uses only the sandbox
(network client, a user-picked image file), which are entitlements in the
build, not App ID capabilities.

## 3. Make the Mac signing assets (one command)

```bash
cd ios
./scripts/provision.sh --check --platform mac   # read-only: what exists
./scripts/provision.sh --platform mac           # makes what's missing
```

It reuses the **Apple Distribution** certificate the iOS releases already use
(one certificate signs apps for every platform; it's in
`mercurius-codesign.keychain-db` on this Mac), adds a **Mac Installer
Distribution** certificate (it signs the `.pkg` the Mac App Store takes), and
creates the **"Mercurius Mac App Store"** provisioning profile. It never
revokes or deletes a certificate, and doesn't touch the iOS profiles.

Apple limits how many installer certificates a team can have. If it says the
limit is reached, revoke an unused one at
<https://developer.apple.com/account/resources/certificates/list> and run it
again.

## 4. Add macOS to the App Store Connect record

App Store Connect → **Apps** → **Mercurius AI**. In the left sidebar, next to
**iOS App**, use **Add Platform** (the **+**) and choose **macOS**. Use version
**2.3.0** (it doesn't have to match iOS; matching keeps support simple).

Because the bundle id is the same, this *is* the universal purchase: anyone
who has the iPhone/iPad app sees the Mac app as theirs on the Mac App Store
(it's free either way). There is no separate switch to turn on.

Shared with iOS, nothing to redo: the name and subtitle, category, age rating
(13+ via the minimum age), the App Privacy label, the privacy policy URL,
price (free) and territories. The Mac app collects the same data for the same
purposes and ships the same privacy manifest (`docs/APP_STORE_LISTING.md` §2
and §3 still hold).

Leave **Pricing and Availability → "iPhone and iPad Apps on Apple Silicon
Macs"** unchecked, as the listing pack already says: Macs get the native app.

## 5. Upload a Mac build to TestFlight

```bash
cd ios
./scripts/release.sh --platform mac --no-upload   # archive + export only, as a check
./scripts/release.sh --platform mac               # bump, archive, export, upload
```

The build appears under **TestFlight → macOS** after Apple processes it
(10–20 minutes). The build number is shared with iOS (`project.yml`), so a
Mac upload skips a number on iOS and vice versa; App Store Connect only needs
each platform's numbers to go up. Commit the bump and push the tag it prints
(`mac/v2.3.0-<build>`).

Install it on a Mac through the **TestFlight** app for Mac and rehearse:

- the first-run gate (age pop-up, disclosure, limits), then a lesson and a chat;
- right-click a reply → **Report response**;
- **Mercurius → Settings… → Privacy → Delete My Data & Start Over…**;
- **Help → Mercurius Help → Get Help**: the crisis numbers as selectable text;
- a reminder, if you turn one on (macOS asks for notification permission then).

**On a Mac that has the iPad app installed** (yours does, in
`/Applications/Mercurius.app`), check what happens to its chats and progress
when the Mac app replaces it. Our reading (PLAN.md, "Open questions") is that
the Mac app sees the iPad app's local data but starts a **new anonymous
session**, because it can't read the iPad app's session id from the
keychain. TestFlight is the first place this can be seen for real.

## 6. Fill in the macOS version page

App Store Connect → Mercurius AI → **macOS App** → 2.3.0. Everything to paste
is in `docs/APP_STORE_LISTING.md` **§7**:

- description, keywords and promotional text (§7.1);
- screenshots, 16:10 (§7.2): `scripts/mac-store-screenshots.sh <dir>` makes
  2560 × 1600 PNGs on this Mac. **Unlock the Mac first** (a locked screen
  gives blank pictures) and look at each one before uploading;
- Support and Marketing URLs (the iOS ones);
- App Review Information: contact details, sign-in "No", and the Mac notes
  (§7.3);
- the build from step 5.

## 7. Submit

**Add for Review** → **Submit**. Choose **Manually release this version**, as
for iOS. The Mac version is reviewed on its own; it can go out before or
after the next iOS version.

## Decisions waiting on you

- **Progress doesn't follow a student between devices.** There are no
  accounts, and a student's Mac and iPhone are separate anonymous sessions
  with separate progress, streaks and chats. The Mac description and the
  review notes say so. Changing it means accounts or a pairing scheme: a
  product decision, not a Mac task.
- **The reviewer and the under-13 stop.** On a Mac, deleting an app doesn't
  delete its data, so the 7-day under-13 stop survives a reinstall. The Mac
  review notes ask the reviewer to continue in another macOS user account if
  they try it. Keep or reword that sentence (§7.3).
- **Debug bundle id.** Debug builds use `….native.macdev` so a development
  run never shares the installed app's data folder. Release is unaffected.
  Keep it, or change one line in `project.yml`.
- **Client header.** The server can't tell a Mac from an iPhone. PLAN.md
  recommends an additive `X-Mercurius-Client: macos/2.3.0 (16)` request
  header, read by a later server change. Not done yet.
- **Store screenshots at 2880 × 1800** need a display with at least 900
  points of visible height (an external monitor, or a 16-inch MacBook Pro):
  `STORE_SIZE=1440x900 scripts/mac-store-screenshots.sh <dir>`. 2560 × 1600
  is also an accepted size, so this is optional.
