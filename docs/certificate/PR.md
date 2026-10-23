# Printable course certificates (the "B · Laurel" designs)

> **Stacked on #48** (`feat/mac-night-studio`). Its base is that branch; retarget this PR to `main` once #48 merges.

The founder asked for "a printable certificate after they complete all the advanced courses… make it look good", chose **B · Laurel** from the Claude Design canvas, and asked for a simpler **AI Basics** certificate for the beginner course. This PR builds both, on iPhone and Mac:
- a vector, one-page US Letter PDF that matches the designs line for line;
- a name sheet with a live preview, Print and Save / Share;
- a "Get your certificate" card at the moment the course is finished;
- a Certificates list in Progress.

The learner's name never leaves the device.

## Screenshots

**The Deep dive certificate**, from the app's PDF at 150 dpi:

![Deep dive certificate](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/certificate-deepDive.jpg?raw=true)

**The AI Basics certificate**, from the app's PDF at 150 dpi:

![AI Basics certificate](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/certificate-basics.jpg?raw=true)

**The design** (Chrome rendering `Laurel.dc.html`, left) **next to the app's PDF** (right):

![Deep dive: design vs app](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/compare-deepDive.jpg?raw=true)

![AI Basics: design vs app](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/compare-basics.jpg?raw=true)

The app's page is white because the PDF leaves the paper unpainted (see below). On AI Basics, the signature label sits on one line on purpose: that is the one layout change from the design.

**The name sheet:** iPhone on the left, Mac (Night Studio) on the right.

<img src="https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/iphone-name-sheet.jpg?raw=true" alt="iPhone name sheet" width="300"> <img src="https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/certificate/docs/certificate/key-shots/mac-name-sheet.jpg?raw=true" alt="Mac name sheet" width="420">

The sample PDFs are in `docs/certificate/samples/`.

## Where the certificates appear

- **When the course is finished.** The eighth unit check's result shows the **"Get your certificate"** card ("You finished the AI Literacy Course"), which opens the name sheet.
  - iPhone: under the score.
  - Mac: a lit Night card above Done.
  - The card goes when the check closes, by any way out.
- **Progress ▸ Certificates.** A row in the Progress hub ("1 earned · 1 in progress") opens a list of every certificate this build offers:
  - earned ones show "Earned October 21, 2026" and **Get Your Certificate**;
  - the others show what's left ("5 of 8 unit checks passed · Still to pass: Unit 4 · Prompt Engineering, …").
- **The name sheet**, "Your Certificate":
  - a live preview, then **"Your name, as it should appear"** and **"Your name stays on this device. It's never sent to Mercurius's servers."**;
  - iPhone: **Print** (the system print sheet) and **Share or Save as PDF** (the share sheet, which includes Save to Files; its preview tile is the certificate itself);
  - Mac: **Close** (Esc), **Save as PDF…** (⌘S, a save panel) and **Print…** (Return or ⌘P, the print panel on the printer's own paper, Letter or A4).
- **The certificate** is always the light Laurel paper, in light and dark mode alike.

**Eligibility:**
- **Deep dive:** all eight unit checks mastered, `unit_1` … `unit_8`, read from `CurriculumProgressStore.masteredUnits`.
- **AI Basics:** every Basics lesson finished (see the seam below).
- **The date:** the moment the last requirement was met, if the app saw it; otherwise the day the certificate is first made. After that it is fixed and stored on the device.

## Privacy: the name stays on the device

- **Storage:** the name lives in `UserDefaults` only, with the earned and printed dates beside it.
- **Where it goes:** it reaches the page, the print panel, the share sheet or a file the learner picks, and nowhere else.
  - No networking code can reach it: `NetworkingKit` sits below `EngagementFeature`, and the store is never passed to it.
  - It isn't logged.
  - The PDF's metadata doesn't carry it (Title, Creator "Mercurius").
  - The shared file is named "Mercurius Certificate - AI Literacy Course.pdf", without the name. The temporary copy is deleted when the sheet closes.
- **Erasing:** "Delete my data & start over", "Reset this device only" and both consent withdrawals erase the name and dates, and any course-complete card still waiting (`CertificateCenter.reset()`).
- **On the Mac,** where Settings is its own window:
  - a reset closes the Progress sheet;
  - a name sheet open across a reset closes itself, and never writes the erased name back.
- **Backups:** like progress, the name is in the device's own iCloud or computer backup. That is the student's Apple backup, not Mercurius's.

## Fonts and licences

- **The fonts:** Cormorant Garamond and EB Garamond, the variable fonts from github.com/google/fonts. They are unmodified and renamed without brackets:
  - `CormorantGaramond-Variable.ttf`;
  - `CormorantGaramond-Italic-Variable.ttf`;
  - `EBGaramond-Variable.ttf`;
  - `EBGaramond-Italic-Variable.ttf`.
- **The licences:** SIL OFL 1.1, shipped beside the fonts (`OFL-CormorantGaramond.txt`, `OFL-EBGaramond.txt`) in `DesignSystem/Sources/Fonts`, as Lexend and Atkinson are.
- **Registration:** `BrandFontRegistrar` registers them like Lexend and Atkinson.
- **Weights:** each face is picked by its named instance:
  - Cormorant Garamond SemiBold and SemiBold Italic, `wght` 600;
  - EB Garamond Regular and Italic, `wght` 400.
- **Checks:**
  - the tests resolve each PostScript name and its `wght`;
  - the PDF embeds exactly those four faces as TrueType subsets, with all text kept as text;
  - the mark (470 × 415) is the only image.
- **Ligatures:** Cormorant's are off, because its "fi" has no Unicode mapping a PDF can carry ("Certi!cate" in copy and search). EB Garamond's stay on.
- **Size:** about 3.5 MB of fonts added to the app.

## The AI Basics seam

AI Basics lives on another branch, so this build doesn't offer its certificate yet. Everything else is built and tested:
- **The rule:** a pure function, `CertificateEligibility.basics(lessons:completedLessonIds:completedAt:)`, with the lesson ids as input.
- **Switching it on:** the Basics branch returns its lessons from `CertificateCourses.basicsLessons` (`AppFeature/Sources/CertificateWiring.swift`). That sets `CertificateCenter.basicsLessons`.
- **Recording the moment:** it wraps its lesson-complete call in `env.certificates.recordingNewlyEarned { … }`, so the date is recorded and the card shows.

The steps and the checklist are in `docs/certificate/INTEGRATION.md`.

## How it matches the design

- **The layout:**
  - `CertificateLayout` reproduces Chrome's flex column for the 1056 × 816 px designs, at 0.75 pt a pixel.
  - Every text baseline lands on Chrome's, and `CertificateLayoutTests` pins them.
  - The seal's words are set as SVG text on a path (`textLength="345"`).
- **Long names:**
  - "Alexandria Montgomery-Vasquez" and short names stay on one line at the design's 72 px.
  - Longer names shrink a little on one line, then go onto two balanced lines.
- **Deliberate differences**, each explained in `docs/certificate/README.md`:
  1. No Cormorant ligatures.
  2. A curly apostrophe in "beginner’s".
  3. **AI Basics' bottom columns are 290 px, not 250**, so "INSTRUCTOR OR FAMILY MEMBER" sits on one line and both signature rules line up. The design's wrap left the signature line 18 px higher than the date line. The Deep dive is unchanged.
  4. **Two-line names sit 1.12 em apart, not 1.05**, so accented capitals (Á, Ö, Å) clear the line above.
  5. **Name breaks:**
     - a break at a space always beats one inside a hyphenated surname, so both certificates set a name alike;
     - a line never ends on a particle: "Maria Fernanda de los Santos / Rodríguez-Ochoa".
  6. **The PDF doesn't paint the #FDFDFB paper,** so printers don't dither a tint. On screen the paper colour stays.

## Tests

All of the following run in `swift test`:
- **Eligibility:**
  - Deep dive: none, partial, complete;
  - Basics with injected ids: none, partial, complete, and its date;
  - the date rule;
  - Basics through the seam.
- **The name store:**
  - only its own key, in the given defaults;
  - normalized;
  - erased by every Settings reset;
  - the reset clears a waiting card, and an open sheet can't write the name back.
- **The PDF (PDFKit and Core Graphics):**
  - one page, media box 792 × 612;
  - extractable text with the name, "Certificate of Completion", the date and the footer;
  - the four faces embedded;
  - the mark the only image;
  - no paper fill.
- **Fonts:** registered with the expected PostScript names and `wght` 600 / 400; the licences in the bundle.
- **Long names:** short, one-line shrink, two-line balance, particles, lowercase names, hyphen preference, unbreakable words, 10–80 characters, and the real font for 44–61-character names on both kinds.
- **Layout:** baselines pinned to Chrome's for both kinds; AI Basics' one-line label and aligned rules; two lines clear of the seal and of each other.
- **Mac shell:** a Settings reset closes the Progress sheet.
- **ArchitectureTests** pass unchanged, apart from the manifest fixture's new `CertificateArt` resource.

**Verification** (Xcode 26.4 / Swift 6.3):

| Check | Result |
|---|---|
| `swift test` | 1247 tests passed |
| `ci-compat-lint.py` | 0 findings |
| iOS `xcodebuild test` with CI's flags | 31 of 31 passed, no retries |
| Snapshot comparison, recording off | unchanged: the same 23 results and the same pixels as the baseline. No snapshot test renders the new UI, and no references were re-recorded. |
| Mac Debug and universal Release builds | succeeded; `mac-bundle-check.sh` ok; the fonts, licences and mark are in the bundle |
| Mac screenshots | taken from a renamed copy of the app |
| iPhone share sheet | tapped on a simulator; it shows the certificate as its preview |

**Not verified:** the Mac print and save panels at run time, and CI's macOS 14 / Xcode 16.2 runtime.

## For the founder

1. **AI Basics' signature label** now sits on one line, in columns 40 px wider than the design's. Say if you'd rather keep the design's two-line wrap; reverting is one line.
2. **Settings' "Delete my data" wording** says it erases "chats, lessons, streak and progress". It does erase the certificate name too, but doesn't say so. Add "and the name on your certificate"?
3. **Two new Mac entitlements,** which App Review will see:
   - `com.apple.security.print`: a sandboxed app can't print without it;
   - user-selected files read-write instead of read-only, so Save as PDF… can write where the learner picks.
4. **App size:** about 3.5 MB more, for the fonts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
