# Standby Gamification (quiet progress) — Phase 1

A **disabled-by-default**, **server-authoritative** engagement layer. With the
flags off (the default, and production), it is completely inert: no tables, no
network calls, no UI, and every existing flow is byte-identical.

## The one rule: LEVEL ≠ RANK

Two **separate** tracks that must never be coupled:

| | **Level** (this system) | **Rank** (Phase 2, separate) |
|---|---|---|
| Driven by | XP from engagement / reasoning moves | Demonstrated AI-literacy **competencies** only |
| Purpose | Encouragement (quiet progress UI) | Credentialed mastery ladder |
| Implies mastery? | **No** | Yes |
| Ladder | numeric Level 1…50 | copper → bronze → silver → gold → platinum → diamond → olympian → mercurial |

Phase 1 ships Rank as a **placeholder column only** (`progression.rank`, defaults
`'copper'`). **Nothing** computes rank from XP / Level / streak / usage. This is
enforced in the data model, the service (`updateProgression` omits `rank`),
comments, and tests (`gamification.test.js` asserts rank stays `copper` through
the full stack; the Swift suite + the node fake-db test assert the service never
writes rank).

## Two gates (both off by default)

1. **Server** — `GAMIFICATION_ENABLED=1` (env). Off → `/api/progression/*`
   returns `{ "enabled": false }`, no tables are created.
2. **iOS client** — `GamificationFlag.clientEnabled` (compile-time, `false`).
   Off → no progression network calls, no progress UI.

BOTH must be on for anything to appear. To develop locally, set both.

## What earns XP — and what never does

Earns XP (see `reasons.js`): clarifying/probing questions, revising a position
after a flaw is surfaced, self-correction, expressing calibrated uncertainty,
completing a reflection, completing a module, returning daily.

**Never** earns XP (no reason code exists for them): correct answers, raw message
volume, session length, passive time, login frequency, filler/spam. Correctness
is deliberately absent.

Anti-grind (all server-side, in `xp.js`): append-only ledger with a unique index
for **idempotency**, **per-day** + optional **per-session** caps, and
**diminishing returns** on repeated low-effort moves. The client may only
*request* an evaluation; the server decides.

## Module map

| File | Responsibility |
|---|---|
| `reasons.js` | The 7-reason registry + per-reason XP/caps/diminishing config. |
| `level.js` | Deterministic Level curve. Never references rank. |
| `xp.js` | `awardXp` — idempotency, caps, diminishing returns, level-up. Writes XP/Level only. |
| `heuristics.js` | Pure reasoning-move detection (clarify / revise / self-correct / uncertainty). |
| `../../migrations/001_gamification.sql` | Canonical production migration — **written, never auto-applied**. |

Persistence lives in `db.js` (`ensureGamificationSchema`, `ensureProgression`,
`recordXpEvent`, `countXpEvents`, `sumXp`, …), created only when the flag is on.

## API

- `GET  /api/progression/me?sessionId=…` → `{ enabled, xp, level, levelProgress, xpToNext, streak, longestStreak, recentXpEvents }` (or `{ enabled: false }`). `recentXpEvents` is the factual credit feed the UI renders — no character, no voice.
- `POST /api/progression/event` `{ sessionId, reason, sourceType?, sourceId?, sessionRef?, metadata? }` → new state + the awarded `reason` (the client formats a factual acknowledgment from `reason` + `awarded`, e.g. "Revised your position · +14 XP"). Idempotent structural events require a stable `sourceId`.

Metrics: `gamification_events_total{reason,status}`, `gamification_xp_awarded_total{reason}` (zero unless the flag is on).

## Enabling locally

```bash
# server
GAMIFICATION_ENABLED=1 npm start
```
```swift
// ios/Packages/NetworkingKit/Sources/GamificationFlag.swift
public static let clientEnabled = true
```

## How XP earns (when enabled)

The iOS client *requests* evaluations; the server decides, caps, and applies
diminishing returns:

- **Structural:** completing a lesson → `MODULE_COMPLETED`; returning daily →
  `DAILY_RETURN`. (Wired in `AppShellView`.)
- **Reasoning moves in chat:** detected client-side by `ReasoningMoveDetector`
  (the Swift mirror of `heuristics.js`) on the user's turn — clarify / revise /
  self-correct / uncertainty — then a gated, fire-and-forget `recordEvent`. The
  chat streaming path is untouched.

## Not in Phase 1

Rank advancement, competency assessment, any rank↔XP coupling, and optional
*server-side* reasoning-move detection (the client owns detection for now;
`heuristics.js` stays a pure reference module). Deferred / separately gated.
