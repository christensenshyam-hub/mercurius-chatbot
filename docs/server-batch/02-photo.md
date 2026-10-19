# Step 02: photo re-attach (AUD-10)

Branch `fix/server-2026-10`, on top of step 01. No prompt text changed: `CURRICULUM_PROMPT`, the source library and `SAFETY_CORE` are untouched, and the static system block is byte-identical (tested). The `server.js` edits are in the `/api/chat` handler plus one helper above it.

## Commits

| Commit | What |
|---|---|
| `dbefc21` | **AUD-10.** A photo is linked to the user turn it came with once that turn is answered, and re-attached to that turn on the session's next 6 user turns while it is under 24 h old. |
| `5ccd301` | **AUD-10 follow-up.** Two chats that each open with a photo-only turn keep their own photo (the link also records the start of the reply). |
| (last) | These notes, `scripts/photo-reattach-usage.mjs`, its worksheet fixture and the two real-API result files. |

## What every shipped build sends

Read from source at `2e212dc` (2.0.0, build 11), tag `ios/v2.3.0-16` (build 16) and `720dbac` (main). Build 16's `ChatViewModel` and `NetworkingKit` are identical to main's. PR #43 doesn't change how photos are sent.

- **The photo turn.** `runSend` uploads the photo, then streams with `imageId`, on that ONE request only. The turn's content is the typed text, or `"[Shared an image]"` when there is no text.
- **Every later turn** sends the thread as text with no `imageId`. That includes `explainMore()`, which appends a wire-only "Explain more…" user turn.
- **Lessons** re-send the `[CURRICULUM: …]` opener first, and re-tag the LAST user turn with the tag. On later turns, the same message arrives untagged.
- **Retry of a photo turn** re-uploads the photo under a new `imageId`, for the same turn.
- **Clamping.** 2.0.0 sends turns unclamped (the server cuts each user turn to 2,000). Build 16 clamps the latest turn to 2,000 and replayed turns to 10,000. Both cap the thread at 40 messages / 24,000 bytes, dropping the oldest first.
- **Interrupted reply.** PR #43 keeps an interrupted reply in the thread when the student answers it. Older builds drop the failed bubble, so two user turns end up in a row.

So the fix has to work from the thread text alone. That's why the image row records which turn it belongs to.

## What changed

### `lib/photoReattach.js` (new, pure)

**Keys.** Each key is computed on the thread exactly as the server replays it on every turn: `normalizeReplayedHistory` (lesson re-tag stripped), the server's 2,000-char cut, and the same empty-turn filter as the request. The text is canonicalised: leading whitespace dropped, cut to 1,500 UTF-16 units, trailing whitespace dropped. The cut is there because on iOS 2.0.0, a long lesson turn keeps about 30 fewer characters on the photo turn (where the re-tag counts toward the 2,000) than on its replays. There is a test for this.

| Key | Hash of | Used for |
|---|---|---|
| `turnKey` | the turn's text | fallback, only when the turn is now FIRST in the thread (the client's byte cap dropped the message before it) |
| `anchorKey` | the text plus the message before it (role and text) | the main match. Two `"[Shared an image]"` turns differ here. A Retry re-upload shares it, so only one image per turn is used. |
| `replyKey` | the first 200 chars of the reply the photo turn got | tie-break only, among equally good matches (commit `5ccd301`) |

The `replyKey` case: two chats that each open with a photo-only turn share an anchor (nothing before, same text). Without it, going back to the older chat showed the newer chat's photo.

**`plan()`.** It walks the thread's user turns from newest to oldest:

- A turn is eligible while at most `maxTurns` user turns follow it, the new one included. So the photo turn plus follow-ups 1 to 6.
- Each turn gets at most one image, and each image goes to at most one turn.
- At most 3 images and 10 MB raw per request. That keeps a request with the new turn's own 8 MB photo well under the API's 32 MB limit.
- The new turn is never a target, and its own `imageId` is excluded.

**`apply()`.** It rebuilds a matched turn as `[image, text]` with the existing `buildUserContent`, and never mutates its input.

### Linking (`server.js`, `db.js`, `lib/imageStore.js`)

**When a photo is linked.** Only once the model has answered the photo turn:

- the stream ended normally and the reply was not a refusal; or
- the stream was cut off (Stop, dropped connection, watchdog) after the model had streamed any text.

So a photo the API rejected (a 400 before any text) is never re-attached. Neither is one that drew a refusal, including a refusal after partial text. Otherwise six follow-up turns would fail, or keep refusing. The `replyKey` is taken from the final reply after `[LESSON_COMPLETE]` is stripped, which is the text iOS stores. On a cut-off stream it comes from the streamed text.

**Schema.** `images` gains `turn_key`, `turn_anchor` and `turn_reply`: hashes only, never text. They are added by boot-time `ALTER … ADD COLUMN IF NOT EXISTS` (Postgres) or a `PRAGMA` check (SQLite), the same pattern as `messages.kind` and the `reports` columns. No migration file is needed. Erasure and the retention purge delete them with the row.

**`db.linkImageTurn`.** It is an `UPDATE … WHERE id = ? AND session_id = ?`. So it only links the session's own image, and a link that lands after an erasure writes nothing.

**`db.linkedImages`.** Metadata only, never the bytes: the session's linked rows since a cutoff, newest first, served by the existing `idx_images_session` index.

**`imageStore`.** It adds:

- `link`
- `linkedForSession`
- `reattachMaxAgeMs()`: the store's retention, capped at 24 h, and 24 h when retention is `off`.

### Re-attaching (`server.js`)

**Per request.**

1. The linked-image lookup starts alongside the session reads, only when the thread has an earlier user turn.
2. After the history is built, `reattachPhotos()` plans the matches.
3. It fetches the matched images through `imageStore.get`, which re-checks retention and the owning session.
4. It rebuilds those turns.

Any failure leaves the history text-only, as before.

**Order and caching.** This all happens before the 20/40-message slice and before `withHistoryBreakpoint`. The photo is always in a historical turn, so it sits in the cached prefix.

**`lib/systemBlocks.withHistoryBreakpoint`.** It now also marks an `[image, text]` turn by putting `cache_control` on its LAST (text) block. That matters when the photo turn is itself the second-to-last message (a failed reply, then a new turn). Before this change that case got no breakpoint.

**Ops.**

- `PHOTO_REATTACH_TURNS` (default 6, `0`–`20`; `0` turns re-attaching off but keeps linking). It is documented in `docs/DEPLOY.md` and `.env.example`.
- The metric `photo_reattached_images_total{kind}`.
- An info log with the count, and no content.

## Tests

`npm test`: **1076 pass, 0 fail.** Step 01 ended at 1031, so this step adds 45. `node scripts/pg-smoke.mjs` (SQLite) passes 39/39, including the new `C3b` step and the column checks after the July-schema upgrade. CI runs the same smoke on Postgres 16.

**`tests/photoReattach.test.js` (24, pure):**

- canonical text and `replyKey`;
- the same keys for a photo turn and its replays, through the lesson re-tag and the 2.0.0 cut difference;
- two photo-only turns: same `turnKey`, different anchors;
- `plan` cases:
  - the right turn, and never the new turn;
  - another position doesn't match;
  - two photo-only turns, each with its own photo;
  - a Retry uses the newest upload only;
  - two chats opening with a photo, picked by reply;
  - follow-ups 1–6 yes and the 7th no, consecutive user turns included;
  - `maxTurns` 0;
  - the first-in-thread fallback, and only there;
  - exclusion;
  - the 3-image and 10 MB caps;
  - malformed links;
- `apply` doesn't mutate, and skips bad targets;
- `withHistoryBreakpoint` on an `[image, text]` turn.

**`tests/photoReattachRoute.test.js` (15).** These run against the real server and the mock, and read back what the model was sent via `MOCK_CAPTURE_FILE`.

- **Lands on the right turn:**
  - build 16 shape (blocks_v1, photo only): exactly one image, on the photo turn, with the uploaded bytes, and `turn_reply` equal to `replyKey` of the reply iOS keeps;
  - 2.0.0 shape (no capabilities, text plus photo), then Explain more, then a typed turn;
  - a lesson with the iOS re-tag;
  - two photos plus a cut-off first try and its Retry re-upload: A and the retry's B are shown, the cut-off upload never is;
  - two chats each opening with a photo: going back to the older chat shows its own photo;
  - the JSON path.
- **Never crosses sessions:** another session replaying the owner's exact thread gets no image. Presenting the owner's `imageId` neither shows it nor changes the owner's link. The owner's own next turn does see it.
- **Stops:**
  - after 6 follow-ups (`[1,1,1,1,1,1,0]`);
  - by age: shown at 24 h minus 1 min, gone at 24 h plus 1 min (`created_at` backdated in the SQLite file);
  - `PHOTO_REATTACH_TURNS=0`: not shown, still linked.
- **Not linked:** a refused photo turn, a refusal after partial text, and an upstream error before any text (`MOCK_SCENARIO=error`).
- **Cached prefix:** `system` is deep-equal with and without a re-attached photo, the static block keeps its breakpoint, and there are 4 breakpoints at most. The photo comes before the history breakpoint. In the mock's usage, follow-up 1 writes the photo into the cache, follow-up 2 reads it back, and its uncached input is under the image's size.
- **Erasure:** the photo is shown before the `DELETE /api/session/:id`. After it, the receipt shows `images: 1`, `GET /api/images/:id` is 404, the row is gone, and the same id and thread get no photo.

**`tests/photoReattachDb.test.js` (6):**

- `linkImageTurn` is session-scoped, needs both keys, and replaces earlier keys;
- `linkedImages` returns only that session's linked rows, newest first, with no bytes and typed numbers, and respects `sinceMs` and `limit`;
- erasure takes the photos, and a late link writes nothing;
- the re-attach window follows retention, capped at 24 h;
- the boot migration of a pre-column `images` table: the columns appear exactly once after two `initSchema` runs, and the old row reads back unlinked and can then be linked.

**Mutation checks (not committed):**

- With re-attaching off, 10 of the 13 route tests that existed then fail. The 3 that pass only assert absence: refusal, kill switch, erasure.
- With the reply tie-break removed, the two-chats test fails.

## Measurements (real API)

**Setup.**

- `scripts/photo-reattach-usage.mjs` on port 3371, against a server started with the brief's exact command (`USE_UNIFIED_PROMPT=1`, SQLite in `/private/tmp`).
- The script warms the system-prompt cache, then drives two sessions like build 16 (blocks_v1, concise). The student turns are the audit's x01 photo repro plus one more:
  - "i got x = 16 for number 7, is that right?" (with the photo);
  - "i plugged it in tho. 3(16-4)+5 = 41 and 2(16)+9 = 41";
  - "ok and what does number 8 say again";
  - "can you read me number 7 exactly as it's written on the sheet?"
- Session B replays A's exact wire threads with nothing to re-attach. So A − B in prompt tokens (input + cache read + cache write) is the image on that turn.

The recorded files are from commit `5ccd301`. Earlier runs on `dbefc21` gave the same token deltas.

**Photos measured:**

- **The audit's worksheet:** 900×520 PNG (`scripts/fixtures/math-hw.png`).
- **The same sheet at iOS's upload size:** 2048×1183 JPEG (`sips -Z 2048`, quality 80). That is the most `JPEGImagePreparer` sends, and the API scales it down to about 1.15 MP.

| Photo | Image tokens, every turn | Follow-up 1 (cache write, 1.25×) | Each later follow-up (cache read, 0.1×) | 6 follow-ups, worst case |
|---|---|---|---|---|
| 900×520 PNG | **631** | +$0.0024 | +$0.00019 | ≈ $0.0033 |
| 2048×1183 JPEG | **1,564** | +$0.0059 | +$0.00047 | ≈ $0.0082 |

- **Constant on every follow-up.** The image token count was the same on all three follow-ups, so the photo was re-attached on each.
- **Cached.** It went into the cache once: follow-up 1's cache write grew by the image. Then it was read back: follow-up 2's cache read grew by the image, and its uncached input stayed at 16–38 tokens.
- **Cache noise in the JPEG run.** In the recorded run, follow-up 1 shows a cache read and no write. Its prefix had most likely been cached by the identical run on `dbefc21` four minutes earlier: same photo, same turn, and the same first reply. That run's follow-up 1 wrote 1,673 tokens, and this one read exactly that. The token delta doesn't depend on cache state.
- **Without caching.** When the history breakpoint is skipped (a thread over 20 KB, or at the window), the photo is billed uncached: 1,564 tokens is about $0.0047 per follow-up.
- **Context.** The photo turn itself already cost +$0.0019 / +$0.0047 for the image before this change.

**Spend.** About $0.14 in all: two runs on `dbefc21` ($0.034 + $0.041) and the recorded two on `5ccd301` ($0.034 + $0.034). Server killed after each, port 3371 confirmed free.

**What the student sees now.** Results are in `docs/evals/photo-reattach-usage-*.json`.

- **Before (audit transcript x01, turn 3):** "I don't have your worksheet in front of me".
- **Now:**
  - turn 3: "I can see it in the image…";
  - turn 4 reads problem 7 back word for word, "3(x - 4) + 5 = 2x + 9", in all four runs.

## Skipped, and why

- **The prompt stopgap** ("restate the exact problem in one line"; "if you can no longer see a photo, say so"). It is prompt text, so it belongs to PR #44's lane. The brief keeps my `server.js` edits out of the prompt constants.
- **iOS follow-up** (explainMore carries the `imageId`). Not needed: the server re-attaches for every build. It would also re-send an image the server already shows.
- **`eval-pacing`.** Not re-run: no prompt changed, and no eval scenario has a photo. A thread with no linked photo takes the old path; only the lookup runs.
- **Simulator / device.** Not run. The client flows are reproduced from the Swift source at each build, and checked at the request level.

## Decisions for review

1. **Linked on an answer, not on upload.** A photo the API rejected, or that drew a refusal, would otherwise break or keep refusing the next six turns. Cost: a stream cut off before ANY text arrives leaves the photo unlinked, so a student who then types on instead of tapping Retry loses it, as today.
2. **Three keys, not "a hash of that turn's text".** Text alone can't tell two `"[Shared an image]"` turns apart, or two chats that open with one. The anchor and the reply tie-break fix both, and a Retry re-upload folds into its turn.
3. **The key cut at 1,500 chars.** It makes the key immune to the 2.0.0 lesson re-tag cut. Two different turns sharing their first 1,500 characters and the same previous message would collide. I judged that negligible.
4. **"About 6 turns"** means the photo turn plus 6 follow-up user turns. "Explain more" and turns with no reply in between each count as one.
5. **Caps.** 3 photos and 10 MB per request, so a re-attach can never push a request toward the API's 32 MB limit.
6. **Window.** The store's retention capped at 24 h. If `IMAGE_RETENTION_HOURS` is raised, re-attaching still stops at 24 h.

## Open risks

- **Privacy copy.**
  - `marketing/privacy.html` says a photo "takes the same path as a message: to our server, then to Anthropic to generate the reply", and is deleted after 24 h. Both still hold.
  - But a photo now goes to Anthropic again with the next few messages, as earlier messages already do.
  - The founder may want "and with your next few messages" added (batch 2's lane). I didn't edit it.
- **The cache drop at follow-up 7.** When re-attaching stops, the history after the photo turn misses the cache once and is re-written (1.25× on that history, once).
- **Postgres.** The boot `ALTER TABLE images …` runs on every boot, as the existing ALTERs do. It takes a brief exclusive lock, and is a no-op once the columns exist. It was only run on SQLite here. CI's pg-smoke covers Postgres 16.
- **Photos from before the deploy** aren't linked, so they aren't re-attached. Only photos answered after the deploy are.
- **A future client that rewrites a photo turn's text** between turns (trims it, re-caps it differently) would miss the link. That falls back silently to today's text-only behaviour.
- **Model behaviour, now that it sees the photo** (prompt territory; observed in these runs, not caused by this step):
  - The tutor still sometimes insists x = 16 is wrong after the student's correct check (audit CQ-01).
  - On "what does number 8 say again" it declines to read the problem aloud ("reading it yourself is part of the work").
  - PR #44 is the place for both.
- **Rebase onto PR #44.**
  - My `server.js` hunks are in the `/api/chat` handler and one helper next to `MAX_USER_TURN_CHARS`, away from the prompt constants. PR #44's own `/api/chat` hunk is the `maxTokens` safety floor, further down.
  - PR #44 also edits `lib/systemBlocks.js`: it adds `withAppFacts` and its header docs right after the `HISTORY_CACHE_MAX_BYTES` line. My edits there are a few lines above it, in the `withHistoryBreakpoint` docs and body. Expect at most a trivial header-comment conflict.
  - PR #44 doesn't touch `db.js` or `lib/imageStore.js`.
  - Its two new `chat-photo-*` eval scenarios are single-turn, so this change doesn't affect them. A follow-up turn there would now see the photo.
