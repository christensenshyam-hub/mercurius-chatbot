# Printable course certificates

Branch `feat/certificate`, stacked on `feat/mac-night-studio` (PR #48). Written 2026-10-21 with Xcode 26.4 / Swift 6.3, then revised after a design and code review. Not pushed. The PR description is `PR.md`.

The founder asked for "a printable certificate after they complete all the advanced courses… make it look good". They chose **B · Laurel** from the Claude Design canvas, and asked for a simpler **AI Basics** certificate for the beginner course too. The designs are the source of truth:
- `design/Laurel.dc.html`: the Deep dive certificate;
- `design/LaurelBasics.dc.html`: the AI Basics certificate.

## What a learner sees

- **The moment the eighth unit is mastered.** The unit check's result shows a **"Get your certificate"** card: "You finished the AI Literacy Course". Its button opens the name sheet.
  - iPhone: under the score. Mac: a lit Night card above Done.
  - The card goes away when the check closes.
- **Progress ▸ Certificates.** A row in the Progress hub, with "1 earned · 1 in progress", opens the **Certificates** list:
  - every certificate this build offers, earned or not;
  - "Earned October 21, 2026" and a **Get Your Certificate** button, or "5 of 8 unit checks passed" and "Still to pass: Unit 4 · Prompt Engineering, Unit 7 · Using AI Well and 1 more".
- **The name sheet**, "Your Certificate":
  - a live preview of the certificate;
  - **"Your name, as it should appear"**;
  - **"Your name stays on this device. It's never sent to Mercurius's servers."**;
  - iPhone: **Print** (the system print sheet) and **Share or Save as PDF** (the share sheet, which includes Save to Files);
  - Mac (Night Studio's sheet): **Close** (Esc), **Save as PDF…** (⌘S, a save panel) and **Print…** (Return or ⌘P, the print panel).
- **The certificate itself** is always the light Laurel paper, in light and dark mode alike.

## Where the code is

| What | Where |
|---|---|
| The certificate: `CertificateView` (792 × 612 pt), `CertificatePreview`, the layout, the long-name fit, the seal, the PDF | `DesignSystem/Sources/Certificate/` |
| The fonts and their licences | `DesignSystem/Sources/Fonts/`: `CormorantGaramond-Variable.ttf`, `CormorantGaramond-Italic-Variable.ttf`, `EBGaramond-Variable.ttf`, `EBGaramond-Italic-Variable.ttf`, `OFL-CormorantGaramond.txt`, `OFL-EBGaramond.txt` |
| The mark | `DesignSystem/Sources/CertificateArt/certificate-mark.png` (`marketing/assets/mercurius-icon.png`, 470 × 415) |
| Eligibility, the store, the center, the sheet, the list, the card, print and share | `EngagementFeature/Sources/Certificates/` |
| The Progress hub's row | `EngagementFeature/Sources/ProgressHubView.swift` (`certificates:`, optional) |
| The card's slot on a passed check | `CurriculumFeature/Sources/UnitMasteryAccessory.swift` (`\.unitMasteryAccessory`), read by `UnitTestView` (iOS) and `NightUnitTestContent` (Mac) |
| Wiring | `AppFeature/Sources/CertificateWiring.swift` (courses, the Basics seam, the slot modifier, DEBUG hosts), `AppEnvironment.certificates`, `AppShellView`, `MacShellView`, `SettingsSheet` (the reset) |

No new package and no new cross-feature dependency: `ArchitectureTests` is unchanged apart from the manifest fixture, which gains the `CertificateArt` resource.

## Matching the design

The designs are HTML at 1056 × 816 CSS px, which is 11 × 8.5 in at 96 px/in. The PDF is 792 × 612 pt, so every design pixel is 0.75 pt. `CertificateLayout` keeps the design's numbers in pixels and converts once.

**How it was matched.** Headless Chrome laid out a standalone copy of each design (`tools/standalone.py`) and reported every line box through `getClientRects()`. `CertificateLayout` then reproduces Chrome's flex column exactly:
- the stack from the top, and the block pinned to the bottom;
- `normal` line heights from the font's ascent and descent rounded to whole pixels;
- explicit line heights floored to 1/64 px;
- the half-leading floored.

Every text baseline lands on Chrome's, and `CertificateLayoutTests` pins them:

| Line | Deep dive (px) | AI Basics (px) |
|---|---|---|
| MERCURIUS AI | 156 | 164 |
| Certificate of Completion | 219 | 229 |
| AI BASICS | — | 268.594 |
| is proudly presented to | 288.594 | 320.594 |
| the name | 356.594 | 388.594 |
| the paragraph | 419.188, 446.734 | 454.188, 483.188 |
| the unit lines | 481.281, 502.281 | — |
| the date / DATE | 679 / 712 | 679 / 712 |
| the signature label | 712 | 712 (one line; see below) |
| the footer | 740 | 740 |

Text goes by its baseline and the centre of its line box, letter-spacing included, as CSS centres it. SwiftUI's `tracking` also adds space after the last character, as Chrome's `letter-spacing` does.

**The seal** sets each glyph as SVG text-on-a-path does:
- the middle of each glyph's advance sits on the circle (r 56), turned to its direction;
- the run starts at 9 o'clock;
- `textLength="345"` spreads the extra room evenly between the characters (SVG 2 `lengthAdjust="spacing"`).

**The result** (`compare/`):
- **At 96 dpi** against Chrome at 1×, every line's ink box is within 1 px.
- **At 150 dpi** the overlays show fringes of up to about 2 px (1 pt), because Chrome lays out in device pixels at a 1.5625 scale factor and rounds each line box there. The PDF follows the CSS layout itself.
- **The frame, the rules, the seal and the mark** match to the pixel at both resolutions, except AI Basics' two bottom columns, which are deliberately 40 px wider (below).
- **The paper:** the design's page is #FDFDFB; the PDF leaves its page unpainted (below), so the app's half of each side-by-side is white.

Files in `compare/`:
- `deepDive-side.png`, `basics-side.png`: the design | the app's PDF, at 150 dpi;
- `*-overlay.png`: the two overlaid, design in red and app in cyan (where they agree the ink is grey);
- `design-*-150dpi.png`: Chrome's renders;
- `*.standalone.html`: the copies Chrome rendered. They point at the bundled fonts and the mark by absolute `file://` paths in this worktree.

Re-make all of it with `docs/certificate/tools/make-compare.sh`.

### Where the PDF deliberately differs from the design

1. **No ligatures in Cormorant Garamond.**
   - **Why:** Cormorant's "fi" ligature has no Unicode mapping a PDF can carry. With it, the PDF's text reads "Certi!cate of Completion", which breaks copy, search and screen readers.
   - **What it costs:** Cormorant's separate f and i look almost the same at these sizes. The only visible change is the dot on the i of "Certificate" (`compare/deepDive-overlay.png`, the cyan dot).
   - **Not affected:** EB Garamond's ligatures map correctly and stay on, as in the design.
2. **"beginner’s" takes a typographic apostrophe.** The design's HTML has a straight `'`. This follows the house rule Night Studio set (`NightTypography.curlQuotes`).
3. **The date** prints in the "[Date]" slot as "October 21, 2026". The signature line stays blank, for the teacher or family member to sign.
4. **Long names.** The design sets the name at 72 px on one line inside the 864 px column, as `text-wrap: balance` would. Past that the rule is (`CertificateNameFit`):
   - a name that fits at 72 px stays there;
   - one just over shrinks a little on one line, down to 57.5 px;
   - longer names break onto two balanced lines, up to 57 px on the Deep dive and 64 px on AI Basics, which keeps at least 16 px between the paragraph block and the seal;
   - the two lines sit 1.12 em apart, not the design's 1.05. At 1.05 an accented capital on line 2 (Á, Ö and Å reach 0.79–0.82 em) runs into a g or y on line 1 (0.28 em down); at 1.12 even Å clears it;
   - a break at a space always beats one inside a double-barrelled name, so "Montgomery-Vasquez" stays whole and both certificates break a name alike. A hyphen breaks only when every space break would set the name under 48 px;
   - a line never ends on a lowercase particle (de, los, van, von, der, da, bin, al, y…): "Maria Fernanda de los Santos / Rodríguez-Ochoa", not "Maria Fernanda de los / Santos Rodríguez-Ochoa". A name typed all in lowercase breaks at any space;
   - one unbreakable word shrinks on its line;
   - input is capped at 80 characters.

   A one-line name keeps the design's 75.6 px line box, so a slightly smaller name doesn't move the rest of the page. Two lines push the paragraph down, as CSS would.

   Samples are made in `shots/` (local, not committed):
   - "Li Wei" (`-short`);
   - "Alexandria Montgomery-Vasquez": one line at 72 px, as in the design;
   - "Maria Fernanda de los Santos Rodríguez-Ochoa", 44 characters (`-long`);
   - "Christopher Alexander Montgomery-Vasquez de la Fuente Ramírez", 61 characters (`-60`).
5. **AI Basics' date and signature columns are 290 px, not 250.** "INSTRUCTOR OR FAMILY MEMBER" is 274.8 px at 14 px with 0.12em tracking, so in the design's 250 px column Chrome wraps it after "Family", and the signature rule rides 18 px higher than the date rule. On paper that reads as a mistake. At 290 px the label sits on one line with 7.6 px to spare each side, both rules line up at 691 px, and each column still stands 72 px clear of the seal. The words, size and tracking are the design's; the Deep dive's columns are unchanged.
6. **The PDF leaves the paper unpainted.** The design's page is #FDFDFB. Printed, a 1% tint comes out as a sparse dot pattern that ends in a hard edge at the printer's margin, so the paper colour comes from the paper. On screen (the sheet's preview, the list, the card) the certificate keeps its #FDFDFB.

## Fonts

- **Bundled the way Lexend and Atkinson are.**
  - **Folder:** `DesignSystem/Sources/Fonts`, a `.copy` resource.
  - **Registration:** `BrandFontRegistrar` registers every `.ttf` in the folder at run time. A new alias, `registerCertificateFonts()`, does the same thing.
  - **Licences:** the SIL OFL 1.1 text ships beside each font.
  - **Source:** the files are the variable fonts from github.com/google/fonts, unmodified, renamed without brackets.
- **Weights come from named instances.**

  | Face | Instance | `wght` |
  |---|---|---|
  | Wordmark, title, unit lines, seal, AI BASICS | `CormorantGaramond-SemiBold` | 600 |
  | The name | `CormorantGaramond-SemiBoldItalic` | 600 |
  | Paragraph, date, labels, footer | `EBGaramond-Regular` | 400 |
  | "is proudly presented to" | `EBGaramond-Italic` | 400 |

  - **Checked in the tests:** each face resolves by PostScript name and carries its `wght`.
  - **Checked in the PDF:** it embeds exactly these four as TrueType subsets (`shots/*.inspect.txt`).
  - **Checked by eye:** a side-by-side of Cormorant at 300, 400, 600 and 700 showed the weights render distinctly.
- **Size:** the four fonts add about 3.5 MB to the app.

## The PDF

`CertificatePDF.data(kind:name:date:)`:
- renders `CertificateView` with `ImageRenderer` straight into a Core Graphics PDF context, at a layout scale of 8 so the text is placed within 1/8 pt;
- produces one page with a 792 × 612 media box;
- keeps the text as text, with fonts embedded as subsets: PDFKit extracts "Certificate of Completion", the name and the date;
- draws the frame, the rules, the ornament and the seal's rings as vectors, and the seal's words as text;
- embeds the mark once, as the original 470 × 415 image (about 730 dpi at its printed size). There is no other image.
- **iPhone printing:** `UIPrintInteractionController`, landscape.
- **Mac printing:** `NSPrintOperation` on a `PDFDocument`, landscape, on the paper the learner's printer is set to (Letter as is; A4 at about 97%), scaled to fit and centred.
- **The share sheet's preview tile** (iPhone) is the certificate itself, drawn small (396 × 306 px) a moment after the name stops changing.
- **Sharing:** the share sheet gets the PDF as a temporary file named "Mercurius Certificate - AI Literacy Course.pdf". The file name has no learner's name in it. The file is removed when the sheet closes.

## Eligibility and the date

- **The Deep dive** is earned when all eight unit checks are mastered, `unit_1` … `unit_8`, which `CurriculumProgressStore.masteredUnits` records. `CertificateCourses.deepDiveUnits` comes from `MercuriusCurriculum.units`, and a test pins it to those ids and to the copy's "eight units, thirty-five lessons".
- **AI Basics** is earned when every Basics lesson is finished. The rule is the pure function `CertificateEligibility.basics(lessons:completedLessonIds:completedAt:)`, with the lesson ids as input. The Basics course isn't on this branch, so the certificate is off until the seam receives its lessons. See `INTEGRATION.md`.
- **The completion date**:
  - when the last requirement was met, if that is recorded;
  - otherwise the day the certificate is first made (the sheet first opened);
  - fixed from then on and stored locally (`CertificateStore`).

  What counts as recorded:
  - **The Deep dive:** mastery carries no date, so the app records the moment it sees the eighth check pass (`CertificateCenter.recordingNewlyEarned` around `markUnitMastered`). Progress synced from another device doesn't carry that moment; its certificate takes the day it's first made.
  - **AI Basics:** the last lesson's `completedAt`, when every lesson has one.

## Privacy

- **Where the name lives:** `UserDefaults` (`com.mayoailiteracy.mercurius.certificate.name`, a private suite under `-UITests`), with the earned and printed dates beside it.
- **Where it goes:** only onto the page, the print panel, the share sheet or a file the learner picks. No networking code can reach it: `NetworkingKit` sits below `EngagementFeature`, and the store is never passed to it. It isn't logged, and the PDF's metadata doesn't carry it.
- **How it's erased:** "Delete my data & start over", "Reset this device only" and both consent withdrawals run `SettingsSheet`'s local wipe, which now calls `CertificateCenter.reset()`: the name, every date and any course-complete card still waiting. `SettingsResetTests` checks this.
- **A sheet open across a reset** (possible on the Mac, where Settings is its own window) closes: it watches `CertificateStore.resetCount`, never writes the erased name back, and the Mac's reset also closes the Progress sheet it sits on.
- **Copy left alone:** Settings' wording ("erases your chats, lessons, streak and progress") is unchanged. Whether to add "and the name on your certificate" is the founder's call.

## Mac

- **The sheet** follows Night Studio's sheet conventions (the mode explainer's):
  - the indigo canvas;
  - an eyebrow ("AI LITERACY COURSE") and a display title;
  - a Night field;
  - a bottom bar with a text button, a secondary button and the one prominent button.
- **The card** is a `nightLit` card with a secondary button. The check's Done stays the one prominent button. It goes whenever the check does, by any way out (the sidebar, ⌘1–⌘3, Learning Path, a lesson, Settings), not only by its Done (`.onChange(of: shell.activeUnitTest?.id)` in `MacShellView`).
- **Two new entitlements**, in `project.yml`, the entitlements file and `MacReleaseConfigTests`:
  - `com.apple.security.print`: a sandboxed app can't print without it;
  - `files.user-selected.read-write` instead of `read-only`, for Save as PDF… to write where the learner picks. Picking a photo still works.

  App Review will see both.

## Accessibility

- **VoiceOver:**
  - the preview reads as one image: "Certificate of Completion, AI Literacy Course, awarded to Alexandria Montgomery-Vasquez, October 21, 2026";
  - the list's thumbnails are hidden and its rows read their words;
  - the field is labelled "Your name, as it should appear".
- **Dynamic Type** (iPhone): the sheet, the list and the card use `BrandFont`.
  - At the accessibility sizes, the list stacks the thumbnail over the words and the name field wraps.
  - The certificate itself stays fixed, as a printed page should.
- **Mac keyboard:** Return or ⌘P prints, ⌘S saves and Esc closes. The field takes the focus when there's no name yet.

## DEBUG launch arguments (screenshots without taps)

They need `-UITests YES`. Progress is seeded in the private suites, emptied at each launch, and never pushed. The sample name is "Alexandria Montgomery-Vasquez", or `-CertificateName <name>`.

| Argument | Shows |
|---|---|
| `-CertificatePreview deepDive` / `basics` | the name sheet for that certificate, open |
| `-CertificateList YES` | the Certificates list: Deep dive earned, AI Basics 12 of 18 (through the seam's DEBUG demo lessons) |
| `-CertificateHub YES` | the Progress hub with its Certificates row |
| `-CertificateCardPreview YES` | Unit 8's check passed, completing the course, with the card |

- **iPhone:** `RootView` hosts these states.
- **Mac:** `MacShellView` hosts them inside the shell, past the gate. `mac-snapshots.sh` has the matching shots:
  - `certificate-sheet`, `certificate-sheet-basics`;
  - `certificate-list`, `certificate-hub`;
  - `certificate-card`.

## Tests added

All of them run in `swift test`.

- **`DesignSystemTests/CertificateTests.swift`:**
  - **Fonts:** registered with the expected PostScript names; `wght` 600 and 400; the licences present.
  - **Layout:** every baseline above, for both kinds; AI Basics' 290 px columns, its one-line label and both rules at 691 px; each signature label inside its column and clear of the seal; two-line names clear the seal and the column, at 57 and 64 px too; two lines 1.12 em apart, with the real font's g and Å not touching.
  - **Name fit, with a fake measure:** short, slightly long, long, particles kept with their surname, a lowercase name, a space break beating a larger hyphen break, a hyphen as the last resort, unbreakable, bounds for 10–80 characters, normalization.
  - **Name fit, with the real font:** "Li Wei" and "Alexandria Montgomery-Vasquez" stay at 72 px; 44–61-character names stay at 54 px or larger on both kinds; both kinds set "Christopher Alexander / Montgomery-Vasquez de la Fuente Ramírez" alike; "de los Santos" stays on one line.
  - **The seal's run:** 345 px.
  - **Copy:** the US date; the VoiceOver summary.
  - **PDF:** one page; a 792 × 612 media box; text with the name, the title, the date and the footer; a two-line name; the four faces embedded; the 470 × 415 mark the only image; no paper fill (the page's corners and open paper are transparent, the border is ink).
  - An opt-in `CertificateShots` test writes the PDFs for `shots/`.
- **`EngagementFeatureTests/CertificateTests.swift`:**
  - **Eligibility:** Deep dive none, partial and complete; Basics with injected ids, none, partial and complete, with its date; the date rule.
  - **The store:** the name normalized; only its own key written, to the given defaults, never `.standard`; reset erases everything and counts itself (`resetCount`, which an open sheet watches); the first dates stand.
  - **The center:** the seam; the eighth mastery as the moment; a certificate earned elsewhere; Basics through the seam; the hub row's summary; the sheet's privacy copy.
- **`AppFeatureTests`:**
  - **`CertificateWiringTests`:** the curriculum's units against the copy; the seam off in this build; mastery through the real progress store; a reset takes a waiting card with it, so a later pass can't bring it back; Basics ids in the shared store.
  - **`SettingsResetTests`:** "Delete my data" and "Reset this device only" erase the name and dates, and clear a waiting card.
  - **`MacShellModelTests`:** a reset from the Settings window closes the Progress sheet (and a certificate sheet over it).
  - **`MacReleaseConfigTests`:** the new entitlements.

## Verification (2026-10-21, Xcode 26.4 / Swift 6.3, after the review fixes)

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-cert-spm` | 1247 tests in 187 suites passed, `ArchitectureTests` included |
| `ios/scripts/ci-compat-lint.py` | 0 findings |
| iOS build, simulator "Lab D 16PM", derived data `/private/tmp/merc-cert-ios-dd` (clean) | BUILD SUCCEEDED, with no warnings in the changed files |
| iOS `xcodebuild test` with CI's flags, Lab D | **TEST SUCCEEDED**: 31 of 31 (3 XCTest unit, 3 Swift Testing, 25 UI), no failures, no retries |
| Snapshot comparison with recording off (`SIM=<Lab D> DD=/private/tmp/merc-cert-ios-dd scripts/ios-unchanged-check.sh`) | "iOS unchanged": the same 23 results as the baseline (11 pass, the same 12 already-stale references fail with identical pixels) |
| Mac Debug build into `/private/tmp/merc-cert-mac-dd` | BUILD SUCCEEDED |
| Mac Release, universal (CI's job), same derived data | BUILD SUCCEEDED; `mac-bundle-check.sh … release` ok (arm64 + x86_64); the four fonts, both licences and the mark are in the bundle |
| Mac shots, copied app `com.mayoailiteracy.mercurius.native.macnscert1`, `ACTIVATE=NO` | all 10 ok; the founder's Mercurius was running before and after; the copy never came to the front |
| iPhone share sheet, tapped on Lab D (a scratch XCUITest runner, launched by bundle id) | the preview tile shows the certificate, not a blank square |

- **Snapshot comparisons:** none changed. No `ViewSnapshotTests` case renders the Progress hub, a passed unit check or the certificate, so no reference covers the new UI. `__Snapshots__` is untouched, and no record run was made.
- **Not run:** the Mac print and save panels at run time (the founder is using the Mac app, so the GUI wasn't driven), and CI's macOS 14 / Xcode 16.2 runtime.
- **The copied-app script:** `mac-copy-snapshots.sh` leaves iOS Simulator apps out of its "still running" check. They are also called Mercurius, and other worktrees' UI tests relaunched them mid-run, which the script reported as a Mercurius that had gone.

## Screenshots

**Committed:**
- `key-shots/` (JPEG, at most 1800 px, q85): both certificates from the app's PDF at 150 dpi, the two design | app comparisons, the iPhone name sheet and the Mac name sheet;
- `samples/certificate-deepDive.pdf` and `samples/certificate-basics.pdf`: the app's PDFs with the sample name and date (about 180 KB each);
- `compare/`: the full-size comparisons and overlays.

**Local only** (`shots/`, gitignored; `tools/make-compare.sh` re-makes the PDFs):
- `certificate-deepDive.pdf` and `certificate-basics.pdf`, with the sample name and date, each with a `-150dpi.png` and `.inspect.txt` (fonts, images, text); the same for the name samples `-short`, `-long` and `-60`;
- `ios/` (iPhone 16 Pro Max at half size): the name sheet (`sheet-deepDive`, `-dark`, `-xxxl`, `-ax3`, `-ax3-dark`; `sheet-basics`), the Certificates list (`list`, `-dark`, `-ax3`), the Progress hub (`hub`) and the course-complete card (`card`, `-dark`);
- `mac/` (copied app): `certificate-sheet`, `certificate-sheet-basics`, `certificate-list`, `certificate-hub` and `certificate-card`, each with `-dark`.

Re-take the Mac shots with:
```bash
N=cert1 SRC_APP=/private/tmp/merc-cert-mac-dd/Build/Products/Debug/Mercurius.app COPY_DIR=/private/tmp/merc-cert-copies \
  VARIANTS="light dark" scripts/mac-copy-snapshots.sh <dir> \
  certificate-sheet certificate-sheet-basics certificate-list certificate-hub certificate-card
```

## For the founder

1. **AI Basics' bottom columns are 40 px wider than the design** (290 px, not 250), so "INSTRUCTOR OR FAMILY MEMBER" sits on one line and the signature rule lines up with the date rule. The design's wrap put the signature line 18 px higher. Revert is one line (`CertificateLayout.columnWidth`) if the design's wrap is wanted.
2. **Settings' "Delete my data" wording** doesn't mention the certificate name, although the name is erased. Add "and the name on your certificate"?
3. **Mac App Review** will see two new entitlements: printing, and user-selected read-write.
4. **App size:** about 3.5 MB more, for the fonts.
5. **"Stays on this device"** is true of Mercurius: the name never reaches its servers. Like progress, it is in the device's own iCloud or computer backup (UserDefaults), which is the student's Apple backup, not Mercurius's.
