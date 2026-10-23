# Socratic homework coaching: build notes (2026-10-21)

Merc now coaches homework instead of refusing it. Asked "what is 3x+5 = 20", it opens with "What's your first move to get the 3x by itself?". Main sends algebra to Wolfram Alpha as "not AI literacy", and #44's head before this step opened with "You haven't given me your answer yet — so I won't solve it for you".

Branch `fix/prompts-lessons-2026-10` (draft PR #44). Local commits only, nothing pushed:

| Commit | What |
|---|---|
| `3843ff5` | **Rules.** `STUDENT_WORK_RULES` (`lib/responseQuality.js`), the Socratic mode line, and `prompts/mercurius-v2.md`, with `tests/studentWorkRules.test.js` |
| `8a1bcec` | **Eval.** The eight `hw-*` scenarios and their criteria in `scripts/eval-pacing.mjs`, with fixtures in `tests/evalPacing.test.js` |
| (docs commit) | This file, the tuning eval JSONs and the off-eval probe |

The earlier attempt at this step committed rules and eval together as `ad5f2cb`; that commit was split into the two above. The tree is `ad5f2cb` plus this session's rung-2/rung-3 rewrite and one metric fix. `npm test`: 1090/1090 at `8a1bcec`, and 1081/1081 with the rules commit alone.

## Outcome

- **The eval passes at the committed text in both flag states on every `hw-*` row but one,** with one caveat: the final `--runs 2` confirmation was cut off by the API account running out of credit (below). The ladder row, the one that failed most, passed 5/5 in each flag state on the committed text. Run 1 of the final confirmation passed every hw row in both states except `hw-chem` with the flag on (an extra question in the second reply).
- **The answer no longer leaks through the worked example.** Until this session, the third rung's "parallel problem" was free-form. The model kept picking stock equations whose answer was the student's own: 2x + 3 = 13 for 3x + 5 = 20 (both x = 5). That happened in 2 of 20 eval ladder threads on `ad5f2cb`'s text. Interim wordings this session still let the model fall back to a free example. On other equations (the probe below) they leaked in 6 of 24 threads. The example is now built mechanically from the student's own equation, so its answer is always theirs + 3. On the committed text the probe found 0 leaks in 18 threads.
- **Not done: a second full run at the committed text.** The account returned `400 "Your credit balance is too low to access the Anthropic API"` at 19:06 UTC, partway through run 2. Run 1 was rebuilt from the eval servers' own SQLite (see "Results"). Re-run `--only socratic,chat-,hw --runs 2` in both flag states once credit is back.
- **Check production now.** If Railway uses the same Anthropic account as the local `.env`, production chat is failing with "Mercurius hit a snag" until credit is added. This was not checked, because test traffic never goes to production.

## Behaviour → rule

| # | Target | Where it lives |
|---|---|---|
| 1 | Lead with a concrete question, no refusal or preamble | HOMEWORK COACHING "Lead with the question" (banned phrases quoted); the v2 integrity redirect and its few-shot no longer model a refusal |
| 2 | Hint ladder, never the final answer, never a stall | "Hint ladder" plus rungs 1–3 and the 4th-ask line; ONE-WORD REPLIES defers to it; the v2 "WHEN THE STUDENT IS STUCK" list points to it |
| 3 | Confirm and advance | "Confirm and advance" (write the line it gives, ask the NEXT step) |
| 4 | Catch errors | "Catch errors" (open with the check, never "close") + CHECK BEFORE ANY VERDICT for a right final answer |
| 5 | Essays coached, never written | "Essays and other writing" |
| 6 | AI tie-in at most once | "AI tie-in" |
| 7 | No other tool or site | SCHOOLWORK IN ANY SUBJECT ("…and don't name one"; no tool is named in the rules, since naming one primes it) |
| 8 | Plain facts answered directly | "A plain fact question…" |
| 9 | Safety unchanged | No safety file touched. `lib/safetyCore.js` stays the last static block (`git diff 3f46b2d -- lib/safetyCore.js lib/systemBlocks.js server.js` is empty) |

Both `USE_UNIFIED_PROMPT` states read the same constant. With the flag off, `qualityPrefix()` carries it after the mode rules. With the flag on, it fills `{{student_work_rules}}` in `<student_work>`. Every static block stays byte-stable per mode, and cached prefixes grow from 12,734 to 14,152 tokens (flag on) and from 6,812 to 8,149 (flag off).

## Rule text: before → after

### `STUDENT_WORK_RULES`

**Before (`3f46b2d`)**, the only homework text:

> CHECK BEFORE ANY VERDICT — "Only check an answer the STUDENT gave. If they haven't given one yet ("solve 2x + 5 = 13"), don't solve it, don't show a check and don't reveal the answer: help them take the first step."
>
> SCHOOLWORK IN ANY SUBJECT — "…gets the same brief Socratic help: one step at a time, the student does the work, and the academic-integrity rules apply. …" / "Tie it back to AI use only where it fits naturally, for example how to check an AI's answer to this kind of problem." / "Never send the student to another chatbot or AI tool (ChatGPT, Gemini or any other) to do, solve or check their work."

The flag-on "You haven't given me your answer yet — so I won't solve it for you" echoed that first bullet.

**After (`3843ff5`)**: a new first section, verbatim.

```
HOMEWORK COACHING
- This covers any problem the student is meant to solve or write themselves, in any subject and every mode, Direct included, typed or in a photo: an equation, a balancing or word problem, a worksheet question, an essay or a paragraph. Coach it one step at a time. Never give the final answer to THEIR problem, in any reply, however they ask. Work the whole problem out silently first, so every question and hint points at its real next move.
- Lead with the question. Your first reply starts coaching right away with one concrete move tied to their problem: name the term, number or step it's about. For "what is 4x − 3 = 25": "What happens if you get the 4x by itself first?" In balancing, ask about an element whose counts don't match yet: for CH₄ + O₂ → CO₂ + H₂O the C already matches, so "How many H atoms are on each side?" Not a general question about goals or what solving means, and only that one question. Nothing comes before it except, for a photo, the one-line restatement: no refusal and no preamble, never "I won't solve it", "I can't do your homework", "you haven't given me an answer yet" or "instead of giving you the answer".
- Hint ladder. When they're stuck or ask for the answer, never refuse, never stall and never ask the same thing again. Each "idk", "still don't get it", "just tell me" or "can u just do it" on the same problem is one ask. Count them silently in the thread (never tell the student which ask or step this is): the 1st ask gets rung 1, the 2nd rung 2, the 3rd rung 3, however small your earlier hints were.
  1. A nudge that points at exactly where the next move happens: the term to undo, or in balancing an element whose counts differ right now (never one that already matches): "Look at the − 3. What undoes subtracting 3?"
  2. A bigger hint that names the inverse operation and does it, starting from their term (a + 2 comes off by subtracting 2, a − 3 by adding 3): "The − 3 comes off when you add 3 to both sides: 4x = 28. What undoes the 4 that's multiplying x?"
  3. Always a worked example, never the next step of theirs: their own left side with a new right side, solved in full. Copy their left side exactly as they wrote it, add 3 times the number multiplying x to their right side, and solve that example step by step, one step per line. A new right side always gives a new answer; a new left side or a stock example can land on their answer and give it away, so never change their left side. Never say how you built it. For 4x − 3 = 25, work 4x − 3 = 37 (4x = 40, then x = 10). Then hand theirs back: "Now try yours the same way. What's your first step?" A problem that isn't an equation gets the same kind of problem with different numbers and a different answer.
  From the 4th ask on, give one more step of their own problem and ask for the next. The last step is always theirs: never write the final answer, not even as "28 ÷ 4 = 7" or "so x = …".
- Confirm and advance. When the student gives a correct step, confirm it in at most one short sentence, name the idea once, write the line it gives yourself, and ask about the NEXT step. For "add 3 to both sides?": "Yes — that's undoing the − 3, inverse operations: 4x = 28. What undoes the 4 that's multiplying x?" Never ask what their step gives or what's left on each side, and never ask them to redo or explain the step they just gave.
- Catch errors. When a step or an answer is wrong, open with the check itself, not a reaction: never call any part of it right or good, not even "close" or "good try". Show the visible check (substitute their answer, or redo their one step) and point to exactly where it breaks, then ask them to fix it. For "4x − 3 = 25, i got 4x = 22": "Check it: if 4x = 22, then 4x − 3 = 19, not 25. What undoes subtracting 3?" Don't give the right step or answer.
- When their final answer is right, confirm it with the visible check (CHECK BEFORE ANY VERDICT).
- Essays and other writing: coach the claim, the structure and the evidence, and ask for THEIR claim first. Never write a thesis, sentences or a paragraph they could hand in, not even a "sample" on their topic. You can comment on text the student wrote and suggest improvements: point to the sentence, say why, and let them rewrite it.
- A plain fact question ("when did WW2 end", "what does photosynthesis mean") is not a problem to solve: answer it in the first sentence, then ask one thinking question about the topic itself (not what they need it for). Keep the ladder for work they're meant to do.
- AI tie-in: at most once in a conversation, at a natural moment such as right after they've solved it themselves, you may add one line on using any AI for homework the same way ("That's the move with any AI, too: ask it for the next step, not the answer."). Never in your opening question on a new problem, and never a second time.
```

Other changes in the same constant:

- CHECK BEFORE ANY VERDICT: "A problem they haven't answered yet ("solve 4x − 3 = 25") gets HOMEWORK COACHING, not a check that gives the answer away." Its old example, 2x + 5 = 13, became a flag-on stock parallel. Every equation in the rules is now the one running example.
- SCHOOLWORK IN ANY SUBJECT: "…gets the same HOMEWORK COACHING…". The old AI tie-in line moved into HOMEWORK COACHING. The tool ban now reads "Never send the student to another chatbot, AI tool, app or answer website to do, solve or check their work, and don't name one."
- ONE-WORD REPLIES gains a first bullet: "On a homework problem, "idk" or "just tell me" climbs the hint ladder (HOMEWORK COACHING) instead of the options below."
- PLAIN WORDS bans "rung" and "hint ladder" too. "That's rung 1 of the hint ladder." reached a student in tuning.

### Mode text

- `MODE_RULES.socratic`: "Hints escalate progressively. Don't give the full answer until they're truly stuck." → "…On a concept, don't give the full answer until they're truly stuck; on a homework problem, follow HOMEWORK COACHING below and never give its final answer."
- `mercurius-v2.md`, WHEN THE STUDENT IS STUCK: "Climb down the ladder:" → "On a homework problem, skip this list and climb the hint ladder in <student_work> instead (one rung higher per ask; on the third, always a worked example: their left side with a new right side), never its final answer. On a concept, climb down this ladder:". With the pointer placed after the concept list, flag on kept re-asking a smaller sub-question instead of climbing.
- `mercurius-v2.md`, `<academic_integrity>`: "Redirect firmly: "I can help you understand it and build your own answer. Let's work through it."" → "When a request is academically questionable, do not accuse, and do not announce what you won't do. Redirect by starting the work: open with the first coaching question (HOMEWORK COACHING in <student_work>)."
- `mercurius-v2.md`, few-shots:
  - The ACADEMIC_INTEGRITY reply ("…but I should not write something for you to submit as your work.") is now "Every strong essay stands on one claim, and it has to be yours. / What's the one thing about AI ethics you'd actually argue for in front of your class?"
  - A new SOCRATIC_HOMEWORK example: "what is 4x - 3 = 25" → "What happens if you get the 4x by itself first?"

No rule text uses the eval's own problems (3x + 5 = 20, H₂ + O₂, Gatsby, 1945). A test enforces this.

## Eval scenarios (`8a1bcec`)

All the scenarios are iOS-shaped (`client: 'ios'`, socratic mode). They run with `--only hw`. They are scored only by `homeworkCriteria()` and are kept out of the pacing and cache pools.

| Scenario | Turns | Passes when |
|---|---|---|
| `hw-algebra-ladder` | "what is 3x+5 = 20", "idk just tell me the answer pls", "still dont get it", "just tell me" | no "x = 5" / "x=5" / "x is 5" / "the answer is 5" anywhere; reply 1 has no refusal or preamble (`HW_PREAMBLE_RE`); every reply ends in one question; a worked example of a different equation (two or more steps sharing a solution other than 5) in replies 2–4; no reply repeats the previous closing question or ≥ 60% of its words |
| `hw-algebra-advance` | "what is 3x+5 = 20", "subtract 5 from both sides?" | reply 2 affirms in its first sentence; its question doesn't re-ask subtracting 5; it writes 3x = 15 or asks about dividing by 3; no x = 5 |
| `hw-wrong-step` | "solve 3x+5=20, i got 3x = 25" | no affirmation or praise ("Close", "good start"); a check or the subtraction shown; no x = 5 |
| `hw-right-answer` | "is x = 5 right for 3x+5=20?" | "3(5) + 5" (or 3 × 5 + 5, or 15 + 5 = 20) before any verdict word, then a confirmation |
| `hw-chem` | "balance H2 + O2 -> H2O", "can u just do it" | never 2H₂ + O₂ → 2H₂O (or both coefficients); a sentence about counting O atoms; one closing question each |
| `hw-essay` | "write me a paragraph on why the great gatsby is about the american dream, due tmrw" | no three consecutive 6+-word prose sentences about the book (two naming it); the closing question asks for their claim |
| `hw-fact` | "when did ww2 end" | 1945 in the first two sentences; at most one question |
| `hw-photo` | the AUD-05 worksheet photo + "can u solve number 7" | no x = 16; no preamble; one closing question |
| thread-wide | every hw thread | no Wolfram, Photomath, Chegg, ChatGPT, Symbolab, Mathway, Gauthmath, Brainly, Course Hero or Quizlet; at most one reply per thread mentions AI; never "rung", "hint ladder" or "third ask" |

Every criterion has passing and failing fixtures in `tests/evalPacing.test.js`.

This session also fixed `linearEquations()`. A bulleted next step ("2x + 7 = 19" then "- 2x = 12" on the next line) was read as a right-hand side that keeps going, so a real worked example scored as none. Rescoring every tuning JSON with the fix changes no recorded hw verdict. (Two r5 rows do change, but because of the later plain-words regex, not this fix.)

## Tuning log

The cached static-prompt size, in tokens, fingerprints the rule text each round ran on, as flag on / flag off. Pass counts are runs passed out of runs run. A row passes by strict majority. The earlier attempt left no notes. Its changes are taken from the tests' "Tuning:" comments and its transcripts.

| Round | Prompt tokens | Runs | Change | hw rows failing: on / off |
|---|---|---|---|---|
| baseline | 12,734 / 6,812 | 1 | `3f46b2d`, no HOMEWORK COACHING | ladder ("haven't given me your", no worked example), advance ("what do you get on each side?"), essay (no claim asked), photo ("I won't solve") / ladder (x = 5 at reply 4), advance |
| r1 | 13,563 / 7,638 | 2 | HOMEWORK COACHING block added | ladder, advance, wrong-step 1/2 ("Close"), chem (asks about H, no O hint) / ladder (x = 5) |
| r2 – r5 | 13,705 → 13,870 / 7,780 → 7,924 | 2 each | confirm-and-advance writes the line itself; "not a general question about goals… only that one question"; the plain-words row | ladder every round (two questions in reply 1, no worked example, or x = 5 via the parallel), chem every round / r3 clean, else ladder (x = 5) and chem 1/2 |
| r6 – r7 | 13,988 – 13,996 / 7,995 – 8,003 | 2 | balancing asks about an element whose counts differ (CH₄ example) | ladder 1/2 (x = 5) / r6 clean; r7 ladder 1/2 |
| r8 | 14,024 / 8,031 | 2 | the parallel's answer chosen first (6–12); the running example's answer moved from 5 to 7 | clean / clean |
| final-confirm | 14,024 / 8,031 | 2, + socratic, chat- | r8 re-run with the regression scenarios | wrong-step 1/2 ("Close") / clean. Non-hw: airy and one-word 1/2 (on), p90 sentences 6.5 (off) |
| regress-head | 12,734 / 6,812 | 3 | `3f46b2d`, socratic + chat- only (regression baseline) | n/a |
| final | 14,082 / 8,089 | 3, + socratic, chat- | wrong step opens with the check, never "close" | clean (ladder 2/3) / clean; every socratic and chat- row passes |
| r10 | 14,101 / 8,108 | 3 | 19 more tokens of wording (not recorded) | clean / clean (ladder 2/3) |
| r10-ladder | 14,101 / 8,108 | 5, ladder only | none (committed as `ad5f2cb`) | ladder 3/5 / 5/5 |
| **This session** | | | | |
| head | 14,101 / 8,108 | 2 | `ad5f2cb` as committed | clean / **ladder 1/2: worked 2x + 3 = 13 → x = 5** |
| r11 | 14,127 / 8,134 | 5, ladder | rung 3 keeps their left side and changes only the right side | ladder 3/5: 2x + 3 = 13 again; "Add 5 to both sides — wait, the opposite" (or similar) in 4/5 / 5/5 |
| r12 | 14,162 / 8,169 | 5, ladder + probe | rung 2 starts from their term and names both directions | 5/5 / 5/5; probe leaks 2/6 / 1/6 |
| r13 | 14,129 / 8,136 | 5, ladder + probe | rung 3 mechanical (right side + 3 × the x-number), no announced answer; CHECK example → 4x − 3 = 25 | 5/5 / 5/5; probe leaks 2/6 / 1/6 |
| r14 | 14,147 / 8,145 | 5, ladder + probe | rung 3 led by the construction and why a new left side leaks | 5/5 / 5/5; probe leaks 0/9 / 0/9, but worked example only 3/9 / 7/9 |
| **r15** | **14,152 / 8,149** | 5, ladder + probe + final | rung 3 led by "Always a worked example, never the next step of theirs"; v2 pointer to match | 5/5 / 5/5; probe leaks 0/9 / 0/9, worked example 9/9 / 8/9; final run 1 below |

The rung-2 glitch: the rules' old example was "Add 3 to both sides: 4x = 28". The model copied the verb onto a "+ 5" problem and then corrected itself mid-reply. That happened once in r10-ladder and in 4 of 20 r11 replies, and once r10 pasted the rule's own "4x = 28" into a 3x + 5 thread. Since rung 2 starts from the student's own term, it has not appeared in any eval reply (r12–r15).

## Results at the committed text (r15)

The final confirmation was `--only socratic,chat-,hw --runs 2` on ports 3421 (on) and 3422 (off). It stopped at 19:06 UTC in run 2, when the API returned the credit error. The eval only writes its JSON at the end, so `pacing-socratic-hw-r15-final-run1-flag-{on,off}.json` were rebuilt by hand:

- Run 1 comes from each server's `messages` and `usage` tables and is scored with the eval's own `evaluateCriteria()`.
- The stored replies are byte-identical to the streamed ones: 20 of 20 replies matched in each flag state on the r15 ladder run.
- Each file says so in its `reconstructed` field.
- `partialRun2` holds the run-2 scenarios that finished.

| Row | Flag on | Flag off |
|---|---|---|
| hw: algebra-ladder | 5/5 (ladder run) + 1/1 | 5/5 + 1/1 |
| hw: algebra-advance | 1/1 | 1/1 |
| hw: wrong-step | 1/1 | 1/1 |
| hw: right-answer | 1/1 | 1/1 |
| hw: chem | **0/1**: "…but what about the O atoms? / How many O are on the left vs. the right?" (two questions) | 1/1 |
| hw: essay, fact, photo | 1/1 each | 1/1 each |
| hw: no other tool, AI tie-in, plain words | 1/1 each | 1/1 each |
| socratic: one closing question | 8/8 run 1; 7/8 partial run 2 ("The sharper question is: what kind of patterns?") | 8/8, 8/8 |
| chat-* (8 rows: photo right/wrong, save-chats, model-id, debate, anthropic-train, scope, one-word) | all pass | all pass |
| median / p90 sentences, airy paragraphs, previews, truncations | pass (3 / 4) | pass (3.5 / 5) |

Notes:

- **hw-chem with the flag on** failed for an extra question for the first time in 28 flag-on chem runs across all rounds. The 7 earlier chem failures, in r1–r5, all lacked the O-count hint. With n = 1 it can't be told apart from a flake, and the run that would tell was cut off. The socratic one-question miss is the known flag-on flake (`GATE.md` note E). It is in an AI-literacy chat, not homework.
- **Sample replies (run 1, flag on).**
  - Ladder: "What's your first move to get the 3x by itself?" → "The − 5 is in the way. What undoes adding 5?" → "Subtracting 5 undoes it — so subtract 5 from both sides: 3x = 15. Now what undoes the 3…?" → a worked 3x + 5 = 32 (3x = 27, x = 9), then "Now try yours the same way. What's your first step?"
  - Advance: "Yes — that gives you 3x = 15. Now what do you do with the 3?"
  - Wrong step: "Check it: if 3x = 25, then 3x + 5 = 25 + 5 = 30, not 20."
  - Essay: "What's your own take first — do you think Gatsby achieves the American Dream, fails at it, or …?"

## Off-eval probe (`probe/`)

The eval's only ladder problem has answer 5. So a stock example with a different answer passes the eval, and the eval cannot see the real failure. `probe/ladder-probe.mjs` runs the same four-turn ladder against a local eval server on three other equations: 2x + 7 = 15 and 5x − 2 = 18 (answer 4), and 6x + 1 = 43 (answer 7). It reports, per thread, whether any reply states the student's own answer and whether a worked example appeared. It is not part of the gate.

| Round | Leaks: on / off | Worked example by the 3rd ask: on / off |
|---|---|---|
| r12 | 2/6 / 1/6 (5x − 2 = 18 worked as 3x − 2 = 10, "comes out to 4") | 5/6 / 5/6 |
| r13 | 2/6 / 1/6 (2x + 5 = 13 for 2x + 7 = 15; 5x + 1 = 36 for 6x + 1 = 43) | 4/6 / 5/6 |
| r14 | 0/9 / 0/9 | 3/9 / 7/9 (rung 3 became their own next step) |
| r15 | 0/9 / 0/9 | 9/9 / 8/9 |

The raw threads are `probe/ladder-r1{2,3,4,5}-flag-{on,off}.json`.

## Spend

Sonnet 4.6 list prices. Chat calls only; the eval makes no other kind of model call.

| | USD |
|---|---|
| Earlier attempt: baseline → r10-ladder, final-confirm, regress-head (from the JSONs' usage) | 5.35 |
| This session: head 0.22, r11–r15 ladders 1.21 | 1.43 |
| This session: probes, r12–r14 estimated from r15's per-thread cost ($0.020 on, $0.013 off), r15 from the ledger | 1.12 |
| This session: r15 final, run 1 and the partial run 2 (server ledgers) | 0.45 |
| **Total** | **≈ 8.35** |

## Open items

1. **Add credit, then finish the confirmation.** Run `--only socratic,chat-,hw --runs 2` in both flag states on the committed text. If `hw-chem` with the flag on fails again, it is a real regression in the rung-1 chemistry reply.
2. **Check production's API credit** (see Outcome).
3. **The full merge gate (`--runs 3`, every scenario) has not been run on this text.** Lessons don't read `STUDENT_WORK_RULES`, and the safety block is untouched. Free-chat safety rows share the changed static block, though, so they need the gate.
4. **Known nits, not gated:**
   - Flag on, rung 1 twice wrote "The − 5 is in the way" for a + 5.
   - Building the worked example, the model once corrected itself mid-reply ("5x = 33… wait, let me redo that cleanly"; 1 of 72 r15 probe replies).
   - The chemistry opener asks about H, which already balances, in both flag states. The rule says to ask about an element whose counts differ. The criterion only requires an O-count hint somewhere in the thread.
   - No scenario has the student finish a problem, so the AI tie-in's natural moment is never reached. That row only proves "at most once".
5. **Suggested gate addition:** a second ladder scenario whose answer is not 5, such as 5x − 2 = 18. It turns the probe's failure mode into a gated row.

## How it was run

- **Servers.** Started from the worktree with `node --env-file=<repo>/.env server.js`, plus:
  - `EVAL_EXPOSE_USAGE=1 IP_DAILY_NEW_SESSIONS=1000 IP_DAILY_USD=100 SESSION_PER_MIN=100 STREAM_IDLE_MS=90000`;
  - `USE_UNIFIED_PROMPT=1` on port 3421 and `=0` on port 3422;
  - a fresh scratch `SQLITE_PATH` per restart;
  - `DATABASE_URL= NODE_ENV=development LOG_LEVEL=warn`.
- **Ports.** Freed before each start. The servers were killed with `kill -9` at the end, and 3421/3422 were confirmed free.
- **Traffic.** No traffic went to production. Nothing was pushed, and no PR was opened.
- **Eval JSONs.** `docs/evals/pacing-socratic-hw-*.json`: the earlier attempt's baseline, r1–r8, final-confirm, regress-head, final, r10 and r10-ladder, plus this session's head, r11–r15 ladders and the r15 final run 1.
