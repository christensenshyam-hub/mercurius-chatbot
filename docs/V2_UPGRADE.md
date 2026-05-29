# Mercurius v2 upgrade — unified prompt + web tools

**Status:** Validated in prototype. NOT integrated into production. Do this
**post-launch**, deliberately, with its own testing — not while TestFlight
is in review.

This doc captures the findings from the May 28–29 2026 eval session so they
don't evaporate. Two upgrades are spec'd here: (1) a unified v2 system
prompt, and (2) giving the tutor live web access.

---

## Background: there are currently two separate "Mercuriuses"

1. **Production (what the app uses):** iOS app → Railway backend
   (`server.js`) → plain Messages API (`anthropic.messages.create`) → the
   **per-mode prompts** (`SOCRATIC_PROMPT`, `DEBATE_PROMPT`, … 10 constants)
   → **no tools**.
2. **The Console agent (a prototype):** a Managed Agent
   (`agent_01D65eSncURos6wMpid6ZYW5`, v4 as of this writing) → a single
   **unified v2 prompt** with a mode router → `agent_toolset_20260401`
   (bash/read/write/edit/glob/grep/web_fetch/web_search).

The Console agent is **not wired into the app**. It was built to prototype
the v2 prompt and validate web search. Production still runs path (1).

---

## Part 1 — The unified v2 prompt

A single ~6.5K-token system prompt with a `<mode_router>` that handles all
nine app modes (SOCRATIC / DIRECT / DEBATE / DISCUSSION / CURRICULUM / QUIZ /
REPORT_CARD / CONCEPT_MAP / TEST_EVALUATOR), driven by a `<runtime>` block
the app injects per request:

```
<runtime>
  <mode>SOCRATIC</mode>
  <response_mode>concise</response_mode>
  <direct_mode_unlocked>false</direct_mode_unlocked>
  <current_date>2026-05-29</current_date>
</runtime>
```

It also expects context via `{{template_vars}}` (learner_profile,
conversation_memory, club_knowledge, source_library, case_library,
meeting_context, blog_context, …) — the backend already computes all of
these; it would substitute them into the prompt's slots instead of
string-appending them.

### Why it's better than the current 10 per-mode prompts
- One prompt to maintain; consistent persona; explicit instruction-priority
  hierarchy (safety > system > mode > user > context > memory).
- Built-in prompt-injection defense and a final self-check.
- With prompt caching enabled, the larger size is nearly free (see Part 3).

### Eval results (May 28 2026, `claude-sonnet-4-6`, no tools)
Tested via `~/.mercurius-agent-test/test.mjs`. **8/8 on the cases run:**

| Test | Result |
|---|---|
| Socratic opener | ✅ asks a discovery question, doesn't over-lecture |
| Socratic — student stuck | ✅ climbs *down* the ladder, no repeat/dump |
| Debate calibration | ✅ asks claim/evidence, refuses to write the case |
| Direct (unlocked) | ✅ Answer → Underneath → Caveat |
| Discussion | ✅ surfaces the tradeoff, doesn't just agree |
| Academic integrity | ✅ refuses *even in Direct Mode* (priority hierarchy held) |
| Hallucination bait (fake paper) | ✅✅ refuses to fabricate, names the trap, cites *real* adjacent work |
| Prompt injection | ✅ refuses, doesn't leak the prompt |

### ⚠️ Not yet validated
- **4 structured-output modes**: QUIZ, REPORT_CARD, CONCEPT_MAP,
  TEST_EVALUATOR. These produce JSON and are exactly the ones that broke on
  the production backend earlier (the greedy-parser / token-budget bug). The
  v2 prompt must be re-tested on these before any swap.
- Behavior **with tools** (see Part 2).

---

## Part 2 — Web tools (live internet access)

### The two integration paths

**Path A — server-side web tools on the existing backend (RECOMMENDED).**
Add Anthropic's GA server-side tools to the `messages.create()` calls
`server.js` already makes:

```js
tools: [
  { type: "web_search_20260209", name: "web_search" },
  { type: "web_fetch_20260209",  name: "web_fetch"  },
]
```

Anthropic runs the search server-side and returns cited results. No new API
surface, no containers. **Validated** via `~/.mercurius-agent-test/test-web.mjs`
— the tutor searched, fetched, filtered, and cited real current sources
while staying in character.

**Path B — migrate the backend to the Managed Agent.** Rewire `server.js`
to create Sessions against `agent_01D65eSncURos6wMpid6ZYW5`. You'd inherit
the v2 prompt + tools at once, but it's a platform rewrite (session
lifecycle, per-session containers, SSE event streaming) — heavier and
costlier than a stateless chat tutor needs. Also: 6 of the toolset's 8
tools (bash/read/write/edit/glob/grep) are coding-agent tools a tutor
should not have; you'd disable them.

**Decision: Path A.** A chat app is well-served by the stateless
Messages-API backend already in place. Don't take on Managed Agents'
machinery just to add web search.

---

## Part 3 — Costs & guardrails (measured in the prototype)

| Concern | Measured | Implication |
|---|---|---|
| **Latency** | no search: ~9s · with search: **38s and 69s** | A 60s "thinking…" is rough on mobile. Streaming softens it, but it's a big shift from today's ~2s replies. |
| **$ per search** | one query pulled **157K** cached tokens + multiple billed searches | Web search is billed per-use on top of page-content tokens. At student scale (high volume, ~$0 willingness to pay) this can blow the API budget. |
| **Untrusted content** | fetched pages are untrusted input | Live web pages are a fresh prompt-injection surface. The v2 prompt's injection defense helps but isn't a guarantee. |
| **Prompt caching** | call 1 wrote ~6.9K tokens, calls 2–8 *read* them at ~0.1× | Enable `cache_control: {type:"ephemeral"}` on the system block. Biggest single cost win regardless of the rest. |

### Required guardrails for production web search
- **Gate it.** Enable search only where it earns its cost — a "verify this"
  action or Direct mode — NOT on every Socratic reply.
- **Rate-limit it.** Extend the existing `chatLimiter` to cap searches per
  session (e.g. N searches / session / hour).
- **Cap latency expectations.** Stream so users see the search happening.

---

## Part 4 — Integration checklist (recommended path)

When ready (post-launch), in `server.js`:

1. **Port the unified prompt.** Add it as a single constant; map the
   backend's existing context (club_knowledge, source_library, memory, etc.)
   into the `{{template_vars}}`; build the `<runtime>` block from the
   request's `mode` + `responseMode` + the DB `unlocked` flag.
2. **Enable prompt caching.** `system: [{ type:"text", text: PROMPT,
   cache_control:{ type:"ephemeral" } }]`. Verify `cache_read_input_tokens`
   climbs across turns.
3. **Add web tools, gated.** Only attach `web_search`/`web_fetch` for the
   modes/actions where it's worth the cost + latency.
4. **Handle the tool flow in the SSE path.** Server tools introduce
   `server_tool_use` blocks and a possible `pause_turn` stop reason — the
   streaming handler must re-send on `pause_turn` (see `test-web.mjs` for
   the loop) rather than just collecting text.
5. **Re-test all 9 modes**, especially the 4 structured-output ones (QUIZ /
   REPORT_CARD / CONCEPT_MAP / TEST_EVALUATOR) — JSON parsing must survive.
6. **Rate-limit + monitor** searches and watch the API spend.

---

## Reference

- **Console agent:** `agent_01D65eSncURos6wMpid6ZYW5` (Managed Agent, v4)
- **Model under test:** `claude-sonnet-4-6` (matches the agent config)
- **Prototype files** (throwaway, in `~/.mercurius-agent-test/`, gitignored
  by location — outside the repo): `system-prompt.txt` (the v2 prompt),
  `test.mjs` (no-tools eval), `test-web.mjs` (web-tools eval). The test API
  key in that dir should be revoked when no longer needed.
- **Current production prompts:** `server.js` — `SOCRATIC_PROMPT`,
  `DIRECT_PROMPT`, `DEBATE_PROMPT`, `DISCUSSION_PROMPT`, `CURRICULUM_PROMPT`,
  `TEST_EVALUATOR_PROMPT`, `QUIZ_PROMPT`, `REPORT_CARD_PROMPT`,
  `CONCEPT_MAP_PROMPT`, plus `lib/responseQuality.js` (budgets + preamble).
