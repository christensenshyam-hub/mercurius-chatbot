# Step 01: stream transforms (AUD-17, AUD-18, AUD-38)

Branch `fix/server-2026-10`, from `main` at `720dbac`. No prompt text changed. `CURRICULUM_PROMPT`, the source library and `SAFETY_CORE` are untouched. The `server.js` edits are in the `/api/chat` handler only.

## Commits

| Commit | What |
|---|---|
| `5b69c8c` | **AUD-17.** Reflow keeps numbered lists and Discussion score lines whole. |
| `ddff378` | **AUD-18.** Each `[Q]` check's options go out in a stable server order for blocks_v1, with `ANS` rewritten. Also adds `lib/replyPipeline.js`, the mock's `MOCK_REPLY:` and `scripts/quiz-order-stats.mjs`. |
| `e332cba` | **Reflow, found by the new fuzz.** The abbreviation guard depended on chunk boundaries. This bug was already on `main`. |
| `b7fc087` | **AUD-38.** `[SOURCE: …]` reaches blocks_v1 clients as plain text, and the eval metrics read the new form. |
| `b6085bc` | **AUD-17 follow-up in the eval.** The airy metric now exempts list lines one by one, as the reflow does. |
| (last) | These notes and the two eval result files. |

## What changed

### One pipeline for every reply (`lib/replyPipeline.js`)

The SSE stream and the JSON path now run the same chain of transforms:

1. Source rewrite. Runs only for blocks_v1 clients that are not the widget.
2. Quiz order. Runs only for blocks_v1 clients.
3. Reflow.

`transformReply(text, opts)` is `push(text) + flush()` on a fresh pipeline. So these four are always the same bytes:

- the streamed deltas;
- the `complete` frame's reply;
- the JSON reply;
- the saved assistant turn.

Every stage is chunk-boundary independent, and so the whole chain is too. Each stage holds back only text it can't decide on yet:

| Stage | What it holds | Most it holds |
|---|---|---|
| Source rewrite | from `[SOURCE:` to its `]` | 400 chars |
| Quiz order | from `[Q]` to its `[/Q]` | 2000 chars |
| Reflow | a partial marker, or a sentence end it can't classify yet | (unchanged) |

Any text still held when the stream ends goes out as written.

The non-blocks scrub (`scrubBlockMarkers`) and the refusal path are unchanged. `REFUSAL_COPY` still skips the transforms.

### AUD-17: numbered lists and score lines (`lib/airyReflow.js`)

**Numbered lists.** A line-leading `1.` or `12.` is now read as a list marker, so the line classifies as a list. Before, a tight numbered list split at the paragraph limit, for example `2.\n\nType the prompt`. A `1)` marker already worked. A decimal such as `1.5 million`, or a 4-digit year, is still prose.

**Score lines.** Lines that start `**Label: n/5**` or `**Label:** n/5` (this covers `**Overall: 11/25**`) are score lines. Their sentences are not counted, so the rubric is never split 2-2-1 and `both?` is never orphaned.

**Hard breaks.** The newline that ends a score line becomes a markdown hard break: two spaces, then `\n`.

- iOS: MarkdownUI's soft break is a space, and no shipped build overrides it. Without the hard break, the five lines that are now kept together would run into one paragraph on 2.0.0 and 2.3.0, which is worse than today's 2-2-1. MarkdownUI renders `.lineBreak` as `"\n"` (checked in its `AttributedStringInlineRenderer`).
- Widget: it already strips trailing spaces and joins the lines with `<br>`, so it looks the same as before.
- The pad counts the spaces already there, so it never stacks, and running the reflow twice is a no-op.

**Prose lines.** A line that ends a sentence before its prefix has classified is now prose. The terminal never reached `linePrefix`, so that line could otherwise turn into a list or score line later.

**Fix found by the fuzz (`e332cba`).** The abbreviation lookback was `recent + buf.slice(i-12, i+1)`, but `recent` already ends with those characters. So when a chunk began inside a word, `v` + `v.` read as `vv.`, and `Mata v. Avianca` split or not depending on where the chunks fell. The lookback is now `recent + ch`.

**Eval metric (`b6085bc`).** `maxParagraphSentences` exempted only paragraphs made entirely of list lines, and counted `1.` `2.` `3.` as sentence ends. An intro line followed by a tight list is one paragraph.

- Once lists stay whole, real lesson exercises measured 5–6 "sentences" against the longform max of 4. The old reflow hid this by splitting the list at `2.`.
- List lines are now exempt one by one.
- On all 1508 replies recorded in `docs/evals`, the metric never goes up, and goes down on 17.
- PR #44 doesn't touch this function.

### AUD-18: `[Q]` option order (`lib/quizShuffle.js`)

The order is options sorted by `sha256("quiz-order-v1", stem, option text)`, and `ANS` is rewritten to the same option. Only the letters and the `ANS` letter move. Every line's text and the layout are untouched.

**Why I didn't permute by the stem alone, as the brief says.** That order is applied to whatever order the model wrote. PR #44 tells the model to repeat an open `[Q]` "word for word" from its history, and the history holds the already-reordered block. A stem-only permutation would scramble that repeat into a new order. Sorting by the keyed hash gives the same order for the same stem and options whatever order the model used. That makes the transform idempotent: the client's stored block, the student's `I picked B) …` and the model's history all agree. The order is still a stable hash keyed by the stem.

**What passes through byte for byte:**

- any block that isn't exactly: stem lines, then `A) ` `B) ` … in letter order (2–4 options, distinct texts, a space after `)` as iOS requires), then one `ANS: X` naming one of them;
- a block with another marker inside;
- positional wording: `All/None/Both of the above`, `Both A and B`, `option A`, `A)` inside an option;
- an unclosed `[Q]`, or one whose `[/Q]` isn't within 2000 chars.

**Safety check.** After reordering, the block is parsed again. Unless it has the same options and the same right answer text, the model's block goes out instead.

**iOS.** Unchanged. It parses options in the order they appear and grades by the `ANS` letter. A test mirrors `BlockParser.parseQuiz` line for line and checks that it reads the reordered real blocks the same way the server does.

**Streaming.** The block now reaches the client whole, when its `[/Q]` arrives (about 250 chars). Before, its stem and options appeared line by line.

### AUD-38: `[SOURCE]` as plain text (`lib/sourceTags.js`)

**What iOS does today.** `grep -rn SOURCE ios/Packages` finds nothing on `main` or in PR #43, so the raw bracket text shows. iOS's partial-marker hold-back doesn't know `[SOURCE:` either, so `[SOURCE: Gen…` streamed in raw.

Now each tag keeps its label and its domain, and any path is dropped. The format depends on where the tag sits:

| Where the tag sits | Becomes |
|---|---|
| Own line, after a sentence, after a `Label:`, after a block marker | `Source: label (domain)` |
| Mid-sentence | `(Source: label, domain)` |
| Right after `(` | `Source: label, domain` |

I added the mid-sentence form because 14 of the 92 real tags sit mid-sentence or inside parentheses. Without it, those read as "…approved COMPAS Source: Machine Bias (propublica.org) while…".

**Edge cases:**

- A tag with no domain keeps its label, for example `Source: NIST 2024`.
- An empty tag is dropped.
- Text that only looks like a tag passes through: a newline or `[` before the `]`, no `]` within 400 chars, `[SOURCES]`, or lowercase `[Source:`.

**Which clients get it:**

| Client | Behaviour |
|---|---|
| blocks_v1, not the widget (iOS 2.2+) | rewritten |
| Widget (`club_v1`, even if it also sends blocks_v1) | keeps `[SOURCE: …]`, which `renderEmphasis` turns into a `merc-source` pill |
| No capabilities (iOS 2.0.0, curl) | gets exactly what it got before |

**Eval.** `scripts/eval-pacing.mjs` strips the rewritten forms the way it strips a raw `[SOURCE:]` tag, and a reply that ends on one doesn't count as truncated. Both regexes live in `lib/sourceTags.js`. This is three lines in the script, away from PR #44's edits; the airy-metric fix (`b6085bc`) adds one more small hunk.

### Test support

- `lib/anthropicMock.js`: when the last user turn contains `MOCK_REPLY:`, the mock streams the text after it verbatim, in 12-char chunks. Route tests use it to play exact `[Q]` and `[SOURCE]` replies through the real server.
- `scripts/quiz-order-stats.mjs <dirs…>`: prints the answer-letter spread before and after the reorder, and how often the right answer is the longest option. Read-only.

## Tests

`npm test`: 1031 pass, 0 fail. `main` had 959, so this step adds 72.

**`tests/airyReflow.test.js` (+10):**

- the audit repro at limits 2 and 3;
- `1)` lists and indented items;
- list items next to prose, and numbers that aren't markers;
- two real lesson exercises and the three real Discussion score blocks from the audit;
- the `**Label:** n/5` form, and a bold heading that is not a score line;
- idempotence of the hard break;
- random chunk fuzz;
- every two-way split for abbreviations.

The fixture is `tests/fixtures/reflowAudit2026-10.json`. Its `raw` texts are ones the OLD reflow turns into the recorded replies byte for byte. That is how I reconstructed the model text, because the transcripts only kept the reflowed reply.

**`tests/quizShuffle.test.js` (31):**

- the reorder and the `ANS` rewrite;
- determinism across model orders;
- idempotence;
- six real audit checks, all answered B, read the same by the server parser and the iOS-parser mirror (the letters are pinned);
- spread over 600 synthetic 3- and 4-option checks;
- 20 cases that pass through untouched;
- unclosed blocks, the 2000-char limit, indentation;
- every two-way split of a reply;
- 300 random chunkings that check no partial block is ever emitted.

**`tests/sourceTags.test.js` (12):**

- all 18 distinct real tags from the corpus;
- the invented-docket case;
- the four placements;
- tags with only a label, and empty tags;
- the parser's separators;
- look-alikes, and a tag that never closes;
- every two-way split, and 300 random chunkings that check no raw tag text leaks;
- the eval regexes.

**`tests/replyPipeline.test.js` (5):**

- without the quiz stage, the output is exactly the reflow;
- with all three stages, they apply in order;
- chunk fuzz over 5 option sets;
- text still held at the end of the stream goes out whole.

**`tests/replyTransforms.test.js` (11), route tests against the real server with the mock:**

- blocks_v1 SSE: deltas, complete reply and saved turn are all the reordered block, and no delta frame ever ends inside a block;
- JSON path;
- a malformed `[Q]`;
- a non-blocks client keeps the model order and the existing scrub;
- a numbered list and a score rubric arrive whole;
- `[SOURCE]` on SSE, JSON, the saved turn, and a lesson with a `[Q]`;
- the widget, and the widget plus blocks_v1;
- a client with no capabilities.

**Also:** `tests/evalPacing.test.js` (+2), for the rewritten source in the metrics and for list lines under an intro line, and `tests/anthropicMock.test.js` (+1), for `MOCK_REPLY:`.

## Measurements

**Corpus:** every JSON under `docs/audits/2026-10` (audit worktree) and `docs/evals`. Each distinct block or reply is counted once.

### AUD-17: split list markers

23 distinct replies had a split marker: 5 audit lesson transcripts and 18 eval replies. For all 23, the old reflow reproduces the recorded reply byte for byte from the reconstructed text, at limit 3. The new reflow leaves 0 split markers.

### AUD-18: answer position

Command: `node scripts/quiz-order-stats.mjs ../audit-2026-10/docs/audits/2026-10 docs/evals`. I ran it before this step's own eval files existed; a rerun now also counts their 5 already-reordered blocks. All 127 well-formed blocks have 3 options.

| Set | Before | After |
|---|---|---|
| All 127 well-formed blocks | A 4%, **B 77%**, C 19% | A 35%, B 43%, C 22% |
| One per distinct stem (106) | A 5%, **B 77%**, C 18% | A 35%, B 42%, C 23% |
| Audit transcripts + replays only (51) | A 8%, **B 80%**, C 12% | A 33%, B 41%, C 25% |
| 30,000 random synthetic checks (sanity) | — | 33.4% / 33.1% / 33.6% |

**Why B is still above a third.** The order is a hash, so for one fixed stem it is fixed, not re-rolled. 21 of the 127 blocks hash to the model's own order, which is the expected 1 in 6, and those stay at B. The rest is the luck of one fixed salt on a small corpus (χ² ≈ 6.4, df 2, on the distinct stems). The same real blocks under 500 different salts come out 33.3% / 33.3% / 33.4%, so the method has no bias. I did not tune the salt to make this corpus look flat. This corpus leaves out this step's own eval runs, whose blocks were already reordered.

**Untouched blocks.** 21 of 127, and all 21 are blocks whose server order equals the model's order. None were positional, and none were outside the strict shape.

**The right answer is the longest option.** Before: 117/127 (strictly 114). After: the same, by construction.

- I skipped this tell, and no transform can safely fix it. The only levers are rewriting option text (padding distractors or trimming the answer), and either one changes what the question says.
- PR #44's appendix now asks for distractors of similar length, with at least one longer than the correct option. The eval should measure this; see the risks below.

### AUD-38: source tags

- 92 real tag occurrences in 88 replies.
- 62 carried a URL path (67%). After the rewrite, none do.
- Placement: 78 on their own line or after a sentence, 11 mid-sentence, 3 inside parentheses.
- 0 tags are left unrewritten in any reply.

## Real-API check

**Setup.** One full `eval-pacing` run in each flag state, against servers built from `b7fc087`:

- the start line from the brief, on ports 3371 (`USE_UNIFIED_PROMPT=1`) and 3372 (`=0`);
- SQLite in `/private/tmp`;
- both servers killed afterwards, and both ports confirmed free.

Spend was about $0.43 (on) and $0.35 (off), from the exposed usage. This step changes no prompt, so this is a sanity run, not the 3-run merge gate.

**Results:**

- `docs/evals/pacing-server-batch-01-transforms-flag-on.json`: **32/32 pass**.
- `docs/evals/pacing-server-batch-01-transforms-flag-off.json`: **32/32 pass**.
- Both files were then rescored (`--rescore`) with the `b6085bc` metric. All criteria still pass, and flag-off's longform airy max went from 4 to 3.

**Blocks scenario:**

- 2 (on) and 3 (off) real `[Q]` checks went out in the server's order.
- All five were in the strict shape and parsed cleanly.
- The eval's taps graded consistently: the model answered the deliberately wrong pick with "Close — but that's actually a different step…".
- One real `[SOURCE]` inside an `[EX]` card came out as `Source: Attention Is All You Need (arxiv.org)`.
- No raw tag was left in any blocks reply.

**Discussion.** All 5 real rubrics (2 on, 3 off) arrived as one block of whole lines with hard breaks. The eval's Discussion scenarios send no capabilities, so their `[SOURCE: …]` stayed raw, as designed.

**Where the five checks' answers landed:** B, B, B, B, C. That is chance, not bias:

- 500 different salts over the 132 real blocks give 33.3% / 33.3% / 33.4%.
- The fixed salt `quiz-order-v1` happens to favour B a little on today's corpus (42–43%).
- Real lessons generate new stems each time, so what students see is uniform in expectation.
- I did not tune the salt to the corpus.

## Decisions to review

1. **The `[Q]` order is a hash of stem plus option text, not a permutation from the stem alone.** This is for idempotence and agreement with PR #44's word-for-word re-ask; the reasoning is under AUD-18 above.
2. **Score lines end in a markdown hard break (`"  \n"`).** This isn't in the brief. Without it, keeping the rubric whole would run its five lines into one paragraph on every shipped iOS build. It makes PR #43's soft-break follow-up unnecessary for the rubric. The follow-up would still help other single-newline prose.
3. **`[SOURCE]` has three forms by placement**, rather than always `Source: label (domain)`.
4. **iOS 2.0.0 (no capabilities) still sees raw `[SOURCE: …]` tags.** I gated the rewrite on blocks_v1 as briefed: capability-gated output is how the server changes what shipped clients see. To give 2.0.0 the plain text too, change `rewriteSources: wantsBlocks && !isWidget` to `!isWidget` in the two `server.js` call sites. Then update the "no capabilities" route test, and note that most eval-pacing scenarios send no capabilities.

## Open risks

- **Simulator.** I did not check the cards on a simulator: a reordered `[Q]`, a `Source:` line, the hard-broken rubric. The parse equivalence is tested, and the MarkdownUI hard-break behaviour was read from its source.
- **Visible streaming change.** A `[Q]` card now appears whole, about 1–2 s after its stem would have started streaming.
- **Text after `[/Q]` in the same reply.** If it refers to an option by letter ("hint: think about B"), it now points at the wrong option. The positional checks only see the block. I found none in the corpus, and the prompt puts the check last in the beat.
- **Rebase onto PR #44.** PR #44 edits `scripts/eval-pacing.mjs` heavily, and `lib/blockMarkup.js`'s appendix. My edits to both are small and in other lines: the header comment in `blockMarkup.js`, and the import, `stripMarkers`, `countLines`, `isTruncated` and `maxParagraphSentences` in eval-pacing.
- **Eval criteria to add (not done here).** An answer-position spread criterion and a "right answer isn't the longest" criterion for the blocks scenario. The audit suggests both. `scripts/quiz-order-stats.mjs` already computes them offline.
