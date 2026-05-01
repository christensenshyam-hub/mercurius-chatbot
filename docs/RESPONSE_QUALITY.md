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
  short scaffolding, hints that escalate progressively. Default mode for
  new users.
- **Direct** — plain, efficient answers. No teaching framing, no Socratic
  detours. Locked behind a comprehension check.
- **Debate** — adversarial, four-line structure: claim · warrant · impact ·
  rebuttal angle. Tight enough for speech prep or live cross-examination.
- **Discussion** — conversational, balanced; surfaces tradeoffs rather
  than verdicts; ends with an open thread, not a conclusion.

These modes are persisted server-side and never silently mutate. A
conversation started in Debate stays in Debate.

## Response modes (new)

The four length/depth tiers, each with its own token + temperature
budget. Defined once in [`lib/responseQuality.js`](../lib/responseQuality.js).

| Mode | `max_tokens` | `temperature` | When |
| --- | ---: | ---: | --- |
| `one_line` | 120 | 0.3 | Quick facts, short rewrites. Reserved for explicit one-liner asks. |
| `concise` | 400 | 0.4 | **Default.** 3–6 sentences or a tight bulleted list. The mobile-native answer. |
| `balanced` | 700 | 0.6 | Moderate depth — a mid-length explanation with one example. |
| `deep` | 1400 | 0.7 | Used when the user taps **Explain more**. Layered, thorough, but explicitly told not to repeat what was already said. |

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
- Default length: 3–6 sentences, OR a tight bulleted list. Skip filler and hedging.
- Format for a phone screen: short paragraphs (≤3 lines), tight bullets.
- Never repeat content already established earlier in the thread.
- Only go deep when the user asks for it (they have an "Explain more" button).
- A short, useful answer beats a thorough lecture every time.

## MODE RULES — <SOCRATIC|DIRECT|DEBATE|DISCUSSION>
<mode-specific guidance>
```

Two paths are exempted because they have their own structural
contracts that conflict with the 3–6 sentence default:
- **Curriculum mode** — has its own teach → exercise → feedback cadence
  (`[CURRICULUM: …]` messages).
- **Test evaluator** — emits a fixed `[TEST_PASSED]` / `[TEST_FAILED]`
  marker.

## Explain More

The first answer is concise. If the user wants depth, they tap
**Explain more** below the assistant's last bubble. That:

1. Sends a new user message — `"Explain more — go deeper, don't repeat
   what you already said."` — visible in the thread (no hidden
   payloads).
2. Sets `response_mode: "deep"` on the wire.
3. The server appends an `EXPAND-MODE NOTE` to the system prompt asking
   the model to layer rather than restate.
4. The next turn snaps back to `.concise`.

Implemented in `ChatViewModel.explainMore()`; the affordance is
rendered by `MessageListView.explainMoreFooter`.

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
