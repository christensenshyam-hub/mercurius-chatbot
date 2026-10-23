> **Stacked on the iPhone tokenizer PR (`feat/ios-tokenizer`)**, which is itself stacked on #48 → #47 → #43. This PR's own changes are the commits after `544ddd6` (the tokenizer branch's tip, merged in again here). Once the tokenizer PR merges, retarget this PR to `main`.

# Lesson interactives, wave 1: five cards on one shared framework

## What it is

The founder asked for more interactives like Lesson 1.1's tokenizer, spread through the curriculum. This PR adds the shared framework and the first wave of five cards from the approved slate, on the iPhone (today's lesson design) and the Mac (Night Studio).

**Every new card ships dark.** Each has `enabled: false` in `InteractiveRegistry`, so no student sees one until its teacher review is signed off in its CONTENT.md and the founder OKs a separate one-line commit. In DEBUG builds, `-Interactive <slug>` shows a dark card in its lesson, and `-InteractiveGallery <slug>` shows it alone. Lesson 1.1's tokenizer is registered through the framework, and its behaviour is unchanged.

Every card follows the same rules:
- **Offline and deterministic.** No network, no live model, nothing stored or sent. Every example is authored and labelled on the card. Every number either comes from the lesson guide or is labelled toy data that the code re-derives, and a test checks every displayed number.
- **Predict first, one control.** The student locks in a guess before anything moves. The reveal puts the guess beside what happened, and never gives a score.
- **Placement.** Only in its own lesson, after the part of the first teach reply that holds the example, before that reply's check. Once per thread. Never mid-stream, never in a thread with a crisis line, never in a cut-off reply. Stable when the lesson is reopened. **No wire or prompt change.**

## The five cards

| | Card | Lesson | The aha |
|---|---|---|---|
| ★1 | **The Doubt Dial** | U6 L4 · Misinformation and the liar's dividend | No amount of doubt sorts real from fake. Doubting everything just waves away every real story; checking is what works. |
| ★2 | **The Bake-Sale Agent** (slate name: The Page with a Secret) | U8 L1 · From chatbots to agents | To an agent, text it reads can act like an instruction, even text you can't see on the page. |
| ★3 | **The Citation That Wasn't** | U1 L3 · Why AI sounds confident but can be wrong | No single step decides to make anything up. Each piece is just a likely next piece, and likely pieces can add up to a study that never existed. |
| ★4 | **Delete the Gender Box** | U3 L1 · AI in hiring and employment | Delete the gender field and the bias stays. "Women's" carried the same signal from a skewed past, so the scorer marked it down even more than before. |
| ★5 | **Patch the Reward** | U5 L1 · The alignment problem | The boat does exactly what the points pay for. Two of three patches leave a gap between the rule and what you meant, and nothing about it is broken or sneaky. |

### ★1 The Doubt Dial (U6 L4)

The student sees ten one-line posts about a made-up town (5 real, 5 fake, each with a "how surprising" score from 1 to 5). They guess which setting fools them least, then turn a five-stop dial from "Believe everything" to "Doubt everything" and count the mistakes. Every setting makes at least 4 mistakes, and "Doubt everything" waves away all 5 real stories. "Check first" then sorts 8 of 10 and is honest about the other 2: not sure yet.

![The Doubt Dial on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/doubt-dial-iphone.jpg?raw=true)
![The Doubt Dial on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/doubt-dial-mac.jpg?raw=true)

### ★2 The Bake-Sale Agent (U8 L1)

The student asks an agent to plan a robotics-club bake sale and steps through its Plan → Act → Observe loop. It reads a made-up recipe page. The student guesses what happens next, then flips the page from "You see" to "The agent reads" and finds a white-on-white line. The agent's plan, list and draft email now push a brand the student never asked for. The takeaway names prompt injection.

![The Bake-Sale Agent on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/page-with-a-secret-iphone.jpg?raw=true)
![The Bake-Sale Agent on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/page-with-a-secret-mac.jpg?raw=true)

### ★3 The Citation That Wasn't (U1 L3)

The student asks for a study showing that houseplants help students concentrate. They then guess each piece of the reference (author, year, title, journal, pages) as an illustrative model draws it from labelled chances. Next they guess at which step the model decided to make it up. The answer is that no step did. "Write it again" draws a different, equally tidy fake.

![The Citation That Wasn't on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/citation-that-wasnt-iphone.jpg?raw=true)
![The Citation That Wasn't on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/citation-that-wasnt-mac.jpg?raw=true)

More: [the five drawn pieces (iPhone)](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/citation-that-wasnt-iphone-revealed.jpg?raw=true) · [the rewrite (Mac, dark)](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/citation-that-wasnt-mac-rewritten.jpg?raw=true)

### ★4 Delete the Gender Box (U3 L1)

The student audits a toy résumé scorer. It is fitted on the device to 12 made-up past résumés (6 of 8 men hired, 1 of 4 women). Two new résumés differ only by "women's", and score 34 against 63. The student bets on what deleting the gender box will do to that 29-point gap, then deletes it. The toy is refitted, and the gap grows: 42 against 77, because "women's" now pushes down harder (−1.21 to −1.53).

![Delete the Gender Box on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/delete-the-gender-box-iphone.jpg?raw=true)
![Delete the Gender Box on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/delete-the-gender-box-mac.jpg?raw=true)

### ★5 Patch the Reward (U5 L1)

A toy boat race, with a lagoon of star targets that keep coming back. The student watches the 2016-style rule ("+10 per target hit") loop in the lagoon for 0 laps. They then try three patches, predicting before each run whether the boat will finish. An exact planner, worked out ahead of time, gives each rule's best-scoring route: A rocks over the finish line, B cruises the open lagoon, and only C (a full lap through gates 1, 2, 3 in order) finishes.

![Patch the Reward on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/patch-the-reward-iphone.jpg?raw=true)
![Patch the Reward on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/patch-the-reward-mac.jpg?raw=true)

More: [the track's marks in three runs (iPhone)](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/patch-the-reward-iphone-track.jpg?raw=true)

### The five together

Each card's reveal, side by side on the merged build:

![The family on the iPhone](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/family-iphone.jpg?raw=true)
![The family on the Mac](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/key-shots/family-mac.jpg?raw=true)

Each card's own key shots show an iPhone 16 Pro Max at Large, light. The left panel is the card's top in its lesson, the right panel is its reveal (`-Interactive <slug> -InteractiveState revealed -InteractiveScroll reveal`). The Mac shots show the top in light and the reveal in dark, taken from a renamed copy of the app.

## The framework

A new package, `ios/Packages/LessonInteractives`. It depends on DesignSystem only, and two tests enforce that: the ArchitectureTests content-module rule and the NoIO source scan. So no card can reach the network or storage. The full guide is [`docs/interactives/FRAMEWORK.md`](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/FRAMEWORK.md).

- **Registry** (`InteractiveRegistry`):
  - one row per card, keyed by lesson id, with its anchor rule (`firstExample`, `teachReply(n)`, `firstReplyMentioning(terms, fallback:)`), spoiler terms, wave and `enabled`;
  - tests enforce one card per lesson, none in a Review lesson, and only built cards enabled.
- **Placement** (ChatFeature, `Lesson/LessonInteractive.swift`):
  - the tokenizer's rule, generalised (moved from `Tokenizer/`);
  - a spoiler scan that runs once, when the place is found. Its flag is kept with the placement, so it never flips while the lesson is open. A spoiled card skips its guess.
  - the iPhone bubble split and the Mac reply mounting are card-agnostic.
- **Logic blocks:**
  - shared: `PredictReveal` (hook → locked → exploring → revealed, with a spoiled mode), `ThresholdCounters`, `StepThrough`;
  - one card each: `ToyFit` (logistic regression, solved exactly by Newton's method) and `RoutePlanner` (an exact planner).
- **Shared views,** each with iPhone and Mac styling hooks (`InteractiveTheme`, `.interactiveText`):
  - the card shell: the iPhone night-sky island, and the Mac lit card with its compact "Try it" below 440 pt;
  - `PredictChips`, `RevealBox`, `InteractiveTakeaway`, `CounterTiles`, `StopControl`, `InteractiveSegmented`, `StepControls`, `LabelLine`;
  - chips and buttons with 44 pt targets and a selection haptic on the iPhone, and the Mac keyboard contract (Tab, Space/Return, ←/→ where a control takes them; a focused control holds Return so the lesson's check never locks from it).
- **Scroll hook:** `\.interactiveScrollIntoView` lets a card bring a part of itself into view after a tap, counted as the student's own move. Patch the Reward uses it to show the track while a run plays.
- **DEBUG paths:**
  - `-Interactive <slug>` streams stub replies that say they are stubs;
  - `-InteractiveGallery <slug>`;
  - `-InteractiveState hook|predicted|explored|revealed|spoiled`;
  - `-InteractiveScroll top|reveal|after`;
  - `-InteractiveStubSpoiled YES`.

  `mac-snapshots.sh` takes `interactive-<slug>` and `gallery-<slug>` shots. Release builds read no arguments.

### Merge-time changes (this branch, after the five card branches)

- **Shared chip, reconciled.** Two card branches had each fixed the locked guess's contrast. The merge keeps both fixes:
  - from the Citation branch, `isLocked`: a locked chip is no longer a control, so the pick stays white on `prominent` and the others read in `ink2`, 4.5:1 or better;
  - from the Page branch, a chip that can't be picked yet is still a control. VoiceOver and XCUITest hear it "dimmed", and on the iPhone nothing fades.
  - The chip's check now grows with Dynamic Type on the iPhone, so it is no longer a speck at AX5.
- **One family.** The five cards were laid side by side on the merged build. A new test, `InteractiveFamilyRenderTests`, renders each one at 408 pt in its hook, guessed and revealed states. These changes bring them into line:
  - The Citation's title is now in Title Case, like the slate and the other cards.
  - Every takeaway uses the same style: a bold `ink` line, through the new `InteractiveTakeaway` (or `RevealBox(takeaway:)`). Delete the Gender Box and Patch the Reward had theirs in reading text. Each is now split into the line and its detail (the Reuters case, or why C worked), with the words unchanged.
  - Delete the Gender Box's hook is in `ink` like every opening, and its slate label moved from the card's foot to just under the hook. Every card's main label now comes before its guess.
  - "Write it again" and "Play it again" share one glyph (↺).
  - FRAMEWORK.md §4.5 records these rules for wave 2.
- **Lesson 1.1's iPhone review fixes** from `feat/ios-tokenizer` are merged in again:
  - the card that follows an [EX] or [KEY] block no longer draws a stray rule;
  - "Try it" jumps to step 4.

## Accuracy and sources

Each card has a CONTENT.md. It lists every line the student sees or hears, every number with its derivation, every factual claim with its status and source, the invented-name searches, the VoiceOver script and the teacher checklist.

| Card | CONTENT.md | Main sources |
|---|---|---|
| The Doubt Dial | [doubt-dial/CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/doubt-dial/CONTENT.md) | Guide U6L4 and fact-check row 50 (Chesney & Citron 2019); Caulfield's SIFT and *Web Literacy for Student Fact-Checkers*; Paris & Donovan 2019 (cheap fakes); Allen et al. 2020 and Acerbi, Altay & Mercier 2022 for the label "Real feeds aren't half fake". The feed is labelled toy data. |
| The Bake-Sale Agent | [page-with-a-secret/CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/page-with-a-secret/CONTENT.md) | Guide U8L1; Greshake et al. 2023 (indirect prompt injection); the Guardian's December 2024 ChatGPT search tests; Anthropic's Claude for Chrome post; RFC 2606 (`.example` names). The run, page and email are authored and labelled. |
| The Citation That Wasn't | [citation-that-wasnt/CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/citation-that-wasnt/CONTENT.md) | Guide U1L3; *Mata v. Avianca* (S.D.N.Y. 2023, Doc 54, read in the original); 3Blue1Brown, *But what is a GPT?* (one sampled piece at a time); Walters & Wilder 2023 (fabricated references borrow real journal names, a teacher note); Anthropic's *On the Biology of a Large Language Model* (a teacher note); a new fact row for "models usually sample" (to be verified). The chances are labelled illustrative. |
| Delete the Gender Box | [delete-the-gender-box/CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/delete-the-gender-box/CONTENT.md) | Guide U3L1 and fact-check row 24 (Reuters 2018 on Amazon's scorer); Google PAIR's "Hidden bias" explorable for the design. The toy is fitted on the device, and an independent Python refit matches every weight and score. |
| Patch the Reward | [patch-the-reward/CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/interactives/patch-the-reward/CONTENT.md) | Guide U5L1 and fact-check row 33 (OpenAI 2016, "Faulty reward functions in the wild"); DeepMind's specification-gaming post and list. The track and routes are toy data from an exact planner. |

Lesson 1.1's tokenizer keeps its own [CONTENT.md](https://github.com/christensenshyam-hub/mercurius-chatbot/blob/feat/interactives-wave1/docs/mac-night-studio/tokenizer/CONTENT.md).

**Minors:** no real faces or voices, only synthetic people, and no real person accused of anything. The only real companies named are the ones the slate allows (Amazon, through Reuters; OpenAI's and DeepMind's own posts; ChatGPT in *Mata*). Invented names (Port Avery, Whiskwren, Flurrow, Quillfeather and the rest) were searched, with dates in each CONTENT.md.

## Teacher checklist (before any card is enabled)

A teacher (the club advisor, or the founder acting as one) walks each card on an iPhone and on the Mac, inside a real lesson run (BUILD_PLAN.md §4.5):
1. The aha lands in about 90 s, without the tutor's help.
2. Every label is visible and understood: example, toy or made-up, our arithmetic, dated.
3. The language is at a 9th-grade level, and nothing reads as live AI or as Mercurius's own output.
4. The tutor's reply in that run didn't spoil the prediction (or the spoiled mode read well).
5. **Exercise clash:** do the lesson's exercise right after the card. The card must not have answered it.
6. **Ethics for minors:** no real faces or voices, no graphic content, no dark patterns, and real cases only with the guide's facts.
7. **Accessibility:** a VoiceOver-only pass, AX5 on an iPhone SE, keyboard-only on the Mac, Reduce Motion, Increase Contrast.

The sign-off goes in the card's CONTENT.md with a date. Each card's own list of what to check is there too:
- **The Doubt Dial** (§11): the reveal's wording ("someone caught in a real story", "You're right: the middle fooled you least"), the R/F strip's key, and whether the label "Real feeds aren't half fake" is acceptable.
- **The Bake-Sale Agent** (§7): three preconditions before it is enabled.
  - A guide line telling the tutor not to open U8L1 with hijacking, hidden instructions or the Guardian case. **Under today's guide, all 4 recorded first replies spoil the guess.** This is a prompt change, so it is not in this PR.
  - `eval-pacing --runs 3` in both `USE_UNIFIED_PROMPT` states.
  - The teacher's sign-off.

  Also: a 3–5 student think-aloud, the C5 fact-check row, and trademark checks for Whiskwren and Flurrow.
- **The Citation That Wasn't** (§8, §10): approve the wording changes from the slate. The takeaway assumes Merc's reply above mentions Mata. Two items remain open: the ISSN Portal and Scholar search of the invented names, and the new fact row.
- **Delete the Gender Box** (§8): the bet question "…scores 29 points lower. What will that gap do?", the nuance line, the old-records line, and "Weights aren't points".
- **Patch the Reward** (§6): whether the auto-scroll feels natural, whether the new takeaway and "stand-in" are clear, and whether the "+100" pops and A's "×30" make the loophole obvious. Fact-check row 33 rates "catching fire" Medium. OpenAI's own post says it, so it should be High; that doc is on the prompts branch.

## Tests

Run on the merged branch (2026-10-22). CI is Xcode 16.2 / Swift 6.0.3 on macOS 14.
- **`swift test`** (`ios/Packages`, from an empty scratch path): **1,441 tests in 222 suites pass.** That includes:
  - each card's suite, which re-derives every number it shows from the authored data;
  - the copy rules, labels, VoiceOver summaries and state machines;
  - the placement, spoiler and stub tests in ChatFeature, and the registry against `Curriculum.swift`;
  - ArchitectureTests' content-module rule, and the NoIO scan;
  - Lesson 1.1's tests, unchanged.
- **CI lint:** `ios/scripts/ci-compat-lint.py` finds 0 issues.
- **iOS build and `xcodebuild test`** on an iPhone 16 Pro Max simulator (iOS 26.4), with snapshot recording forced off:
  - **Unit tests, 16 of 16 pass:** the card layout tests (the real views at an SE's and a 16 Pro Max's width, from Large to AX5: nothing leaves a card), the new `InteractiveFamilyRenderTests`, and the tokenizer's.
  - **UI tests, 44 of 44 pass.** The first full run passed 41. The other three card tests still looked for the locked guess among the buttons, and the merged chip is no longer a button once locked; they were fixed and pass. A second run of every card and launch UI test passed, except the Citation's AX5 walk once under machine load; it passed when re-run alone.
- **Snapshots:** `ios-unchanged-check.sh` gives the same 23 results as the baseline (11 pass, 12 already stale), with the same pixels for every stale render. No record run.
- **Mac:**
  - the Debug build and the unsigned universal Release build (`x86_64 arm64`) both succeed;
  - the shots were taken from a renamed copy of the app (`….macnsiamerge`), and the founder's running app was never touched.
- **Not done here:**
  - a VoiceOver pass and AX5 on a real iPhone SE, which are teacher-checklist items. The layout tests cover the SE's width at AX5.
  - a placement eval on real tutor replies. No prompt or wire change is in this PR.

## Not in this PR: wave 2, and the founder's decisions

**Wave 2** (six cards, each already in the registry as dark, with a placeholder view):
- Who's in the Test? (U2L3)
- The Ward of 1,000 (U3L2, `firstReplyMentioning(["sepsis"])`)
- Predict the Exam (U7L1)
- Two Tests, One Line (U2L2, `teachReply(2)`)
- Grown from Static (U6L1)
- Read My Mind (U4L1)

Wave 2 waits on these decisions:

| | Decision | Recommendation | Blocks |
|---|---|---|---|
| D1 | Placement after the first teach reply: a beat index with a spoiler fallback, or a marker the tutor emits | A beat index with a spoiler fallback now; a capability-gated marker later if evals show drift | The Ward of 1,000, Two Tests, One Line |
| D2 | One guide-line batch (U2L2, U2L3, U3L2, U7L1) stacked on PR #44, gated by `eval-pacing --runs 3` in both flag states | Yes, alongside wave 1 | Who's in the Test?, The Ward of 1,000, Predict the Exam, Two Tests, One Line |
| D3 | Name IBM on the Gender Shades card | Yes, dated 2018 | Who's in the Test? |
| D4 | U6L1 frames: which open model, or a labelled animation | Real frames: CommonCanvas first, SDXL as the fallback, licence checked | Grown from Static |
| D5 | A Unit 4 card (open question 1 on the curriculum map) | Yes, Read My Mind, built last | Read My Mind |
| D6 | A cap of one card per lesson | Keep | (none) |

**Wave 1 decisions for the founder:**
- **The ★2 title:** "The Bake-Sale Agent" (on the card now) or the slate's "The Page with a Secret". A page "with a secret" answers the prediction before it is asked. Reverting is one constant, `PageWithASecretCopy.title`.
- **The guide line ★2 needs** before it can be enabled (above).
- **★4's bet:** "What will that gap do? Shrink / Stay the same / Grow" replaces the slate's "Will it still score lower?" The weights on screen, and the tutor's Amazon line, already answered the slate's version.
- **Enabling:** each card is enabled in its own commit, after its teacher sign-off, and only with the founder's explicit OK.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
