# Step 04: network failures (AUD-32, and the iOS half of AUD-30)

Branch `fix/ios-student-2026-10`. Nothing is pushed.

## Commits

- `c1781b3` Name the network, not the server, when a school network blocks Mercurius (AUD-32). It stands alone: I built and tested it on its own (843 package tests).
- `fe29077` Show a daily limit's reset as a local time; offer Retry only where it helps (AUD-30). 871 package tests.
- `07ebc1c` DEBUG: `-LessonReplayNetwork` scenarios for the network-failure screenshots (AUD-30, AUD-32). DEBUG only, with one test.
- `ebec681` Keep a paused or capped server from locking the unit-test answer (AUD-30 follow-up). This was not in the brief; it's a separate commit so it can be dropped. See "Unit test" below.

## The wire (server unchanged)

I read `server.js` and `lib/quotas.js`, then confirmed each shape on this branch's own server in mock mode (details under Tests).

- **`/api/chat`:** every 2xx is `Content-Type: text/event-stream`, both the reply (`res.writeHead(200, …)`, about line 1958) and every refusal.
  - A refusal (`sendRefusal`, about line 1461) is one frame, `{"type":"error","code":…,"error":<copy>,"retryAfterSec":…}`, then `[DONE]`.
  - **The SSE frame carries no `scope`.**
  - The stream's headers go out only after the database awaits and the gate. So "connected, but no headers yet" can be a real server stall.
- **JSON routes:** a refusal is `{error, scope, reply, message, retryAfterSec}` plus a `Retry-After` header. `daily_limit` comes as a 429; `restarting`, `service_disabled`, `spend_cap` and `busy` come as a 503.
- **`retryAfterSec` values:**
  - `daily_limit`: the seconds to UTC midnight (`secondsUntilUtcMidnight`).
  - `busy`: 60. `restarting`: 5.
  - `spend_cap` and `service_disabled`: none.
- **The daily copy** (`DAILY_MESSAGES`): the student's own limits end "Mercurius will be ready again tomorrow." Every network-scoped one names the network: "This network has reached…" and "Too many new sessions from this network today."

## What changed

### AUD-32: name the network

- **`ConnectionPhase` (new, NetworkingKit):** reads how far a request got from `URLSessionTaskMetrics`. It takes the last network-load transaction and returns one of:
  - never connected (no TCP, or for https no TLS end);
  - connected and waiting for headers (a reused connection or a started request counts as connected);
  - receiving the response;
  - unknown, when there is no network transaction (a stub, or metrics that never arrived).
- **`APIClient.mapURLError(_:pathSatisfied:phase:)`,** for a timeout:

  | Phase | Network path | Result |
  |---|---|---|
  | Never connected | Working | `.unreachableOnThisNetwork` |
  | Never connected | None | `.offline` |
  | Never connected | Unknown | `.timeout` |
  | Connected, no headers | Any | `.timeout` (it can be a server stall) |
  | After the headers | Any | `.connectionLost` |
  | Unknown | Any | `.timeout`, as before |

  Every other code maps as before.
- **JSON path (`perform`):** it now uses `data(for:delegate:)` with a small metrics recorder. A 2xx that is HTML is now `.unreachableOnThisNetwork`: either its type is `text/html` or `application/xhtml+xml`, or its body starts with `<` after whitespace or a byte-order mark. That's a filter's block page, a captive portal, or the end of a filter's redirect. Before, it was `.decoding`, which wasn't retryable and locked the unit-test answer.
- **Stream path (`SSEDataDelegate`):**
  - A 2xx that isn't `text/event-stream` is cancelled at the headers and ends as `.unreachableOnThisNetwork`. Before, it ended as "The server closed the connection without a response."
  - A timeout after the headers is `.connectionLost`.
  - Metrics come from the delegate.
  - The network path is now injected, so tests don't depend on the host.
- **Copy:** "This network may be blocking Mercurius. School Wi-Fi often does. Try cellular data or a different Wi-Fi." It stays retryable. It replaces "Can't reach Mercurius on this network…", which already covered DNS/TLS/RST and a bare 401/403.

### AUD-30, iOS half: reset time and Retry

- **`ServerRefusal` (new, NetworkingKit):** one type turns both wire shapes into copy and a Retry rule. `APIError.serverRefusal` and `ChatStreamEvent.serverRefusal` produce it.
- **A `daily_limit` with a usable wait (above 0 and up to 26 h):**
  - The sentences that say "tomorrow" are dropped.
  - A local clock time is added: "Try again after 8:00 PM.", or "Try again tomorrow after 9:00 AM.", or "Try again tomorrow." for a reset at local midnight.
  - The time is the wait minus 5 s, rounded up to the minute, so it is never shown before the reset.
  - With no usable wait, the server's copy stands.
- **The network's allowance** (`scope: "ip"`: new sessions, or the network's dollar or image cap):
  - It reads "…Switch to cellular data and try again, or come back after 8:00 PM."
  - It **keeps Retry**, because another network gets past it.
  - The JSON body says `scope`. The SSE frame doesn't, so then the copy decides: it's network-scoped if it mentions "network", "wi-fi" or "wifi". A contract test reads `lib/quotas.js` and checks this against every `dailyLimit('scope', 'reason')` call.
- **Retry:**
  - None for the student's own daily limit, the spend cap, or the kill switch (`service_disabled`).
  - Kept for `busy`, `restarting` and any unknown refusal code.
  - The composer still sends a new turn after a no-Retry refusal (tested).
- **API changes:**
  - `APIError.quotaExceeded` and `ChatStreamEvent.refusal` gained a defaulted `scope`.
  - `ChatViewModel` reads the time on an injectable `clock: LocalClock`.
  - `APIError.userFacingMessage` keeps its signature. `userFacingMessage(clock:)` is new.

### Unit test (`ebec681`)

The unit test has no Retry button. A non-retryable refusal instead locks the submitted answer until it's edited (existing `refusedAnswer`). Without this commit, the kill switch and the spend cap would now lock the answer under "please try again soon". `UnitDefenseGrading` keeps both unlocked, as before this step. A student's own daily limit still locks it, as before. A network-scoped one no longer does.

### DEBUG harness (`07ebc1c`)

`-LessonPreview -LessonReplay -LessonSkipIntro -LessonReplayNetwork <scenario>` sends the lesson opener through the real `APIClient` and `ChatViewModel`. A local `URLProtocol` answers it, so no network call is made.

The scenarios are `block-page`, `daily-limit`, `new-sessions`, `paused`, `spend-cap` and `busy`:
- `block-page` serves a 200 `text/html` page (the audit's filter stand-in).
- The others serve `sendRefusal`'s exact frames, with today's wait to UTC midnight.

## Tests

- **`swift test`:** 872 tests in 129 suites pass. This was a **clean** build with `--parallel`, as CI runs it. Step 03 ended at 812, so this step adds 60: 31 in `c1781b3`, 28 in `fe29077` and 1 in `07ebc1c`. `ebec681` changes one test.
- **New suites:**
  - `ConnectionPhaseTests`: the timeline to phase, the phase mapping, and the intercepted-page check.
  - `ServerRefusalTests`:
    - the reset time in 7 time zones, including the audit's capture (21:10:57Z + 10143 s gives 7:00 PM Chicago and 8:00 PM New York), rounding, unusable waits, a German locale;
    - network scope, Retry, verbatim copy and "tomorrow" stripping;
    - the `lib/quotas.js` contract, which reads the server's real copy.
  - `NetworkFailureEndToEndTests` (StubURLProtocol, inside the serialized end-to-end suite):
    - a 200 text/html page on a JSON route, the grader and the stream;
    - an untyped HTML page, a wrong 2xx type on the stream, and a charset parameter that still streams;
    - a 429 `daily_limit` with `retryAfterSec`, for the student and for the network;
    - production's SSE refusal frames;
    - a 503 `service_disabled` (JSON and SSE);
    - a timeout before the first byte, a drop mid-stream, and a timeout mid-stream.
  - `LoopbackNetworkTests`: real sockets on 127.0.0.1, so URLSession's own metrics decide. About 1 s each, run in parallel.
    - SYNs dropped (a full accept queue): the network, or offline with no path, or a timeout with the path unknown.
    - A server that accepts and never answers: a timeout.
    - A swallowed TLS hello: the network.
    - Headers, then silence: the reply so far, then a dropped connection.
  - ChatViewModel tests: refusal copy and Retry for each code, the clock time, and sending after a no-Retry refusal.
  - `UnitDefenseGrading` tests: a block page doesn't lock the answer; the retry rules per refusal.
  - `NetworkScenarioPreviewTests`: each DEBUG scenario ends in the failure its screenshot shows.
- **`xcodebuild test` with CI's flags** on Audit 16PM, at `07ebc1c`: **TEST SUCCEEDED**. All 21 UI tests passed on the first try. The flags skip the snapshots, perf tests and App Store screenshots, with retries on.
- **`xcodegen generate` + `xcodebuild build`** for the simulator at `ebec681`: **BUILD SUCCEEDED**.
- **The wire, against this branch's `server.js`:** I ran it with `ANTHROPIC_MOCK=1`, with no API key and no production traffic, on four local servers. I checked with `curl`, and with a probe compiled from the real NetworkingKit sources:

  | Server | `/api/chat` (stream) | `/api/quiz` (JSON) |
  |---|---|---|
  | Default | 200 `text/event-stream`; 18 deltas and the reply arrived | 400 "Have a longer conversation first." |
  | `SESSION_DAILY_CHAT_TURNS=0` | Frame with no scope: "…Try again tomorrow after 7:00 PM.", no Retry | 429 with `scope:"session"`: the same copy, no Retry |
  | `IP_DAILY_NEW_SESSIONS=0` | "Too many new sessions from this network today. Switch to cellular data and try again, or come back tomorrow after 7:00 PM.", with Retry | 429 with `scope:"ip"`: the same copy, with Retry |
  | `CLAUDE_DISABLED=1` | "Mercurius is temporarily paused — please try again soon.", no Retry | 503: the same, no Retry |

  It was 23:47 CDT, so the 7:00 PM reset (00:00Z) was the next evening.
- **The audit's own filter stand-in** (`classroom-reliability/nkprobe/filter.js`), through the same probe:
  - `html200` and `redirect`, the audit's two failures, now give the network copy with Retry on both paths.
  - `html403` gives the same, as before.
  - `empty200` gives the network copy on the stream, but still "We got an unexpected response" on a JSON route (see risks).
- **Metrics timing:** I checked on macOS 26 that URLSession hands over the metrics before the task completes and before `data(for:delegate:)` throws. If an OS did it later, the phase would be unknown and the old `.timeout` would stand.
- **Snapshots:** not run, and nothing recorded. The only failed-bubble snapshot uses a fixed reason string ("Network error. Try again."), and no snapshotted view changed. I expect no drift from this step, but that isn't verified.
- **Stale build:** once, an incremental `swift test` failed to link: `SettingsFeatureTests` still referenced the old `mapURLError` symbol. Deleting the test build products fixed it. It's the same stale-build trap steps 01 and 02 hit.

## Screenshots (`docs/ios-batch/shots/`)

All are from `-LessonReplayNetwork`, through the real client. The SE3 sim is in dark mode and the 16PM in light.
- **Simulator time zone:** the sims run in the Mac's zone, America/Chicago, and it was about 23:45 CDT. So the plain daily-limit shot correctly says "tomorrow after 7:00 PM".
- **"-newyork" shots:** these launch with `SIMCTL_CHILD_TZ=America/New_York`. It was already past midnight there, so they show the common same-evening case, "after 8:00 PM".

| File | Shows |
|---|---|
| `04-blockpage-se3-L.png`, `04-blockpage-16pm-L.png` | Block page: the network copy, with Retry |
| `04-blockpage-se3-AX5.png`, `04-blockpage-16pm-AX5.png` | The same at AX5 |
| `04-dailylimit-se3-L-newyork.png` | "You've used today's lesson turns. Try again after 8:00 PM.", no Retry |
| `04-dailylimit-se3-L-chicago.png` | "…Try again tomorrow after 7:00 PM.", no Retry |
| `04-newsessions-se3-L-newyork.png`, `04-newsessions-16pm-L-newyork.png` | Cellular and the time, with Retry |
| `04-newsessions-se3-xxxL-newyork.png`, `04-newsessions-se3-AX5-newyork.png` | The same at xxxL and AX5. At AX5 on the SE the copy scrolls; the end and Retry are in view. |
| `04-paused-se3-L.png` | The kill switch: the server's copy, no Retry |
| `04-spendcap-se3-L.png` | The spend cap: the server's copy (still "tomorrow"; it sends no wait), no Retry |
| `04-busy-se3-L.png` | Busy: the server's copy, with Retry |

Both sims are back at text size `large`.

## Skipped or not verified

- AUD-34, snapshot recording and `ConsentGate.currentVersion` (still 1), as instructed.
- **"Still connecting…" after about 10 s:** the audit's optional item, not done.
- **A silent drop still waits out the full timeout** (60 s chat, 30 s JSON) before it's named. Only the classification and copy changed. A shorter connect timeout would need care on slow cellular.
- **Not tested on real networks:** no real school network, captive portal, MDM TLS interception or Railway edge. Only loopback sockets, stubs, a local mock server and the audit's stand-ins.
- **iOS 17:** not run (the sims are iOS 26).
- **VoiceOver:** not re-checked. The failed bubble's copy changed, not its structure.

## Open risks and founder decisions

1. **No Retry for the kill switch and the spend cap.** This follows the brief, and it's a product call.
   - In chat the composer still sends. A lesson whose opener was refused needs the student to type to start it.
   - To revert, change `ServerRefusal.isRetryable`.
   - The unit test keeps Submit enabled for both (`ebec681`).
2. **The Content-Type check on the stream is strict.** Any 2xx from `/api/chat` that isn't `text/event-stream` now reads as "This network may be blocking Mercurius".
   - Production sets it on every 2xx path today. I checked that in `server.js` and on a local server.
   - A CDN or proxy that rewrote it would fail every turn. Remember this if the hosting changes.
3. **Network scope comes from the copy on the stream.** The server batch should add `scope` to `sendRefusal`'s SSE frame; the client already reads it. Until then, the contract test fails if `lib/quotas.js` copy stops naming the network.
4. **The server half of AUD-30 is still open.**
   - The quotas and the spend cap still roll at UTC midnight.
   - `spend_cap` sends no `retryAfterSec`, so its "tomorrow" stays.
   - The client rewrites only `daily_limit` copy.
5. **An empty 2xx `text/plain`** (`empty200`) on a JSON route still shows "We got an unexpected response" with no Retry. Only HTML is classified, as the audit specified.
6. **The reset time is read on the device clock.** A clock that's minutes off shifts the time shown by the same amount.
7. **The Settings delete alert** still says "Check your connection" for a blocked network. This is unchanged, and it already offers "reset this device only".
8. **My probe listeners may have caught other servers' traffic.** These were local processes on this Mac, outside the repo.
   - **What I ran:** while I measured URLSession's metrics, from 23:22 to 23:53 CDT, I held 127.0.0.1 ports 3301–3304 (IPv4 only). One listener was silent, one sent headers then stalled, and one had a full accept queue.
   - **What was already there:** three `node --env-file=…/mercurius-chatbot/.env server.js` processes I didn't start (PIDs 76394, 76396 and 76835, started 20:03–20:10) listen on `*:3301–3303` over IPv6.
   - **The effect:** in that window, a client that dialled `127.0.0.1:3301–3303` reached my listeners, not those servers. A client that dialled `localhost` or `::1` was unaffected. If anything failed or hung against those ports in that window, rerun it. My listeners are stopped, and those three servers are still running, untouched.
   - **The `pkill`:** I stopped my own four mock servers (ports 3291–3294) with `pkill -f "node server.js"`. That pattern doesn't match the three servers above, because their command lines have `--env-file` in between. It would only have stopped some other plain `node server.js`, and I didn't check for one first.
