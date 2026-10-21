# Printable course certificates

Branch `feat/certificate`, stacked on `feat/mac-night-studio` (PR #48). Written 2026-10-21 with Xcode 26.4 / Swift 6.3. Not pushed.

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
| the footer | 740 | 740 |

Text goes by its baseline and the centre of its line box, letter-spacing included, as CSS centres it. SwiftUI's `tracking` also adds space after the last character, as Chrome's `letter-spacing` does.

**The seal** sets each glyph as SVG text-on-a-path does:
- the middle of each glyph's advance sits on the circle (r 56), turned to its direction;
- the run starts at 9 o'clock;
- `textLength="345"` spreads the extra room evenly between the characters (SVG 2 `lengthAdjust="spacing"`).

**The result** (`compare/`):
- **At 96 dpi** against Chrome at 1×, every line's ink box is within 1 px.
- **At 150 dpi** the overlays show fringes of up to about 2 px (1 pt), because Chrome lays out in device pixels at a 1.5625 scale factor and rounds each line box there. The PDF follows the CSS layout itself.
- **The frame, the rules, the seal and the mark** match to the pixel at both resolutions.

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
   - longer names break onto two balanced lines, up to 57 px on the Deep dive and 64 px on AI Basics, which keeps at least 24 px above the seal;
   - a break at a space beats one inside a double-barrelled name unless the hyphen sets it 10% larger;
   - one unbreakable word shrinks on its line;
   - input is capped at 80 characters.

   A one-line name keeps the design's 75.6 px line box, so a slightly smaller name doesn't move the rest of the page. Two lines push the paragraph down, as CSS would.

   Samples are in `shots/`:
   - "Li Wei" (`-short`);
   - "Alexandria Montgomery-Vasquez": one line at 72 px, as in the design;
   - a 44-character name (`-long`);
   - a 61-character name (`-60`).

### Kept as designed, worth a look

- **AI Basics' signature label wraps.** "INSTRUCTOR OR FAMILY / MEMBER" is wider than the design's 250 px column at 14 px with 0.12em tracking, so Chrome wraps it. The signature line then sits 18 px higher than the date line. The PDF reproduces this exactly, because it is what the founder approved.
- **The fix is one line in `CertificateCopy.signatureLabel`**, if they'd rather have one line: for example "Instructor or family", or a slightly tighter tracking.

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
- **Mac printing:** `NSPrintOperation` on a `PDFDocument`, Letter landscape, scaled to the printer's margins.
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
- **How it's erased:** "Delete my data & start over", "Reset this device only" and both consent withdrawals run `SettingsSheet`'s local wipe, which now calls `CertificateStore.reset()`. `SettingsResetTests` checks this.
- **Copy left alone:** Settings' wording ("erases your chats, lessons, streak and progress") is unchanged. Whether to add "and the name on your certificate" is the founder's call.

## Mac

- **The sheet** follows Night Studio's sheet conventions (the mode explainer's):
  - the indigo canvas;
  - an eyebrow ("AI LITERACY COURSE") and a display title;
  - a Night field;
  - a bottom bar with a text button, a secondary button and the one prominent button.
- **The card** is a `nightLit` card with a secondary button. The check's Done stays the one prominent button.
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
  - **Layout:** every baseline above, for both kinds; the Basics label; two-line names clear the seal and the column.
  - **Name fit, with a fake measure:** short, slightly long, long, hyphen preference, unbreakable, bounds for 10–80 characters, normalization.
  - **Name fit, with the real font:** "Li Wei" and "Alexandria Montgomery-Vasquez" stay at 72 px; 44–61-character names stay at 54 px or larger.
  - **The seal's run:** 345 px.
  - **Copy:** the US date; the VoiceOver summary.
  - **PDF:** one page; a 792 × 612 media box; text with the name, the title, the date and the footer; a two-line name; the four faces embedded; the 470 × 415 mark the only image.
  - An opt-in `CertificateShots` test writes the PDFs for `shots/`.
- **`EngagementFeatureTests/CertificateTests.swift`:**
  - **Eligibility:** Deep dive none, partial and complete; Basics with injected ids, none, partial and complete, with its date; the date rule.
  - **The store:** the name normalized; only its own key written, to the given defaults, never `.standard`; reset erases everything; the first dates stand.
  - **The center:** the seam; the eighth mastery as the moment; a certificate earned elsewhere; Basics through the seam; the hub row's summary; the sheet's privacy copy.
- **`AppFeatureTests`:**
  - **`CertificateWiringTests`:** the curriculum's units against the copy; the seam off in this build; mastery through the real progress store; Basics ids in the shared store.
  - **`SettingsResetTests`:** "Delete my data" and "Reset this device only" erase the name.
  - **`MacReleaseConfigTests`:** the new entitlements.

## Verification (2026-10-21, Xcode 26.4 / Swift 6.3)

| Check | Result |
|---|---|
| `swift test --scratch-path /private/tmp/merc-cert-spm` | 1236 tests in 187 suites passed, `ArchitectureTests` included |
| `ios/scripts/ci-compat-lint.py` | 0 findings |
| iOS build, simulator "Lab D 16PM", derived data `/private/tmp/merc-cert-ios-dd` | BUILD SUCCEEDED, with no warnings in the changed files |
| iOS `xcodebuild test` with CI's flags, Lab D | **TEST SUCCEEDED**: 3 XCTest unit, 3 Swift Testing and 25 UI tests, with no failures and no retries |
| Snapshot comparison with recording off (`SIM=<Lab D> DD=/private/tmp/merc-cert-ios-dd scripts/ios-unchanged-check.sh`) | "iOS unchanged": the same 23 results as the baseline (11 pass, the same 12 already-stale references fail with identical pixels) |
| Mac Debug build into `/private/tmp/merc-cert-mac-dd` | BUILD SUCCEEDED |
| Mac shots, copied app `com.mayoailiteracy.mercurius.native.macnscert1`, `ACTIVATE=NO` | all ok; the founder's Mercurius was running before and after; the copy never came to the front |

- **Snapshot comparisons:** none changed. No `ViewSnapshotTests` case renders the Progress hub or a passed unit check, so no reference covers the new UI. `__Snapshots__` is untouched, and no record run was made.
- **The copied-app script:** `mac-copy-snapshots.sh` now leaves iOS Simulator apps out of its "still running" check. They are also called Mercurius, and other worktrees' UI tests relaunched them mid-run, which the script reported as a Mercurius that had gone.

## Screenshots

**`shots/` (the PDFs):**
- `certificate-deepDive.pdf` and `certificate-basics.pdf`, with the sample name and date, each with a `-150dpi.png` and `.inspect.txt` (fonts, images, text);
- the same for the name samples `-short`, `-long` and `-60`.

**`shots/ios/`** (iPhone 16 Pro Max at half size):
- the name sheet: `sheet-deepDive`, `-dark`, `-xxxl` (the largest standard size), `-ax3` and `-ax3-dark` (AX3 = Accessibility Extra Large); `sheet-basics`;
- the Certificates list: `list`, `list-dark`, `list-ax3`;
- the Progress hub: `hub`;
- the course-complete card: `card`, `card-dark`.

**`shots/mac/`** (copied app, half size):
- the sheets: `certificate-sheet`, `certificate-sheet-basics` (with `-dark`);
- `certificate-list` and `certificate-hub` (with `-dark`);
- `certificate-card` (with `-dark`).

Re-take the Mac shots with:
```bash
N=cert1 SRC_APP=… COPY_DIR=… VARIANTS="light dark" \
  scripts/mac-copy-snapshots.sh <dir> certificate-sheet certificate-sheet-basics certificate-list certificate-hub certificate-card
```

## For the founder

1. **AI Basics' signature label** wraps onto two lines, as the design does; the signature line then sits higher than the date line. Keep it, or make it one line?
2. **Settings' "Delete my data" wording** doesn't mention the certificate name, although the name is erased. Add "and the name on your certificate"?
3. **Mac App Review** will see two new entitlements: printing, and user-selected read-write.
4. **App size:** about 3.5 MB more, for the fonts.
