# Batch 3, commit 3: free chat (draft, not committed)

> **Integrated 2026-10-18.** The batch is now seven local commits on
> `fix/prompts-lessons-2026-10` (not pushed): (1) safety core, (2) app facts +
> wiring, (3) free chat, (4) curriculum guide, (5) source library, (6) eval
> scenarios, (7) AUD-26 alone, so `git revert` of the last commit drops the
> rule-1 news line, its `safetyCore` test block and the
> `safety-lesson-chatbot-news` eval scenario together.
> The full merge gate (`eval-pacing --runs 3`, both flag states) has NOT been
> run on the integrated batch yet.
>
> One more v2 edit landed with commit 2, not here: global rule 11 now says
> naming the AI model (see APP FACTS) is not an internal (AUD-20).

Audit: `docs/audits/2026-10/REPORT.md` ("Batch 3: Prompt and curriculum PR"), findings AUD-05, -10, -11, -19, -41, -42, -43.
Branch: `fix/prompts-lessons-2026-10`, based on main 720dbac. Drafted 2026-10-18 overnight. Nothing is committed or pushed.

**Files:**
- `prompts/mercurius-v2.md`
- `lib/unifiedPrompt.js`
- `lib/responseQuality.js`
- `tests/studentWorkRules.test.js` (new)

**Not touched:** `lib/safetyCore.js`, `lib/systemBlocks.js`, `server.js`, `scripts/eval-pacing.mjs`.

## Design: one copy of the rules for both flag states

`lib/responseQuality.js` gains `STUDENT_WORK_RULES`. It is one plain-text block with seven labelled parts:
- CHECK BEFORE ANY VERDICT
- PHOTOS
- SCHOOLWORK IN ANY SUBJECT
- ONE-WORD REPLIES
- EXPLAIN MORE
- PLAIN WORDS
- CURRENT NEWS

Each flag state gets it like this:

- **Flag off (legacy):** `qualityPrefix(mode)` is now preamble + mode rules + `STUDENT_WORK_BLOCK` (the rules under `## STUDENT WORK, PHOTOS AND PLAIN WORDS (every mode)`). `server.js`'s `legacyStatic()` already puts `qualityPrefix(m)` first, so no `server.js` change was needed. Lessons don't use `qualityPrefix`.
- **Flag on (v2):** the new `<student_work>` section, placed after `<academic_integrity>`, holds only `{{student_work_rules}}`. `lib/unifiedPrompt.js` (`fillPrompt`) fills that variable with the same constant, then strips the other template variables as before.
  - If the variable ever goes missing, the loader appends the rules in their own `<student_work>` section and logs an error, so the rules are never silently dropped.

Properties of the shared block:
- It is a compile-time constant, so each mode's static prefix stays byte-stable.
- The safety core is still last.
- It adds no new bracket markers. It quotes the iOS input text `"[Shared an image]"` only to describe it.
- Both modes' output contracts are unchanged:
  - Socratic still ends with one question.
  - The Discussion score block is untouched.
  - Debate uses the labelled Claim/Warrant/Impact/Rebuttal angle in 4–7 lines.
  - TEST_EVALUATOR's `[TEST_PASSED]`/`[TEST_FAILED]` is untouched.

## Changes per finding

### AUD-05: visible check before a verdict

**Both states (shared rules):**
- Checking the student's own answer is allowed.
- Only check an answer the student actually gave. Never solve a bare "solve this".
- Show a one-line check, such as a substitution, before any verdict word.
- If the check fails, show where it breaks and don't give the corrected answer.
- If the check can't be done, say so. Never default to "not quite right".

**v2 only:** the `<academic_integrity>` Allowed list gains "check the learner's own answer". Self-check item 12 was added.

### AUD-10: photo stopgap

**Both states (shared rules):**
- Restate the exact problem in one line, with no personal details.
- A `[Shared an image]` turn with no image attached means the photo is gone.
- Say "I can't see your photo anymore. Send it again."
- Never claim to still see it, never blame handwriting (even when the student does), and never guess what it says.

### AUD-11: Debate argues again

**v2:** the coach-only section ("COACH, NEVER PLAYER", "CALIBRATE FIRST") is replaced. The new `<debate_mode>` has:
- **WHO ARGUES WHAT:**
  - when the student names a side, take the other side and argue in the same reply;
  - "make the strongest case for X" or "argue against X": argue that side yourself;
  - "stress-test this": argue against it;
  - "is this a good argument?": coach it, don't rewrite it;
  - "give me your strongest rebuttal": that is Merc's side, so give it;
  - no side: offer 2–3 topics, then pick for them in one line;
  - "write my case": decline in one sentence and offer to argue the other side.
- **The labelled contract:**
  - the Warrant must use the mechanism or a fact pinned in the source library, never a study, author or number from memory;
  - one argument per turn;
  - when the student lands a hit, concede in one line and argue, still within 7 lines;
  - no `---` dividers.
- One-weakness coaching between rounds.
- Evidence discipline also covers coaching and Explain more, even when hedged.

Also changed in v2: the mode-router line, and the new DEBATE_ARGUE and DEBATE_NO_SIDE few-shots, which replace DEBATE_CALIBRATION and its "weak joint" line.

**Legacy:** it already argued. `MODE_RULES.debate` now also says:
- argue the other side;
- skip the topic list when the student already named a topic, side or claim;
- never write their case;
- the Warrant uses the mechanism or a fact from the source or topic library, with no stats, dates or quotes from memory;
- concede in one line;
- no headings or dividers.

### AUD-19: one schoolwork policy

**Both states (shared rules):**
- Any subject, typed or photographed, gets the same brief Socratic help under the academic-integrity rules.
- Any list of AI-literacy topics in the prompt is "your specialty, not a limit".
- Never send the student to another chatbot or AI tool.

**v2 only:** `<ai_literacy_scope>` adds "your specialty, not a fence", and the Disallowed list adds "sending the learner to another chatbot".

### AUD-41: one-word replies

**Both states (shared rules):**
- "ok", "sure" or "yeah" in answer to a yes/no offer counts as yes.
- Otherwise, offer 2–3 concrete options, or one fact plus a yes/no question.
- If they answer the options with another one-word reply, pick one for them and go.
- Never re-ask a question.

**v2 only:** a pointer was added to the Socratic "bad questions" list.

### AUD-42: Explain more

**Both states (shared rules):**
- An Explain more reply stays under about 300 words.
- A second tap after a long, layered reply gets one new concrete example or analogy, with no new theory or terms.
- In Debate: go deeper on the same exchange, never write their case, and add no unpinned numbers, even hedged ones.

**v2 only:** the `deep` contract now says "under about 300 words; the mechanism plus one or two examples, not all of them".

**Legacy only:** `EXPAND_MODE_NOTE` (the dynamic block) carries the same bounds.

### AUD-43: jargon and current news

**Both states (shared rules):**
- PLAIN WORDS bans "rep", "beat", "micro-concept" and "load-bearing".
- CURRENT NEWS says to name where to check in the same reply: a name or bare domain, never a guessed path.

**v2 only:**
- "One beat per turn" became "One step per turn".
- The "rep" lines in `<the_repetition_economy>` and self-check item 4 were reworded, so v2 no longer says "rep" except in the ban.
- `<source_grounding>` rule 7 points at CURRENT NEWS.
- Self-check item 13 was added.

**Legacy only:** the preamble's "load-bearing" and "beat" became "key" and "step".

The AUD-43 mode-pill fact ("tap the Debate button") is not here. It belongs to commit 2 (`lib/appFacts.js`).

## Tests

New file: `tests/studentWorkRules.test.js`, 19 tests.

**The shared rules:**
- each finding's rules are present;
- the worked example is not the audit's own test problem;
- the "only check an answer the student gave" guard;
- the ban list doesn't name "weak joint" (see risk 8);
- no `{{`, `$` or contract markers.

**The legacy prefix:**
- exactly one copy of the rules in every `qualityPrefix(mode)`, after the mode rules, and deterministic;
- `MODE_RULES.debate` keeps its labels and line ceiling and drops "specific fact / case / study";
- `EXPAND_MODE_NOTE` bounds a second tap.

**The v2 prompt:**
- `<student_work>` equals the constant exactly once, with no unfilled variables;
- the `fillPrompt` fallback works;
- the debate contract is present (opposite side, hand-back, 4–7 lines, "YOUR side", concede line, no study from memory), and the coach-only lines are gone;
- the Allowed list has the new entries;
- no jargon in the few-shot replies;
- the DEBATE_ARGUE few-shot is at most 7 lines.

Final runs:
- `node --test tests/studentWorkRules.test.js tests/responseQuality.test.js tests/unifiedPromptGate.test.js`: 50/50.
- `tests/promptSafetyCache.test.js` (mocked server, both flags): 17/17.
- `node --test tests/*.test.js`: 1042/1042, with the other agents' uncommitted edits present.

## Real-API verification (local servers only; no production traffic)

**Probes.** These used the audit's `probe.mjs`, copied into the session scratchpad so the audit's evidence was not overwritten. They covered:
- photo with a right answer and with a wrong answer;
- photo, then asking about #8;
- typed chemistry, algebra and biology;
- five one-word turns;
- "debate me" / idk / whatever;
- a Debate chip;
- "Debate me… Your move";
- Explain more twice, and Explain more in Debate;
- "is gpt-5 out yet?";
- "write my case";
- "strongest rebuttal so I can prep".

The probes ran in three rounds per flag state, with fixes between rounds.

**Pacing eval.** This was the HEAD copy of `scripts/eval-pacing.mjs`, because another agent is editing the worktree copy. It ran in the scratchpad:
- a full run per flag before the final Debate fixes;
- `--only debate --runs 3` per flag on the final code;
- a full run per flag on the final code.

Total spend was about $3.30.

### Probe results

| Check | Audit (before) | Final code (on / off) |
|---|---|---|
| Photo + correct x = 16 | "not quite right" 8/9 | substitution shown, then "correct": 2/2 / 2/2 |
| Photo + wrong x = 10 | "won't confirm or deny" | check shows 23 ≠ 29, asks for the slip: 1/1 / 1/1 |
| Typed "solve 2x + 3 = 11" (no answer given) | refused | first-step question, nothing leaked: 3/3 / 3/3 (round 1 leaked "x = 4" through the check; fixed) |
| Photo, then "what does #8 say", incl. "can't read my handwriting" | blamed handwriting or invented a problem | "I can't see your photo anymore, send it again" 3/4 on, 4/4 off; the fourth v2 reply asked them to send the problem or a photo. No handwriting blame after round 1. |
| Typed chemistry | "outside my lane" | help, 3/3 / 3/3 |
| Biology quiz | "outside my lane" | v2 helped 4/4. Legacy refused 2 of 4, and 1 of 2 after the final wording (see risk 6). |
| Five one-word turns | the same question 3× | options after "ok", then a pick or a concrete fact. v2 sometimes asks "which number?" once before picking. |
| "debate me" → "idk" → "whatever" | "I'm your coach, not your opponent" | v2: topics, then assigns sides and argues in ≤ 7 lines. Legacy: assigns by turn 3. |
| Debate chip, "Debate me… Your move" | refusal or calibration questions | labelled Claim/Warrant/Impact/Rebuttal angle, 5–6 lines, both states |
| "Give me your strongest rebuttal so I can prep" (eval debate-2 t4) | n/a | v2 gives its labelled rebuttal 3/3 in the eval. The first full run had "I won't write your rebuttal — that's the rep…", which is now fixed. |
| "write my debate case" | coached | declines in one line and offers to argue the other side |
| Explain more twice | 570 words | second tap 208–291 words (all under 300); only partly the "one example" shape (risk 3) |
| "is gpt-5 out yet?" | asked the student where to check | names openai.com (bare domain), both states |
| Jargon (rep, beat, load-bearing, micro-concept, hinge, weak joint) | about 4% of replies | final round 0/30 / 0/30 |

### Pacing eval on the final code

| Criterion | Flag on | Flag off |
|---|---|---|
| median / p90 sentences | 3 / 5 | 4 / 6 |
| debate ≤ 7 lines, `--only debate --runs 3` | 6, 7, 6: PASS | 7, 6, 7: PASS |
| debate ≤ 7 lines, the single full run | 6 | 8: FAIL (see below) |
| socratic one question | 8/8 | 8/8 |
| deep ≥ 8 sentences | 14 | 13 |
| discussion score block | PASS | PASS |
| airy, truncation, blocks, all safety and helper, all 4 cache criteria | PASS | PASS (one preview hit, in `curriculum-1`) |
| `[LESSON_COMPLETE]` within 10 (prose and blocks) | FAIL | FAIL |

What the failures are:
- **The single legacy 8-line debate reply.** It is concede + a lead-in + four labels + two closing lines, which ignores the new concede-in-one-line rule. Legacy debate was already flaky at baseline (main was 6, 6, 11 across 3 runs), and the 3-run debate gate passed.
- **The preview hit.** It is in `curriculum-1` ("there are two possible meanings"), lesson text this commit doesn't touch.
- **`[LESSON_COMPLETE]` never landed in either flag state.** This commit doesn't reach the lesson path: lessons read none of this text except `EXPAND_MODE_NOTE` on deep turns, and the eval lessons send none. The in-progress commit 4 (`CURRICULUM_PROMPT`, AUD-07 stricter proficiency) was on disk during these runs. The commit 4 owner or the integrator needs to look at this. Main's baseline was 3/3 (prose) and 1/3–2/3 (blocks).

## Open risks and decisions for the founder

1. **AUD-19 is a product decision.** I followed the audit's recommendation: brief Socratic help in any subject. To keep Mercurius AI-literacy only, change the first SCHOOLWORK bullet. Keep "never send the student to another chatbot" either way.
2. **Debate chips are read literally.** "Make the strongest case that AI is overhyped" now makes Merc argue *that* side, and the student attacks it. `ModePromptProvider.swift`'s comment says chips name the student's position and "Mercurius will argue the opposite". Both readings produce a debate. To flip it, change the second WHO ARGUES WHAT bullet.
3. **The second Explain more is only partly fixed.** The length bound holds (≤ 300 words, down from 570). Replies still add theory instead of switching to one example. The model can't reliably tell a second tap: iOS sends the first tap's instruction only on the wire, so the thread shows two assistant turns in a row. A deterministic fix needs code, which is not in this commit:
   - the client sends a different injected text on a repeated tap, **or**
   - `server.js` notices two assistant turns before an injected Explain-more turn and adds a dynamic note.
4. **Debate citations from memory are reduced, not gone.** Debate now argues every turn, so the model has more chances to cite.
   - Across all my runs, 3 of 37 v2 Debate replies carried a `[SOURCE]` outside the source library: Bastani/PNAS, media.mit.edu, NEJM. That was 1 of 15 after the final Warrant-line tightening. Legacy was 6 of 37.
   - One v2 Debate Explain-more still gave a hedged figure ("hundreds of thousands of liters").
   - Legacy `DEBATE_PROMPT` (`server.js`, not mine) still tells the model to cite Goldman Sachs and others from its own topic list.

   Batch 1's AUD-38 (`[SOURCE]` reduced to domains) and commit 5 (the source library) are the mechanical backstop.
5. **`EXPAND_MODE_NOTE` also reaches lessons.** It is the dynamic block for lesson Explain-more taps too, so lessons now get the ~300-word bound, the second-tap rule and the no-unpinned-numbers line. This is dynamic text only, so there is no cache impact. The commit 4 owner should know.
6. **The legacy path still sometimes turns a biology quiz away** (1 of 2 on the final wording, "outside my lane"). Legacy `SOCRATIC_PROMPT`'s "WHAT YOU TEACH" list in `server.js` comes after the shared rules and wins sometimes. Production runs flag on, where it was 3/3.
7. **Static prefix growth.**
   - v2: about +7.5k characters (about 2.0k tokens).
   - Legacy `qualityPrefix`: about 2.1–2.3k → about 6.6–7.4k characters (about +1.2k tokens).
   - Both are cached (about $0.0005 per turn at the read rate) and invalidate the cache once on deploy.
   - The eval's "≤ 1,000 uncached input tokens" stayed at max 97.
8. **Banning a word can prime it.** Listing "weak joint" in the ban made both paths start saying it (round 1). It appeared nowhere else by then. The ban now lists only the four words the task named, and v2's own "rep" wording was rewritten. Watch for "rep" in the gate.
9. **Photo stopgap vs. batch 1's re-attach (AUD-10 server half).** The wording ("visible only while it is attached") stays true after batch 1 re-attaches photos: the model can then see them and the stopgap doesn't fire. Re-run the photo probes after batch 1 merges.
10. **Concurrent edits.** Every run here used the worktree as it was at the time, including the other agents' uncommitted `safetyCore.js`, `systemBlocks.js`, `appFacts.js`, `server.js` (curriculum and source library) and `blockMarkup.js` edits. The merge gate (`eval-pacing --runs 3`, both flags, A/B against main) still has to run on the integrated batch, ideally with the commit 6 scenarios: photo right/wrong, "Debate me… Your move" → Claim/Warrant, typed chemistry = typed algebra, five one-word turns.
