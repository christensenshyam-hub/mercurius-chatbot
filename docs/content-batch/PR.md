# Content and docs: privacy, support and playbook fixes (October 2026 audit, Batch 2)

Branch `fix/content-docs-2026-10`, from main `720dbac`. This
covers Batch 2 of the October 2026 audit: AUD-06, AUD-56, AUD-57, AUD-55,
AUD-53 (content half), AUD-59, AUD-58 and AUD-60. It also takes in the
review of the first pass.

Privacy wording is a public commitment. **Approve every sentence in
"Changed public sentences" before you merge.**

## Merge gate: the TestFlight link is closed

The last commit, "Site: beta CTAs to /get, gated on an open TestFlight
link", points every "get the app" button at `trymercurius.com/get`. On
2026-10-19 at 03:06 UTC that link was a dead end:

- `/get` → 302 → `https://testflight.apple.com/join/3ujBtDsa`.
- That page says "This beta isn't accepting any new testers right now."
  The app name isn't on it, and its install steps are switched off
  (`showSteps = false`).
- The App Store still sells 2.0.0, rated 9+ (iTunes lookup for id
  6773192313).

**Merge the last commit only when this prints `0`:**

```bash
curl -sL https://testflight.apple.com/join/3ujBtDsa | grep -cE "accepting any new testers|beta is full"
```

It printed `1` on 2026-10-19. The check the review suggested, `grep -c
"isn't accepting"`, prints `0` even while the beta is closed, because
Apple writes the apostrophe as `&#39;`. Also open trymercurius.com/get on
an iPhone and check that it offers to join the beta.

You have two ways through:

1. **Reopen the beta, then merge everything.** In App Store Connect, open
   the app → TestFlight → the external group. Turn the public link on and
   raise the tester limit if it's full. Make sure a 2.3 build that passed
   Beta App Review (build 16) is in the group. Run the check, then merge.
2. **Keep the beta closed and merge without the last commit.** Ask Claude
   to move it to its own branch and PR, or merge everything and then
   `git revert` it. The privacy, support and docs fixes don't depend on it.
   Nothing they say sends anyone to `/get`, and the runbook offers `/get`
   only after the check above passes.

This also affects the club: the playbook and poster send students to
`/get`.

## Commits

| # | Commit | What it does |
|---|---|---|
| 1 | Site + docs: privacy accuracy, deletion runbook, pilot playbook | The privacy, support and playbook wording, the deletion runbook and this file. Store buttons unchanged. |
| 2 | Site: beta CTAs to /get, gated on an open TestFlight link | All of AUD-06's CTA changes, plus the `/get` option for older app versions on the privacy and support pages. |

The first commit changes only the privacy and support wording and the
docs. The second commit is the whole CTA change, so it can be held or
reverted on its own.

## Changes by AUD id

- **AUD-06 (high): CTAs sell 2.0.0.** The last commit does three things while 2.3
  is in TestFlight:
  - Every header pill on the 9 pages, plus the homepage hero, the end of
    the lesson replay and the final CTA, becomes a plain "Get the app
    (beta)" button to `/get`.
  - The Smart App Banner meta tag is commented out on all 9 pages.
  - The replay generator, its check and its spec now match.

  The privacy page's parents section now says the age check starts with
  2.3 and that earlier versions don't ask. That part is in the first commit, so
  it ships either way.
- **AUD-56: photo reply and Anthropic retention.** The privacy page says
  Merc's reply about a photo is part of the chat and kept 90 days. The
  Anthropic entry now gives Anthropic's published retention, with a
  source. There is a FOUNDER-TODO to confirm we have no other agreement.
- **AUD-57: "not linked".** The page no longer says "not linked to you"
  or "linked only".
  - The heading is now What "linked to a random ID" means in practice.
  - New lead sentence: "What we keep is filed under a random ID, never
    your name or an account. Usage rows also carry the scrambled network
    address described above."
  - `APP_STORE_LISTING.md` §3 now says Linked = Yes and quotes the new
    sentence.
- **AUD-55: deleting your data on a version before 2.3.**
  - The privacy and support pages say versions before 2.3 show only 8
    characters and ask you to send those.
  - New `docs/PRIVACY_DELETION_RUNBOOK.md` handles a full ID with `curl -X
    DELETE`. For a prefix of 8 or more characters, it runs a read-only SQL
    lookup and erases only when exactly one session matches, then logs
    the date.
  - `DEPLOY.md` points to the runbook.
- **AUD-53 (content half): parent of a blocked child.** A new
  privacy-page paragraph covers this. Runbook section C covers the case
  with no ID.
- **AUD-59: classroom network errors.** The playbook's §2 "When phones get
  stuck: the network rule" quotes every 2.3.0 (16) error string and the
  server's refusal messages. §1 and the §9 8:10 check point to it.
- **AUD-58: feedback form.** A §4 checklist line, and the §9 line, say:
  add Google Forms to the privacy page before `/feedback` points at the
  form.
- **AUD-60: progress and a new phone.** A new support FAQ item and the
  playbook's "When a student's path is gone" now say:
  - the session ID stays with the phone;
  - a restore from a backup may bring the lesson list back;
  - erase the old data before you switch.

  The privacy page adds "or moving to a new phone" to "Deleting the app is
  not enough".

## Changed public sentences (old → new), against live main `720dbac`

### Ships with the first commit (no dependency on the beta)

`marketing/privacy.html`

1. What we collect → Photos you attach (AUD-56)
   - Old: "Photos are deleted from our server after 24 hours."
   - New: "Photos are deleted from our server after 24 hours. Mercurius's
     reply about your photo can quote what the photo shows. That reply is
     part of the chat, so it is kept for 90 days like any message."
2. Section heading (AUD-57; the section's aria-label matches)
   - Old: What "not linked to you" means in practice
   - New: What "linked to a random ID" means in practice
3. First paragraph of that section (AUD-57)
   - Old: "On our server, your conversations sit under a random string of
     letters and numbers. …"
   - New: "What we keep is filed under a random ID, never your name or an
     account. Usage rows also carry the scrambled network address
     described above. On our server, your conversations sit under a random
     string of letters and numbers. …" (the rest is unchanged)
4. Who sees what → Anthropic (AUD-56), added after "Anthropic does not
   train future models on API requests by default."
   - Old: (nothing)
   - New: "Anthropic's published policy for API customers like us is to
     delete what we send it, and its replies, within 30 days. It can keep
     them longer when the law requires it or to enforce its usage policy:
     messages its automated safety systems flag can be kept for up to 2
     years. Deleting your data in Mercurius erases our copy; Anthropic's
     copy follows Anthropic's schedule." ("published policy" links to
     Anthropic's article.)
5. Your controls → Delete everything from inside the app (AUD-55)
   - Old: "Available in app version 2.3 and later; on an older version,
     update the app or use the email option below."
   - New: "Available in app version 2.3 and later; on an older version,
     use the email option below." (The App Store has no newer version to
     update to yet. The last commit adds the `/get` route; see below.)
6. Your controls → Or email us (AUD-55)
   - Old: "Write to privacy@trymercurius.com and paste your session ID,
     which is shown in Settings. We delete the data within 7 days."
   - New: "Write to privacy@trymercurius.com and paste your session ID,
     which is shown in Settings. Versions before 2.3 show only the first 8
     characters, so send those; if they don't match exactly one session,
     we'll write back. We delete the data within 7 days."
7. Your controls → Deleting the app is not enough (AUD-60)
   - Old: "Removing Mercurius from your phone does not delete what is on
     the server."
   - New: "Removing Mercurius from your phone, or moving to a new phone,
     does not delete what is on the server."
8. For parents and schools, first paragraph (AUD-06)
   - Old: "What we can tell you: the app is for ages 13 and up, it asks for
     an age at first launch and shows anyone who picks one under 13 a stop
     screen instead of the tutor for 7 days (the check takes the student's
     word for it, and the device keeps only when the stop happened, never
     the age), it collects no contacts or location, it shows no ads, and
     everything it stores is deleted on the schedule above or on request."
   - New: "What we can tell you: the app is for ages 13 and up. Starting
     with app version 2.3, it asks for an age at first launch and shows
     anyone who picks one under 13 a stop screen instead of the tutor for 7
     days (the check takes the student's word for it, and the device keeps
     only when the stop happened, never the age); earlier versions don't
     ask. It collects no contacts or location, it shows no ads, and
     everything it stores is deleted on the schedule above or on request."
9. For parents and schools, second paragraph (AUD-55)
   - Old: "If you want a student's data deleted, ask them to use the button
     in Settings, or email us their session ID."
   - New: "If you want a student's data deleted, ask them to use the button
     in Settings (app version 2.3 and later), or email us their session
     ID."
   - Why: before 2.3, the only Settings button is "Start Over". It gives
     the phone a new ID and erases nothing on the server (2.0.0
     `SettingsViewModel.resetSession`).
10. For parents and schools, new last paragraph (AUD-53)
    - Old: (nothing)
    - New: "If your child is under 13 and used Mercurius before the app
      asked for an age, what they sent then may still be on our server, and
      the stop screen keeps Settings and its delete button out of reach.
      Email privacy@trymercurius.com. With no names on file, we need the
      session ID to find that data; without it, the data is still deleted
      on the schedule above."

`marketing/support.html`

11. Your data → "Can I delete my data?" (AUD-55), added after "…and we'll
    delete it within 7 days."
    - Old: (nothing)
    - New: "Versions before 2.3 show only the first 8 characters, so send
      those."
12. Your data → new item (AUD-60)
    - Old: (nothing)
    - New: "**What if I get a new phone, or also use an iPad?** Your session
      ID stays on the phone you use. A new phone or an iPad gets a new ID,
      so what's saved on our server under your old one, like your lesson
      checklist, doesn't follow. A new phone set up from a backup may still
      bring back the lesson list your old phone kept. Reinstalling the app
      on the same phone keeps your ID, and from app 2.3 your path too. If
      you want the old data erased, do it before you switch: tap "Delete my
      data & start over" in Settings (app 2.3 and later), or email us the
      session ID shown there."

Unchanged on purpose:
- the retention table;
- "Three outside services" (no Google Form yet; AUD-58 is a playbook
  line);
- support's "Mercurius AI is free on the App Store" (still true, and it
  isn't a link);
- terms' "If you got the app from the App Store".

The Effective date is a FOUNDER-TODO.

### Ships only with the last commit (gated on the beta)

All 9 pages (`index`, `features`, `modes`, `how-it-works`, `audience`,
`trust`, `support`, `privacy`, `terms`):

13. Header pill
    - Old: "Start Learning", linking to `https://apps.apple.com/app/id6773192313`.
    - New: "Get the app (beta)", linking to `https://trymercurius.com/get`.
14. Smart App Banner meta tag: on → commented out. It has no visible text,
    but Safari shows it as an App Store banner that offers 2.0.0.

`marketing/index.html`:

15. Hero
    - Old: App Store badge ("Download on the App Store").
    - New: button "Get the app (beta)" (to `/get`).
16. End of the lesson replay
    - Old: App Store badge, then "Free on the App Store. Requires iPhone,
      iOS 17 or later."
    - New: button "Get the app (beta)", then "Free beta on Apple's
      TestFlight. Requires iPhone, iOS 17 or later."
17. Final CTA: the same two changes as 16.

`marketing/privacy.html`:

18. Your controls → Delete everything from inside the app
    - Old (after the first commit): "…on an older version, use the email option
      below."
    - New: "…on an older version, install the current version from
      trymercurius.com/get or use the email option below." (linked)

`marketing/support.html`:

19. "Can I delete my data?"
    - Old (after the first commit): "Versions before 2.3 show only the first 8
      characters, so send those."
    - New: "Versions before 2.3 show only the first 8 characters, so send
      those, or install the current version from trymercurius.com/get and
      use the button." (linked)

18 and 19 stay true after the switch-back, because `/get` will point at
the App Store.

## FOUNDER-TODOs

1. **The TestFlight link** (the merge gate above).
2. **Anthropic retention (AUD-56).** The page states 30 days, and up to
   2 years for chats Anthropic's safety systems flag.
   - Source: Anthropic's "How long do you store my organization's data?"
     (privacy.claude.com/en/articles/7996866). It shows July 1, 2026 under
     the title. I read it on 2026-10-18 and again on 2026-10-19. It says
     API inputs and outputs are deleted "within 30 days of receipt or
     generation", with these exceptions:
     - longer retention under our control (the Files API; we don't use
       it, since images go as base64 in `lib/visionContent.js`);
     - a different agreement (such as zero data retention);
     - enforcing the Usage Policy (flagged chats up to 2 years,
       classifier scores up to 7 years);
     - the law.
   - "Covered Models" keep data for at least 30 days. Anthropic's list
     (support.claude.com/en/articles/15425695) has only Mythos 5 and 5.1,
     and Fable 5 and 5.1. We use `claude-sonnet-4-6` and
     `claude-haiku-4-5` (`server.js`, `MODEL_ALLOWLIST`).
   - **Confirm:** that the Anthropic org has no zero data retention or
     other retention agreement, and that Railway's model variables don't
     point at a Covered Model. If either is wrong, reword the sentence.
     The HTML comment above it says the same.
3. **App Store Connect privacy label (AUD-57).** In App Privacy, change
   all four data types to Linked = Yes, Tracking = No:
   - User ID;
   - Other User Content;
   - Photos or Videos;
   - Product Interaction.

   No build is needed. Build 16's `PrivacyInfo.xcprivacy` still says not
   linked. The next build fixes that in the iOS batch;
   `APP_STORE_LISTING.md` §3 records the gap.
4. **The privacy page's Effective date** still says September 27, 2026.
   Set it to the deploy day (an HTML comment marks it).
5. **Railway Postgres backups.** Check whether backups are on and how long
   they're kept. Erased rows live on in backups until those rotate, and
   the privacy page doesn't say so. This TODO is in the runbook.
6. **AUD-53.** Should an under-13 answer erase that phone's server data
   automatically? That's still your decision, parked in PR #34.

## Switch-back plan, once 2.3 is approved

Wait until `curl -s 'https://itunes.apple.com/lookup?id=6773192313&country=us'`
shows version 2.3.0 or later. Then follow `docs/STORE_CTA_SWITCHBACK.md`
(in the last commit). It gives the exact "now" and "back to" HTML for each spot:

1. In `marketing/_redirects`, point `/get`, `/Get` and `/GET` at
   `https://apps.apple.com/app/id6773192313` and keep the 302. `/beta`
   stays on TestFlight.
2. Turn the Smart App Banner back on, on all 9 pages.
3. Put the header pills back to "Start Learning" with the App Store link.
4. Put the homepage hero and final CTA back to the App Store badge, with
   "Free on the App Store".
5. For the lesson replay end, edit `scripts/build-demo-replay.mjs`, the
   check in `scripts/check-demo.mjs` and `docs/marketing-demo.md`, then
   regenerate.
6. Run the check list: `grep -rn "AUD-06"` finds nothing, every page links
   to the App Store, `build-demo-replay --check` passes and
   `check-demo.mjs` gives 124 passed.

The privacy and support `/get` sentences (18 and 19) stay.

If the last commit was held, the CTAs are already on the App Store, so only step
1 applies. You could also bring back "update the app or" in privacy.html
"Your controls" (sentence 5).

## TestFlight build 16 expires around 2026-12-26

Build 16 (2.3.0) was uploaded on 2026-09-27 (`e3e3f0d`). TestFlight builds
expire 90 days after upload, so it lapses around 2026-12-26. After that,
`/get` and every commit-5 button lead to a beta with nothing to install.
Before then, do one of these:
- get 2.3 approved and do the switch-back;
- upload a newer build with `ios/scripts/release.sh`, get it through Beta
  App Review and assign it to the external group.

Then rerun the beta check. `docs/STORE_CTA_SWITCHBACK.md` §0 says the
same.

## Review findings: what changed

1. **High: CTAs lead to a closed beta.** Accepted.
   - I can't reopen the link: it needs App Store Connect, which is your
     call.
   - The CTA change is now one commit, the last one, so you can hold it.
   - The privacy and support pages, and the runbook replies, no longer
     send anyone to `/get` outside that commit.
   - I corrected the check, which gave a false pass.
   - The check is in this file, `STORE_CTA_SWITCHBACK.md` §0 and the
     runbook, not NOTES.md. NOTES.md is folded into this file.
2. **Medium: "linked only to a random ID" over-promises.** Accepted, with
   the review's wording. Confirmed in the code: `usage.ip_hash` sits next
   to `session_id` (`db.js`). It is a salted sha256 truncated to 16 hex
   characters (`lib/claudeCall.js` `hashIp`), and it is kept 400 days.
3. **Low: new phone and backup restore.** Accepted, with hedged wording.
   - Confirmed: the lesson list is in UserDefaults (`ProgressStore.swift`),
     and there is no `isExcludedFromBackup`.
   - The Keychain ID is this-device-only.
   - `CurriculumProgressSync` pushes a local list the server lacks.
   - The FAQ now leads with the session ID and says to erase before
     switching. Privacy sentence 7 covers the server copy that's left
     behind.
   - Not tested on a device.
4. **Low: versions before 2.3.** Accepted.
   - `prefix(8)` ran from `5018f50` until `f655c85` (2.3.0), so it covers
     2.0.0, 2.1.0 and 2.2.0.
   - "App version 2.0" is now "Versions before 2.3" on the privacy page,
     the support FAQ and in the runbook.
   - I also qualified the parents' "use the button in Settings" (sentence
     9).
5. **Screenshots folder.** `docs/content-batch/shots/` (40 PNGs from the
   review) is untracked and in no commit. Delete it or leave it. Don't
   `git add -A` in this worktree.

I rejected none of the findings.

## Every claim checked against the code (main `720dbac`)

| Claim | Where it comes from |
|---|---|
| Messages are kept 90 days, photos 24 h, usage rows and lesson events 400 days, the whole session erased after 365 idle days | `lib/scheduler.js` `PURGES` and `SESSION_PURGE` defaults. Railway could override these through env; I can't see its variables. |
| Merc's reply about a photo is a normal message | `server.js` saves the user turn and the assistant reply with `db.saveMessage` (the `messages` table, 90-day purge). Photo bytes are in `images` (`lib/imageStore.js`), purged after 24 h. |
| What goes to Anthropic | Messages and photos (`lib/visionContent.js`, base64, no Files API), through `lib/claudeCall.js`. Models: `claude-sonnet-4-6`, `claude-haiku-4-5`. |
| Usage rows carry the scrambled address | `db.js` `usage` has `session_id` and `ip_hash`. `recordUsage` writes both. `hashIp` is a salted sha256, 16 hex characters. `IP_HASH_SALT` must stay stable (`DEPLOY.md`). |
| Delete erases our copy only | `DELETE /api/session/:id` refuses IDs under 16 characters, then calls `db.deleteSession`. That deletes `messages`, `images`, `reports`, `usage`, `lesson_events`, `curriculum_progress` (plus `xp_ledger`/`progression` if present), then `sessions`, in one transaction. Nothing calls Anthropic. |
| No name on file | `sessions.student_name`/`display_name` exist but are never written, and are cleared on boot (`db.js`). |
| Versions before 2.3 show 8 characters | `SettingsView.swift` `sessionId.prefix(8)` + "…", from `5018f50` until `f655c85`. 2.3 shows the full ID with Copy. |
| "Start Over" before 2.3 erases nothing on the server | 2.0.0 `SettingsViewModel.resetSession` only resets the Keychain ID and local history. |
| Installing 2.3 over an older version keeps the ID | Same Keychain key and generator (`SessionIdentity`), same bundle. |
| The ID stays with the phone; a backup may bring the list back | `Keychain.swift` `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. `ProgressStore` uses UserDefaults, with no backup exclusion. `CurriculumProgressSync` pulls, merges, then pushes. |
| The stop screen hides Settings | `OnboardingSteps.swift` `UnderThirteenView` has no controls. |
| Every error string in the playbook | `APIError.swift`, `ChatViewModel.swift`, `MessageBubbleView.swift` at build 16 (`e3e3f0d`). Server copy: `server.js`, `lib/quotas.js`. |

## How the site deploys (checked)

trymercurius.com is served by Netlify. Its response headers include
`server: Netlify` and `cache-status: "Netlify Edge"`, and the live
homepage matches `marketing/index.html`. The repo has no `netlify.toml`,
so the publish directory is set in the Netlify dashboard. PR #40 went
live when it merged, so merging this deploys the site.

After the deploy, `node scripts/check-demo.mjs https://trymercurius.com/`
should give 124 passed. With the last commit it expects the `/get` button; without
it, the App Store badge.

## Verification (2026-10-19)

I checked both states: the first commit alone (beta held) and both commits.

- `node scripts/build-demo-replay.mjs --check` matches the capture
  (sha256 `b6ae15690ea7…`) in both states.
- I served each state locally with `python3 -m http.server` on free ports
  and ran `node scripts/check-demo.mjs`. Both gave **124 passed, 0
  failed**.
- Link check of all 9 pages:
  - Every local `href`/`src` gives 200 and every `#` anchor exists: 16
    paths with the last commit, and 17 held (that state also has the badge
    SVG).
  - External: both Anthropic pages 200, the App Store 200, `/get` 302 to
    TestFlight.
- No horizontal overflow on privacy and support at 360, 375, 1024 or
  1280 px in either state, or on any of the 9 pages at 375 px with commit
  5.
- `grep` with the last commit: no `apps.apple.com` link and no live
  `apple-itunes-app` tag on any page.
- `grep` held: the App Store links and banners are exactly as on main,
  and no `/get` link.
- The beta check printed `1` (closed).
- Not run:
  - `npm test`, since no server code changed and no test reads these
    files;
  - a real iPhone, including Safari, the TestFlight install over 2.0 and
    a restore from a backup.

## Judgment calls from the first pass (unchanged)

- **The Smart App Banner is off while the CTAs point at `/get`.** It can't
  point anywhere but the App Store listing, which sells 2.0.0. The cost:
  people who already have the app lose its "Open" shortcut.
- **The header pill text is "Get the app (beta)".** It shows only at
  1024px and wider, and it fits at 1024.
- **The replay's end button is generated.** The generator, the check and
  the spec changed together. The replay text is untouched, and
  `--check` passes against the same capture.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
