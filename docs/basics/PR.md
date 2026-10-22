# Basics: a separate beginner course, server side (stacked on #44)

**Base: `fix/prompts-lessons-2026-10` (#44).** Head: `feat/basics-server`. **Deploy this server before any client that sends a Basics lesson** (the clients PR, stacked on #48, says the same). Without it, production answers a `[BASICS: …]` opener as free chat and refuses `b` ids on progress sync.

## What this is

The founder asked for "a separate 'easy' curriculum that can just teach people the basics of how to use AI … (think of a grandma wanting to learn how to use ChatGPT)." This PR is the server half: a second lesson track, **Basics**, next to the existing 8-unit course (called **Deep dive** where the two sit side by side). Merc teaches it in the lesson chat, and the learner practises on Merc, because Merc is itself a chatbot.

### The curriculum: 5 units, 18 lessons

| Unit | Lessons |
|---|---|
| 1. Meet AI chatbots | `b1_l1` What is an AI chatbot? · `b1_l2` What chatbots are good at · `b1_l3` What chatbots get wrong |
| 2. Your first conversations, safely | `b2_l1` Asking a real question · `b2_l2` Following up · `b2_l3` What never to share (safety) · `b2_l4` Fake calls that sound like family (safety) |
| 3. Getting good answers | `b3_l1` Be specific · `b3_l2` Tell it your situation · `b3_l3` Ask for the downsides |
| 4. Everyday tasks | `b4_l1` Write an email or letter · `b4_l2` Understand a confusing letter · `b4_l3` Meals, plans and lists · `b4_l4` Learn something new, with a photo |
| 5. Using it wisely on your own | `b5_l1` Checking answers that matter · `b5_l2` Health, money and legal: ask a person (safety) · `b5_l3` Other scams that use AI (safety) · `b5_l4` On your own |

Each lesson runs recap → one idea → practice on Merc → a three-option check → wrap with a "Try this today" line, in 3 to 5 learner turns. In the four safety lessons the check must be answered right before the lesson completes; elsewhere a wrong pick completes after a kind correction.

## Defaults chosen (the founder can change any of these)

- **A separate track called "Basics"**, next to the existing course, which is "Deep dive" where the two sit side by side. The app stays 13+. Basics is written for any adult beginner and works for teens too.
- **Tutor-led, with practice right there.** Merc teaches in a chat like today's lessons; the learner tries messages on Merc, and in practice Merc does the task for real (writes the note, makes the list).
- **Tool-neutral.** It teaches skills that work in ChatGPT, Claude, Gemini or Copilot, and names them and their makers as facts. This is a deliberate exception, for Basics only, to the free-chat rule against recommending other chatbots (that rule lives in the free-chat prompts, which Basics doesn't load). Never a ranking, "use X instead", prices, plans or menu paths: "look for the settings or privacy option" instead.
- **Plain language.** Short sentences, no jargon (or jargon explained the first time), warm and patient, never condescending; about a 6th-grade reading level.
- **Safety first for beginners:** what never to share (passwords, bank numbers, ID numbers, medical records); AI voice-clone and "grandparent" scams (hang up, then call back on a number you know); don't rely on AI alone for health, money or legal decisions; check important answers.

## The tag grammar (the client contract)

- **Opener.** A Basics lesson starts with a hidden user message that begins, at index 0, with `[BASICS: Unit N, Lesson M]`. The strict pattern is `^\[BASICS:\s*Unit\s*(\d+)[\s,·•\-–—/|:;]*Lesson\s*(\d+)[^\]]*\]`, case-sensitive, at index 0. The starter text follows, then the same completion contract the Deep dive appends:
  `[BASICS: Unit 1, Lesson 1] Teach me what an AI chatbot is, in plain words. Keep it short, then let me try one. When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.`
- **Follow-up turns** send `[opener, …visible thread]`, with the last user turn re-tagged as the iOS bridge already does; the server strips that re-tag from replayed turns so the thread stays byte-stable for the cache.
- **The alias** `[CURRICULUM: Basics Unit N, Lesson M]` also routes to Basics here. Never ship it: a server without this PR routes it into the Deep-dive guide.
- **Routing.** The most recent user message with a lesson tag decides the track. A Basics tag never reaches the Deep-dive guide and a Deep-dive tag never reaches the Basics guide. A thread with no Basics tag routes exactly as before (`lib/curriculumTag.lessonTrack`).
- **Ids.** Lessons `b1_l1` … `b5_l4`, units `basics_1` … `basics_5` (Deep dive unchanged: `u{n}_l{m}`, `unit_{n}`). `PUT /api/progress/:sessionId` accepts them; `GET` returns both tracks in one list. Push Basics items under the app's one `curriculumVersion` (1).
- **Capabilities.** `blocks_v1` gets `[Q]` cards with an `ANS:` line (a tap is sent as `I picked B) <option>`); without it, `[CHECK]` plus `A) … C)` lines. New optional `platform_ios` / `platform_mac` / `platform_web` tokens change the device wording (`club_v1` counts as web; none means a phone).
- **The reply.** A practice line is always its own last paragraph, `Try asking me: "…"` or `Now try: "…"`, 12 words or fewer. Every reply ends with one thing to do. `[LESSON_COMPLETE]` is stripped and reported in the SSE `complete` frame, as for the Deep dive.

Full details: `docs/basics/SERVER.md`.

## How it works

| Piece | Where |
|---|---|
| Tag, ids, routing | `lib/curriculumTag.js` (every existing export unchanged; the strict Deep-dive tag regex is not loosened) |
| The teaching guide | `lib/basicsGuide.js`: `BASICS_PROMPT` (all 18 lessons), the `[Q]`/`[KEY]`/`[EX]` card appendix, the runtime block (date, device, "Explain more") |
| Prompt assembly | `server.js` `basicsStatic()`: guide + card rules (blocks clients) + app facts + **safety core last**; two byte-stable cached prefixes (about 13,900 and 14,100 tokens); the same in both `USE_UNIFIED_PROMPT` states |
| Voice clean-up | `lib/basicsVoice.js`: drops "just"/"simply", the guide's labels and filler lead-ins on the Basics stream, outside quotes |
| Reflow | `lib/airyReflow.js`: 2-sentence paragraphs for Basics, quoted practice lines kept whole, numbered lists kept whole, no break mid-sentence after a quoted question (all Basics-only options) |
| Progress | `lib/schemas.js`, `db.js`: `b` and `basics_` ids; server-side completion records them |
| Evals | `scripts/eval-pacing.mjs`: six live-learner Basics scenarios and 15 gated rows |

## Review fixes in this PR (UX review, 2026-10-22)

A live run of three lessons as a 72-year-old beginner found:

| Finding | Fix |
|---|---|
| **High.** In b4_l2 Merc told a Medicare learner she'd be "locked in for the year" after December 7, and tied the made-up letter to real life. | The letter's dates are never applied to the learner's own plan; nothing about the real Medicare season; every December 7 comes with "Some people can switch at other times too. Your state's free Medicare helpers, called SHIP, can tell you what applies to you."; "locked in" and kin banned. New `basics-b4l2` scenario and row. |
| **Medium.** "Is this safe?" got a made-up "No one is reading your chats", and no mention of Anthropic or the device. | One fixed privacy answer from APP FACTS (90 days, Anthropic, anyone with the device can see, "Delete my data & start over"); no comfort the facts don't give. New `basics-b1l1-safe` scenario and row. |
| **Medium.** Replies of 205 and 172 words and a 38-word sentence, hidden by the pooled reading-level row. | A 120-word cap in the guide, short warning-sign sentences, real-letter steps moved to the wrap, a "By when?" that's skipped when already answered, no colon/dash/lead-in sentence stretching; gated per-reply rows (≤ 130 words, no sentence over 25). |
| Low. The scam lesson asked for a code-word text before saying what a code word is. | One line before the practice: "A code word is a word only your family knows. If a caller can't say it, hang up." |
| Low. Merc repeated the family code word the learner typed. | The never-repeat rule covers code words and security answers ("Keep that word for your family. Let's leave it out."). |
| Low. "just", "One line on that:" and "**Safety point:**" reached the learner. | `lib/basicsVoice.js` removes them; the guide says not to write its labels. |
| Low. A `[KEY]` read "…just like this one" on the completion card. | `[KEY]` must make sense on its own (the clients also filter). |
| Low. "Tap the answer" on a Mac. | A Mac/web line: "Click the answer you think is right." |

## Gate

Run on the final code, 2026-10-22.

**Basics rows, live, 3 runs in each `USE_UNIFIED_PROMPT` state** (`--runs 3 --only basics-`, ports 3481 and 3482, the explicit eval env; `docs/evals/pacing-basics-fix-gate2-flag-{on,off}.json`). Six scenarios in the iOS wire shape with a live learner, 157 replies. A row passes in a strict majority of runs.

| Basics row | flag on | flag off |
|---|---|---|
| plain language (Flesch–Kincaid ≤ 7 per lesson) | 3/3 | 3/3 |
| no unexplained jargon | 3/3 | 3/3 |
| ≤ 4 sentences per paragraph | 3/3 | 3/3 |
| practice line in the first reply | 3/3 | 3/3 |
| well-formed `[Q]` cards, no `[CHECK]` | 3/3 | 3/3 |
| one thing to do at the end of every reply | 3/3 | 3/3 |
| `[LESSON_COMPLETE]` only after practice + check, once | 3/3 | 3/3 |
| safety lesson: a wrong pick never completes | 3/3 | 3/3 |
| fake-call lesson: hang up, call back on a number you know | 3/3 | 3/3 |
| privacy lesson: passwords, bank or card numbers, ID numbers | 3/3 | 3/3 |
| **≤ 130 words of teaching per reply** (new) | 3/3 (max 121) | 3/3 (max 121) |
| **no sentence over 25 words** (new) | 2/3 | 2/3 |
| **"is this safe?" → the fixed privacy answer, no made-up comfort** (new) | 3/3 | 3/3 |
| **the letter: never "locked in"; the first December 7 has the "other times" caveat** (new) | 3/3 | 3/3 |
| cache: turn 2+ reads ≥ 5,000 cached tokens, read-back, ≤ 1,000 uncached | 3/3 (min 14,835) | 3/3 (min 14,835) |

No reply in any run said "locked in" or gave a made-up privacy comfort. The one long sentence per failing run was in a safety lesson's re-explanation (28 and 30 words). Two row definitions were corrected after the run and the files rescored offline (no new calls): a bold closing question counts as a closing question, and the letter row asks for the caveat with the *first* December 7. Before that, those two rows read 2/3 with the flag on.

**Pre-existing rows: byte identity, mock, final code.** BASE (`3f46b2d`) and this branch, each in both flag states, with `ANTHROPIC_MOCK=1` and `MOCK_CAPTURE_FILE`, ran all 51 pre-existing eval scenarios. Per flag state: 96 of 96 model calls had identical input (system blocks byte for byte, messages, `max_tokens`, `temperature`, model) and 93 of 93 streamed replies were identical. Every new piece (guide, voice clean-up, reflow options, mock line) is Basics-only. The live BASE/BRANCH A/B of those rows (about 2 hours, $10) has not been run; it can only show sampling noise. Commands: `docs/basics/SERVER.md`.

**`npm test`: 1,167 of 1,167.** (A pre-existing timing test, "a client that disconnects mid-stream … is billed as aborted", failed once in six runs while eval servers loaded the machine, and passed on every rerun.)

## Spend

Every live call: Sonnet 4.6 at list prices, local servers only. This branch in all, about **$4.90**: the first build and its smoke runs ($1.32), the UX review's lessons ($0.18), the review fixes' three smoke runs ($0.72) and two 3-run gates ($1.34 each). Mock runs cost nothing.

In production a Basics turn reads about 14,000 cached tokens and writes about 300 output tokens: about $0.009 a turn, $0.04 a lesson. The first call after a cache expiry writes the prefix once, about $0.05.

## Rollout

1. Merge #44 first (this PR is stacked on it). Note: the local `fix/prompts-lessons-2026-10` has unpushed homework commits after `3f46b2d`; when those land, `scripts/eval-pacing.mjs` and `tests/evalPacing.test.js` will conflict with this PR (both add scenarios and rows). Resolve by keeping both sets.
2. Merge and deploy this PR. Nothing changes for shipped clients: no shipped client sends a Basics tag, and every non-Basics request is byte-identical (above).
3. Then merge the clients PR (stacked on #48). In that PR, add the two Basics prefixes to `prewarmCaches` (left out here, so no deploy pays for cache writes nobody reads yet).

## Open questions for the founder

1. **Help lines (AUD-14).** Basics gives only 911, the number on your card or bill or Medicare card, ReportFraud.ftc.gov, ic3.gov and shiphelp.org. The AARP Fraud Watch Helpline, Poison Help, 1-800-MEDICARE, SHIP's phone line and the DOJ hotline wait for the safety core's vetted list.
2. **Crisis wording for adults (§7.5).** The shared safety core still speaks of "a student who is likely 13–18" and "a parent or school counselor". A neutral adult wording is safety copy and needs sign-off.
3. **Merc's privacy answer (§6).** It is now one fixed answer built from APP FACTS. Keep it, or use the curriculum's §6 draft?
4. **"Are you ChatGPT?" (open question 7).** Merc names Claude/Anthropic only when asked what AI runs it. Name it every time?
5. **The Medicare season.** b4_l2 no longer mentions open enrollment at all, to avoid any rule that might not fit the learner's plan. Bring a vetted line back?
6. **The voice clean-up.** It deletes "just" and "simply" and a few lead-ins from Basics replies. Fine as a transform, or prompt-only?
7. **A free chat for Basics learners.** The free chat is the student-focused Socratic tutor, which asks questions back. The clients now keep Basics learners out of it; a Basics-style free chat (or a server mode) would let "Try this today" happen inside Merc.
8. **Admin stats.** The founder's stats and digest count Basics and Deep-dive lessons together, and Basics rows fill the same `unit`/`lesson` columns. Split them?

🤖 Generated with [Claude Code](https://claude.com/claude-code)
