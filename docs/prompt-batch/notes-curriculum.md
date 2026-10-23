# Curriculum prompt batch: notes (commits 4–5 of Batch 3, drafts, not committed)

> **Integrated 2026-10-18.** The batch is now seven local commits on
> `fix/prompts-lessons-2026-10` (not pushed): (1) safety core, (2) app facts +
> wiring, (3) free chat, (4) curriculum guide, (5) source library, (6) eval
> scenarios, (7) AUD-26 alone, so `git revert` of the last commit drops the
> rule-1 news line, its `safetyCore` test block and the
> `safety-lesson-chatbot-news` eval scenario together.
> The full merge gate (`eval-pacing --runs 3`, both flag states) has NOT been
> run on the integrated batch yet.
>
> `lib/appFacts.js` is wired into both curriculum prefixes (commit 2), so the
> U7L4 "answer only from the APP FACTS section" line has the facts to point
> at. The two `[LESSON_COMPLETE] within 10` gate rows (risk 1) are unchanged
> by the integration.

These are the October 2026 audit's Batch 3 commit 4 (curriculum guide) and commit 5 (source library).
- Branch: `fix/prompts-lessons-2026-10`, based on main `720dbac`.
- All edits are uncommitted working-tree changes; nothing was pushed.
- The fact table for human review is in `curriculum-factcheck.md`.
- Evidence is in `curriculum-evidence/` and in `docs/evals/pacing-curriculum-*.json`.

## What changed

### `server.js`: `CURRICULUM_PROMPT` (commit 4)

- **AUD-07: proficiency and pending checks.**
  - **PROFICIENCY SIGNAL rewritten.**
    - Before emitting, the tutor checks every part of the exercise.
    - Regular lessons need every part right.
    - Review lessons need every numbered part answered in the student's own words, plus a grade of A or B.
    - A **second-redirect rule** keeps the old "don't re-demand forever" behaviour, but now only for *format*. After one redirect, if every part is correct but the answers point to the right blank or item instead of quoting it, the tutor shows the expected shape and emits.
    - **HARD STOPS** come last and override everything, including the second-redirect rule. The tutor never emits when:
      - the student's latest message says "idk", "not sure", "I didn't…" or "don't know how" about any part;
      - any part is wrong;
      - or the reply would have to supply a skipped or "idk" part.
    - Instead it hands that one part back, and never credits the student with something its own reply supplied.
  - **PENDING CHECKS (new).** A check stays open until a student message actually answers it.
    - After an off-topic, joke, jailbreak, role-play, declined, "idk" or own-question turn, the tutor never says "you picked / you got it / exactly right / correct" and never praises an answer or insight the student didn't give.
    - It never infers the pick from the answer key. It replies briefly, then re-asks.
    - After a crisis hand-off it doesn't resume the lesson in that reply.
- **AUD-04: facts.**
  - **New FACT RULES block** heads the unit guides:
    - use only the guide's statistics, studies and years;
    - never call a real journal, person, study or case fabricated;
    - when an exercise needs false claims, use invented names;
    - for newer news, point the student to where to check;
    - each real case has one home lesson.
  - **Known errors fixed:** Waluigi, the Epic "52%", and pulse-oximeter "AI triage".
  - **Vetted facts added.** Every lesson where the model used to improvise numbers now has one or two vetted facts. The hook must be a true fact from the lesson entry, or a demonstration that needs no statistic.
  - All 62 claims and the source library are listed in `curriculum-factcheck.md`.
- **AUD-15: "As of 2026" notes.**
  - Chatbots search, remember and run code, and can be steered by hidden text (U1L2, U7L2, U7L4, U8L1).
  - Readable text and normal hands are no longer reliable tells (U6L1).
  - Missing Content Credentials prove nothing (U6L2 and the U6L5 rubric).
  - Reasoning models and chain-of-thought (U4L2).
  - The "strawberry" failure is mostly patched (U8L3).
  - There is no autonomous-weapons treaty (U5L2).
- **AUD-39: exercise rules.**
  - A reteach uses a different example from the exercise and never answers it.
  - Everything to be graded must be in the task, and multi-part exercises are numbered.
  - Grading is part by part, and contradictions get flagged, not credited.
  - Review grades rest only on what the student wrote.
  - U1L1 has a grading note: "many words fit" means LOW confidence, and the tutor never reinterprets the student's reasoning into the right one.
  - The U8L1 exercise must contain an irreversible action.
- **AUD-45: duplicates removed.**
  - **Amazon** stays in U3L1 only. It was dropped from U5L1, where it was also miscategorized as specification gaming.
  - **U2L1's exercise** is no longer a hiring tool.
  - **U5L1** gets the robot-arm and 2025 reward-hacking examples instead.
  - **The Hong Kong deepfake** stays in U6L3 only, and U8L1 is told not to use it.
  - **U3L3's exercise** moves from policy-writing (which overlapped U7) to a false-positive detector case.
- **AUD-43.** "beat", "micro-concept", "check question", "Step N" and "teach phase" are private planning words. So is any mention of "the guide" or the tutor's instructions. The tutor never announces how many ideas are left and never quizzes on an untaught idea. "load-bearing term" became "key term".
- **AUD-40.** This wasn't on my list, but the eval commit's new beat-1 row depends on it. Each teach reply now has a budget: "at most 6 paragraphs in total (each [KEY] or [EX] block counts as one) and about 120 words before the check — one hook fact".

### `lib/blockMarkup.js`: `CURRICULUM_BLOCKS_APPENDIX` (commit 4, the template string only)

- **AUD-18.**
  - Exactly one option is defensibly correct, and every distractor is a real, tempting misconception. There are no joke options.
  - The options must look alike, and the correct one must not be the longest or the most qualified. "Length check before you send: at least one wrong option must be longer than the correct one."
  - There is no position rule here: shuffling belongs to the Batch 1 server transform.
- **AUD-07.**
  - A `[Q]` counts as answered only by "I picked X) …" or by a message that clearly chooses or explains.
  - `ANS:` is the tutor's private key.
  - Anything else gets a reply, then the same or a fresh `[Q]`.
- **`[EX]`** now asks for "a real case from this lesson's guide entry, or a scenario you plainly present as made up".

### `server.js`: `SOURCE_LIBRARY` (commit 5), plus one sentence in the legacy `SOCRATIC_PROMPT`

- **AUD-16.**
  - **EO 14110** is now labeled REVOKED (2025-01-20), "NOT current US policy", and points to federalregister.gov; the whitehouse.gov link was a 404.
  - **Policy entries are dated.**
  - **New rule:** cite a source only when it directly supports the specific claim just made.
  - **Dead or moved links fixed:**
    - gendershades.org fails TLS → media.mit.edu;
    - the HAI ai-education page was a soft 404 → removed;
    - the NAM path was a 404 → the publication title on nam.edu;
    - FDA and the Anthropic docs moved → domain only.
  - **New entries** back each fact the guide now teaches.
- **AUD-38.** The format is `[SOURCE: Title — domain.com]`, domain only, with no paths, DOIs or docket numbers. Batch 1's rewrite transform still works on it, and the widget (`public/widget.js:442`) renders it as plain text.
- **Legacy `SOCRATIC_PROMPT` → SOURCE CITATIONS.** It used to say "tag every verifiable fact with `[SOURCE: brief label]`". It now says to tag only a fact that a library entry directly supports, using that entry's title and domain, and otherwise add no tag. This is AUD-16's "only attach a source that supports the claim" on the flag-off path. No other legacy prompt was touched.

### Not touched

- The prompt-assembly code (`curriculumStatic`, `legacyStatic`, `V2_STATIC_*`).
- `lib/systemBlocks.js`, `lib/safetyCore.js`, `lib/appFacts.js`, `prompts/mercurius-v2.md`, `lib/unifiedPrompt.js`, `lib/responseQuality.js`.
- `scripts/eval-pacing.mjs` and the iOS data.

`SAFETY_CORE` is still last. The static blocks are compile-time constants with no dates or env, so each prefix stays byte-stable. Deploying them causes one cache miss.

## For the integrator

- **APP_FACTS.** U7L4 ends with "About Mercurius itself: answer only from the APP FACTS section of this prompt; never guess." That relies on `systemBlocks.withAppFacts` putting `lib/appFacts.js` into the curriculum prefixes. If it doesn't, change that line.
- **Size.**
  - `CURRICULUM_PROMPT` grew from 25.8k to 42.7k characters, about +4k tokens per lesson call. It is cached: eval turn 2+ reads about 12.4k cached tokens, and uncached input stays at most 97 tokens a turn.
  - The cost is about +$0.001 a turn, plus about $0.015 per cache write.
  - `SOURCE_LIBRARY` grew from 2.6k to 3.9k characters, about +300 tokens on every chat prefix.
- **Conflicts.** Batch 1 also edits `lib/blockMarkup.js` (the `[Q]` shuffle and the `[SOURCE]` rewrite); my change there is the appendix string only. PR #39 edits `server.js` near the club block, not these constants.
- **Reproducing the evidence.** `curriculum-evidence/scripts/replay.mjs` replays the audit's recorded lesson turns: `BASE=… node replay.mjs <label> u7_l1:4:4 …`. It reads the transcripts from the `audit-2026-10` worktree path. `lessons.mjs` runs the pending-check and fact probes: `BASE=… node lessons.mjs <label> pending|facts <runs>`.

## Tests run

All of these ran on isolated copies of main `720dbac` plus only my two files, so the other agents' in-progress work was excluded. Servers used the required env and fresh SQLite files, and every port was confirmed free before and after. About $12 of API spend in total.

1. **Unit tests.** `node --test tests/*.test.js` passes 959/959, re-run after every draft. The prompt-related subset (blockMarkup, promptSafetyCache, systemBlocks, curriculumTag, unifiedPromptGate, evalPacing, lessonOutcome) passes 164/164.
2. **AUD-07 replays.** These are the audit's recorded "gap" turns, where the student skipped a part, said "idk", or got one wrong. Each was replayed 4 times. A "control" turn is one where the student had answered every part.

   | | main | final draft |
   |---|---|---|
   | gap turns that completed (should not) | **28/32** | **4/32** (u1_l3 3/4, u1_l1 1/4; 0/4 on u7_l1, u5_l1-r2, u3_l1-r2, u1_l1-r2, u6_l5-r2, u2_l1) |
   | control turns that completed (should) | 16/16 | 16/16 |

   - Intermediate drafts swung between 2/32 and 8/32. A looser bounded-strictness wording sent u1_l3 back to 4/4, so I reverted it. Every run is in `curriculum-evidence/replays-all-versions.txt`.
3. **Pending check after an off-topic turn** (the u1_l1 opener's `[Q]`, then DAN, a roast, "favorite movie", or "help with spanish hw", ×3):
   - main credited a pick in 3/12 ("you picked B, which is exactly right") and re-asked in 5/12;
   - the final draft credited 0/12 and re-asked 9/12. The roast refusals didn't re-ask, but they didn't credit anything either.
4. **Full simulated lessons.** I used the audit's own driver with a claude-haiku-4-5 student and the same behaviour schedules: 10 first lessons ×2, plus the u1_l4 and u6_l5 Reviews.

   | | main (audit run) | final draft |
   |---|---|---|
   | lessons completed | 20/20 | 22/22 |
   | latest completion | — | turn 7 |
   | completed right after the deliberately flawed "attempt" turn | 6/20 | 1/22 (u1_l3: three weak-but-present parts) |
   | "micro-concept" or "this beat" | in 7 lessons | 0 |
   | Waluigi, 52%, oximeter-triage, "2023 MIT", "chatbots can't search/remember", "classic tell", "metadata is a flag" | present | 0 |
   | Amazon outside U3L1, or Hong Kong outside U6L3 | present | 0 |
   | `[SOURCE]` tags with URL paths | present | 0 (one tag, domain-only and correct) |
   | "the guide" leaks | — | 1 |

   Transcripts are in `curriculum-evidence/lessons-v7/`.
5. **Fact and opener probe** (opener plus two correct taps, 9 lessons ×2, after the v8 tweaks):
   - the only flags were "micro-concept" in one u3_l2 run and one correct Kestin title in a `[SOURCE]` tag;
   - openers: 5/18 met ≤ 6 paragraphs and ≤ 165 words. main's audit openers met 0/18. Median 158 words (main 202) and 7 paragraphs (main 8).
6. **`scripts/eval-pacing.mjs` (main's version)**:
   - **Full gate `--runs 3`, both flag states**, on the v7 draft: everything except the last two v8 wording tweaks (the beat budget now counts blocks, and the distractor length check). **30/32 criteria pass in both states.** That covers every safety, helper, cache, chat-pacing, debate, discussion, deep, airy, blocks-format and beat-1 row. **The 2 failures, in both states:** "[LESSON_COMPLETE] within 10 assistant turns" and "blocks: [LESSON_COMPLETE] within 10 assistant turns". See risk 1.
   - **`--only curriculum --runs 3`, both flag states, on the final draft:** every curriculum row passes except the same two completion rows (flag on: 1/3 and 0/3; off: 0/3 and 0/3).
   - The results are in `docs/evals/pacing-curriculum-v7-full-flag-{on,off}.json` and `pacing-curriculum-v8-final-flag-{on,off}.json`.

## Open risks

1. **The eval gate's two lesson-completion rows fail. This blocks the merge gate, and I think the eval should change, not the prompt.**
   - **What happens.** `curriculum-1` and `curriculum-blocks-1` script the student's exercise answers in advance ("the slot right after the last two words…"). The tutor writes a new exercise sentence every run, so those answers never name the actual blanks and are sometimes wrong for that sentence.
   - **Why main passed.** main's "model it yourself and emit" rule completed anyway. That is the same unearned credit AUD-07 is about.
   - **I tried loosening it.** One draft (v6) widened the second-redirect rule. It made the scripted lesson complete about half the time, but one of those completions said "you had the two slots flipped" and still emitted, and u1_l3 went back to 4/4.
   - **Real students are fine.** With students who actually do the exercise, the final draft completes 22/22 lessons by turn 7.
   - **Options:**
     - (a) make the exercise turns in those two scenarios dynamic: role-play a competent student with claude-haiku-4-5, as the audit driver does;
     - (b) make the two rows report-only until (a) lands;
     - (c) accept a looser rule, at the cost of re-opening AUD-07.

     I recommend (a). The eval agent owns `scripts/eval-pacing.mjs`, so I didn't touch it.
2. **AUD-07 is greatly reduced, not eliminated.**
   - **Where it remains.** 4/32 gap replays still complete. Both are on threads whose history came from main's old prompt: u1_l3's exercise names a real journal, and the student's "google it" answer is partly right.
   - **Follow-up.** Prompt compliance plateaus, so add a deterministic server guard in Batch 1 style. In lesson mode, if the latest user turn matches an explicit self-reported gap (`idk`, `i don't know how`, `i didn't (answer|do)`, `not sure`), strip `[LESSON_COMPLETE]` and don't record completion. The guard is cheap, but it needs care: "idk" can appear in an otherwise complete answer.
3. **AUD-18 is not fixed by the prompt.** The correct `[Q]` option is still the longest 84–90% of the time: 32/38 on the final draft, 62/69 in the simulated lessons. main was 53/53 (100%) in the audit and 16/18 (89%) in my baseline probe. The letter is B about 76% of the time; the Batch 1 shuffle fixes position. Length needs either an eval criterion with a server-side check or acceptance. Prompting has plateaued.
4. **AUD-40 (beat-1 length) is improved, not fixed.** Openers dropped from a median of 202 to 158 words and from 8 to 7 paragraphs, but only about 28% meet the eval agent's new ≤ 6 paragraphs / ≤ 165 words row. Expect that row to fail until the founder decides between report-only and a stricter budget. A server transform can't merge paragraphs without fighting `airyReflow`.
5. **A person must still fact-check.** See the **Check** rows in `curriculum-factcheck.md`, especially:
   - the Epic "18% of hospitalized patients" figure;
   - the dates of the three labs' safety frameworks;
   - "most shared images carry no Content Credentials";
   - the treaty status after the November 2026 CCW Review Conference.
6. **Lessons are slightly longer for students who leave gaps.** A gap now costs one more round trip. That's by design, and the simulated runs show completion at turns 5–7.
7. **Small leaks remain.** I saw "micro-concept" once in 18 probe lessons, "the guide" once in 22 simulated lessons, and one off-topic roast reply that didn't re-ask the check. All three are rare and none is harmful.
8. **Unverified on device.** The `[SOURCE: Title — domain]` tag still shows as raw text on iOS until the Batch 1 transform (AUD-38) ships. The domain-only format at least removes the invented paths.

## Link check, to re-run each term (AUD-16)

```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36"
for u in https://www.propublica.org/article/machine-bias-risk-assessments-in-criminal-sentencing \
  https://www.media.mit.edu/projects/gender-shades/overview/ https://www.ajl.org https://doi.org/10.6028/NIST.IR.8280 \
  https://arxiv.org/abs/1803.09010 https://arxiv.org/abs/1706.03762 https://arxiv.org/abs/2303.08774 \
  https://www.3blue1brown.com https://www.anthropic.com/research https://hai.stanford.edu/ai-index \
  https://ainowinstitute.org https://www.unesco.org/en/artificial-intelligence/recommendation-ethics \
  https://eur-lex.europa.eu/eli/reg/2024/1689/oj https://www.nist.gov/itl/ai-risk-management-framework \
  https://www.federalregister.gov/d/2023-24283 https://incidentdatabase.ai \
  https://www.fda.gov/medical-devices/software-medical-device-samd/artificial-intelligence-enabled-medical-devices \
  https://nam.edu/publications/artificial-intelligence-in-health-care-the-hope-the-hype-the-promise-the-peril/ \
  https://www.unesco.org/en/digital-education/artificial-intelligence https://learnprompting.org https://docs.claude.com \
  https://www.anthropic.com/news/core-views-on-ai-safety https://arxiv.org/abs/1606.06565 \
  https://deepmind.google/discover/blog/specification-gaming-the-flip-side-of-ai-ingenuity/ https://safe.ai \
  https://contentcredentials.org https://www.elementsofai.com https://www.technologyreview.com/topic/artificial-intelligence/ \
  https://ourworldindata.org/artificial-intelligence https://arxiv.org/abs/2304.02819; do
  echo "$(curl -s -o /dev/null -L -A "$UA" --max-time 20 -w '%{http_code}' "$u")  $u"; done
# A 403 from jamanetwork / nejm / science.org / pnas.org / dl.acm.org is bot-blocking, not a dead link.
# A 200 can still be a soft 404 (the HAI ai-education page was one): spot-check <title>.
```
