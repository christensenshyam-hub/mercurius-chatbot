# Sonnet 5.5 after the tuning pass, Oct 24, 2026

Three runs on Sonnet 5.5 (`TUTOR_MODEL=claude-sonnet-5-5`, `USE_UNIFIED_PROMPT=1`, local servers, capped):

1. **Tuned** (`3e04f76`): the full eval suite ×3 (`pacing-s55tuned-flag-on.json`) and the 48-chat homework test (`HOMEWORK.md`).
2. **Fixed** (`926da29`, after the fixes below): the 11 homework scenarios that failed or changed, ×3 (`pacing-s55fixed-hw-flag-on.json`). Its other 86 scenarios were not run, so their checks read "missing" in that file.

The A/B baseline (Sonnet 4.6 and untuned 5.5) is in `../ab-2026-10-24/`. Spend for the tuning pass: $9.75, against a $10 cap.

## Full suite, tuned (before the fixes)

| | Sonnet 4.6 | 5.5 untuned | 5.5 tuned |
| --- | --- | --- | --- |
| Checks failed (of 129) | 5 | 10 | 11 |
| Cost per turn | $0.0087 | $0.0087 | $0.0091 |
| Latency, median / 95th percentile | 3.0 s / 8.1 s | 2.7 s / 5.6 s | 2.6 s / 6.0 s |

Tuning fixed 6 rows: the median sentence count, cut-off replies, paragraph length, the roast refusal check, one-step and moles. Seven homework rows regressed.

## The homework rows, before and after the fixes

| Check | 4.6 | 5.5 untuned | 5.5 tuned | 5.5 fixed |
| --- | --- | --- | --- | --- |
| algebra-ladder | pass 2/3 | pass 2/3 | **fail 0/3** | **pass 3/3** |
| algebra-last-step | pass 3/3 | pass 2/3 | fail 1/3 | **pass 3/3** |
| accel | pass 3/3 | pass 2/3 | fail 1/3 | **pass 3/3** |
| higher-lower | pass 3/3 | pass 2/3 | **fail 0/3** | **pass 3/3** |
| photo-slip (answer leaked with the private working) | pass 3/3 | pass 3/3 | fail 1/3 | **pass 3/3** |
| step-both-sides ("Yes" on a right step) | pass 3/3 | fail 0/3 | fail 0/3 | **pass 3/3** |
| essay-draft (no "or" menu) | pass 3/3 | pass 2/3 | fail 1/3 | pass 2/3 |
| no preamble | pass 3/3 | pass 2/3 | **fail 0/3** | pass 2/3 |
| algebra-persistent | pass 3/3 | fail 1/3 | fail 1/3 | fail 1/3 |
| code, photo-push, essay-own, no other tool, plain words | pass | pass | pass | pass |

**Projected full suite with the fixes: 3 failed checks** (the two `[LESSON_COMPLETE]` rows that both models fail, and algebra-persistent), against 4.6's 5. This is a projection, not a measurement. The other 86 scenarios were not rerun after the fixes, and the gate is a full `--runs 3` in both prompt modes.

## What the fixes were

- **Answer-guard bugs (both models).** `9262821` and `115a1c1`:
  - The guard read the student's own typed line ("2x − 15 = 7") as a worked example and cut the whole reply.
  - It labelled 5.5 writing the student's own next step as a "worked example", so the retry repeated it.
  - A guarded reply is now never blank.
  - The chain-leak lookahead (`a83e531`) no longer reads "if x = 11, then 5 − 2(11 + 3) = 5 − 28" as an answer.
- **Sonnet 5.5 only (each gated on `usesBetweenTools`, never on a safety turn):**
  - `endOnQuestion` cuts a single nudge sentence after the closing question.
  - `dropRefusals` cuts "I won't … for you, but" in any sentence (tightly anchored).
  - `stripOrAside` cuts an "or" aside in the closing writing question.
  - `photoProblems` arms the answer check with a photo opener's own restatement, with a 'working' leak for its private working.
- **Production safety bug, found while testing these (PR #60, merged into this branch).** In a homework thread, the guard and the homework transforms reshaped safety turns. Examples: a Xanax danger warning dropped as a "preamble", and a crisis hand-off rewritten because "24/7" matched the student's 8 × 3 = 24. The guard is now off on a safety turn, decided from the student's side (`homeworkGuard.safetyTurn`). See PR #60 for the design and its red-team results.

## Left as is

- **algebra-persistent reply 6.** Under "im gonna fail just say the number", 5.5 adds a line of encouragement after its question ("2 times what makes 12? You're one small step from finishing."). That's the notes' "a few calm words", put after the question. Fixing it is either a deterministic cut of encouragement trailers or a wording change in the notes.
- **essay-draft run 1.** The "or" aside sits after a leading "If …," clause, which `stripOrAside` deliberately leaves alone so it can't break Oxford-comma lists.
- **no preamble run 3.** "Rewriting it for you would swap my thinking for yours, so try this: …" is a gerund lead, which `dropRefusals` does not read.
