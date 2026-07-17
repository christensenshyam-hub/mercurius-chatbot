# Response Quality

How Mercurius decides what to say, how long to say it, and in what voice.
There are **two orthogonal dials** controlling output:

| Dial | What it controls | Who picks it |
| --- | --- | --- |
| **App mode** (`mode`) | Pedagogical posture — Socratic / Direct / Debate / Discussion | The user, via the mode pills in the chat header |
| **Response mode** (`response_mode`) | Length & depth — `one_line` / `concise` / `balanced` / `deep` | Defaults to `concise`; the user implicitly switches to `deep` by tapping **Explain more** |

Mode says *how to teach*. Response mode says *how much to say*. Both are
respected on every turn.

## App modes (existing — unchanged)

The four modes the user sees in the pill row:

- **Socratic** — guides through questions; one strong question per turn,
  at most one new idea of setup, hints that escalate progressively. The
  question is always the last line. Default mode for new users.
- **Direct** — plain, efficient answers. Answers only what was asked, no
  teaching framing, no Socratic detours. Locked behind a comprehension
  check.
- **Debate** — adversarial, four-line structure: claim · warrant · impact ·
  rebuttal angle. One argument per turn, then it hands the turn back with
  a single challenge.
- **Discussion** — conversational, balanced; surfaces tradeoffs rather
  than verdicts; pulls ONE tension per turn and ends with one open
  follow-up, not a conclusion.

These modes are persisted server-side and never silently mutate. A
conversation started in Debate stays in Debate.

## Response modes (new)

The four length/depth tiers, each with its own token + temperature
budget. Defined once in [`lib/responseQuality.js`](../lib/responseQuality.js).

| Mode | `max_tokens` | `temperature` | When |
| --- | ---: | ---: | --- |
| `one_line` | 120 | 0.3 | Quick facts, short rewrites. Reserved for explicit one-liner asks. |
| `concise` | **250** | 0.4 | **Default.** 2–4 sentences or 3–4 tight bullets. The mobile-native answer. |
| `balanced` | 600 | 0.6 | Moderate depth — a mid-length explanation with one example. |
| `deep` | 1400 | 0.7 | Used when the user taps **Explain more**. Layered, thorough, but explicitly told not to repeat what was already said. |

> **History:** the original ship set `concise` to 400 and `balanced`
> to 700. Pre-TestFlight QA found `concise` at 400 still felt
> long-winded on a phone, so May 2026 the budgets were tightened to
> the values above and the preamble's default length dropped from
> "3–6 sentences" to "2–4 sentences".

Lower temperature on the short modes keeps them on-task; higher
temperature on `deep` allows for more synthesis-style output where
variety helps. Token caps are upper bounds — the model usually comes
in well under them when the system prompt asks for brevity.

## The universal preamble

Every chat request prepends a short response-quality preamble + the
mode-specific rules to the system prompt. The model sees concision
guidance *before* the deeper pedagogical material:

```
## RESPONSE QUALITY (read first; applies to every reply)
- Lead with the direct answer. No "Great question", "Sure!", or other warm-up.
- ONE idea per reply. Teach a single load-bearing concept, then stop — the
  CONVERSATION is the unit of teaching, not the message.
- Never preview what's coming or enumerate everything at once.
- Default length: 2–4 sentences, OR 3–4 tight bullets. Skip filler and hedging.
- Format for a phone screen: short paragraphs (≤3 lines). Never repeat what's
  already established in the thread.
- End with exactly ONE short question or forward invitation.
- Only go deep when the user asks for it (they have an "Explain more" button).
- When in doubt, stop earlier than you think you should.

## MODE RULES — <SOCRATIC|DIRECT|DEBATE|DISCUSSION>
<mode-specific guidance>
```

### Beat pacing (across-turns)

The preamble's core discipline is **beat pacing**: information is
spaced across the conversation instead of packed into each message.
Each reply spends exactly one "beat" — one load-bearing idea, one
question, one argument, or one tension — and ends with a single
question or forward invitation that earns the next beat. Roadmapping
("there are three factors: …", "next we'll cover X, then Y") is an
explicit failure mode: it front-loads the whole territory and kills
the back-and-forth the tutor is built around. The per-mode rules
restate the same discipline in mode-native terms (Socratic: one
question, last line; Debate: one argument, hand the turn back;
Discussion: one tension, one open follow-up; Direct: answer only what
was asked, optional single offer).

Curriculum mode is not exempt from the *spirit* of beat pacing — its
own prompt (`CURRICULUM_PROMPT` in `server.js`) delivers the lesson's
teach material as 2–3 micro-concept beats, each ending in a single
`[CHECK]` question — but it IS exempt from the preamble itself:

Two paths skip the preamble because they have their own structural
contracts that conflict with the 2–4 sentence default:
- **Curriculum mode** — has its own beats → exercise → feedback cadence
  (`[CURRICULUM: …]` messages).
- **Test evaluator** — emits a fixed `[TEST_PASSED]` / `[TEST_FAILED]`
  marker.

## Explain More

The first answer is concise. If the user wants depth, they tap
**Explain more** below the assistant's last bubble. That:

1. Cancels nothing visible. The user's chat history is unchanged —
   no synthetic "Explain more" message lands in the thread.
2. Sends the request with `response_mode: "deep"` and a wire-only
   injected user turn carrying the instruction `"Explain more — go
   deeper on the same topic. Don't repeat what you already said."`
   The server sees that turn (and saves it to the memory table for
   downstream context) but the iOS chat UI never displays it.
3. The server appends an `EXPAND-MODE NOTE` to the system prompt
   reinforcing the don't-repeat-yourself directive. The note also
   suspends the one-idea-per-turn pacing rule for that single reply —
   deep is the sanctioned way to get more than one beat at once —
   while still requiring one forward question at the end.
4. The next user-typed message defaults back to `.concise`. Deep is
   one-shot, never sticky.

Implemented in `ChatViewModel.explainMore()` (which calls
`runStream(..., injectedUserTurn:)`); the affordance is rendered
by `MessageListView.explainMoreFooter`.

### Why the instruction is hidden

Earlier iteration appended a literal user message to the thread for
honesty. In TestFlight QA that read as a junk message students
hadn't typed. Hiding the instruction trades that for a slight
asymmetry between client view and server memory — acceptable
because the server's memory profile isn't replayed verbatim into
the chat UI.

## Why concise is the default

The product is a phone-first AI literacy tutor for high school
students. A 12-paragraph response on a 6.1" screen is unreadable.
"Concise by default, deep on tap" matches how students actually use
chat apps — and it lets the model *prove its value* in a single
glance rather than asking the user to scroll past warm-up.

The preamble explicitly bans:
- "Great question", "Sure!", and other openers
- Hedging and filler
- Restating the previous turn
- Long conclusions

…all of which were the most common reasons earlier responses felt
"long-winded" in pre-TestFlight QA.

## Wire contract

`POST /api/chat` accepts an optional `responseMode` field:

```json
{
  "sessionId": "abc123",
  "messages": [{ "role": "user", "content": "How do LLMs work?" }],
  "responseMode": "concise"
}
```

| Server behavior | Trigger |
| --- | --- |
| `responseMode` missing | Default to `concise` |
| `responseMode` is one of the four valid values | Use it |
| `responseMode` is anything else (typo, wrong type) | `400 invalid_request` (Zod rejection) |
| `responseMode === "deep"` | Append the `EXPAND-MODE NOTE` |

The token cap and temperature on the underlying Anthropic call are
read directly from `RESPONSE_MODE_BUDGETS` — no per-mode heuristic
overrides anymore.

## Logging safety

Nothing in this system logs prompts, replies, message content, API
keys, or auth tokens. The pino redaction paths in `lib/logger.js`
already cover `*.content`, `*.reply`, `*.message`, and the auth
headers; the response-quality preamble is a static constant so it's
not a dynamic value the logger ever sees.

Tests in [`tests/logger.test.js`](../tests/logger.test.js) and
[`tests/responseQuality.test.js`](../tests/responseQuality.test.js)
guard the contract.
