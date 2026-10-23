# Step 01: crisis support (AUD-02)

Branch `fix/ios-student-2026-10`, based on `main` 720dbac.

## Commits

- `c84abf0` Show crisis support, not a failed grade, on a unit-test crisis answer (AUD-02). This is the first commit, and a TestFlight build can be cut from it on its own.
- `ccadc0c` Show crisis support on the chat quiz's crisis answer too (AUD-02 follow-up). This is a separate commit, so it can be dropped without touching the first one.

## The wire (read from server.js, unchanged)

- `POST /api/unit-test/grade` answers a crisis with **200** `{"grade":"—","pass":false,"feedback":CRISIS_COPY,"crisis":true}` (server.js `CRISIS_GRADE`, about line 2330). It sends this both for the deterministic `crisisSignal(answer)` floor and for the grader's own rule-1 hand-off (`isCrisisReply`). The route never returns a crisis on a non-2xx.
- The JSON helper routes (`/api/quiz`, `/api/report-card`, `/api/concept-map`, `/api/factcheck`, `/api/analyze`) answer a crisis with **503** `{"error":"crisis","message":CRISIS_COPY,"crisis":true}` (`CRISIS_RESULT`, about line 1146). Of these, iOS calls only `/api/quiz`. `generateReportCard` exists in NetworkingKit, but no view calls it.
- Chat (`/api/chat`, free chat and lessons) sends a crisis reply as ordinary SSE text deltas: the model's rule-1 reply, or `REFUSAL_COPY` on a refusal (PR #41). It never sends a crisis flag, a crisis SSE error frame or a crisis non-2xx.

## What changed

**NetworkingKit**
- `UnitDefenseResult.crisis: Bool` is decoded with a new lenient `LenientFlag` (JSON `true` or `"true"` → true; absent, null or anything else → false).
  - When `crisis` is set, `pass` is forced to false, and a missing grade or feedback can't fail the decode (feedback falls back to `message`).
  - Without the flag, `grade`, `pass` and `feedback` are still required, as before.
- New `APIError.crisisSupport(message:)` (added as the **last** case, see the risks below). `APIClient.validate` checks for it before the status switch: any non-2xx body with `crisis:true` or `error/code == "crisis"` maps to it. It is never retryable, and `userFacingMessage` is the server's copy. If a crisis body arrives without copy, the fallback lists 988, 741741 and 911.
  - `ErrorBody` gained `@LenientFlag crisis` and an `isCrisis` property.

**AppFeature**
- `UnitDefenseGrading` (new) holds the mapping that used to sit inline in `AppShellView`:
  - a 200 with `crisis` → `DefenseResult.crisisSupport`;
  - `APIError.crisisSupport` → `DefenseGradingError.crisis`;
  - an HTTP 404 → `.unavailable`;
  - any other `APIError` → `.refused(copy, retryable)`;
  - pass is still derived from the letter grade.
- `AppShellView.unitTestCover` now calls `UnitDefenseGrading.grade { apiClient.gradeUnitDefense(…) }`.
- DEBUG `-UnitTestCrisisPreview` (`UnitTestCrisisPreviewHost` in RootView) drives Unit 1's test through the **real** view model: it answers every multiple-choice question correctly, then submits a written answer. The grade comes from the server's exact crisis payload, run through the real decode and mapping. Adding `-CrisisVia503` sends the 503 helper body through `APIClient.validate` instead. No network call is made.
- DEBUG `-QuizCrisisPreview` shows the quiz sheet with the 503 crisis body through `APIClient.validate`.

**CurriculumFeature**
- `UnitTestViewModel.Phase.support`, plus `DefenseResult.isCrisis` and `DefenseResult.crisisSupport`, and `DefenseGradingError.crisis`. Entering support clears any grade or error.
  - `overallPassed` is never true in support, so `onMastered` can't fire.
  - The new `offersRetake` is true only on the result screen after a graded fail.
  - `retake()` does nothing in support.
- `UnitTestView`:
  - shows `CrisisSupportView(closeTitle: "Back to your path", onClose: onExit)`;
  - hides the "UNIT n · UNIT TEST" eyebrow and the unit title in support, leaving only Done;
  - `.id(model.phase)` on the ScrollView, so each phase opens at its top;
  - Retake is gated on `offersRetake`;
  - a new `init(model:onMastered:onExit:)` for the preview host.

**DesignSystem**
- `CrisisResources`: `tel:988`, `sms:988`, `sms:741741&body=HOME` and `tel:911`. The app builds these links itself and never takes them from server or model text.
- `CrisisSupportView` contains:
  - the heading "I'm really glad you told me" (marked as a header and announced to VoiceOver on appear);
  - a short intro line;
  - four tappable cards: Call 988, Text 988, Text HOME to 741741, Call 911 (each at least 56 pt tall, with VoiceOver labels that spell out the digits);
  - the line "I'm an AI, so I can't be your support person. Please tell a trusted adult too, like a parent or school counselor.";
  - "Everything else can wait…";
  - a quiet secondary close button.

  It has no Merc, grade, score or retry. At accessibility sizes the heart and the card icons are hidden and the intro line moves below the cards, so **Call 988 is visible without scrolling at AX5 on the SE**.

**ChatFeature (second commit)**
- `QuizViewModel.Phase.support`, set from `APIError.crisisSupport`. `QuizView` shows `CrisisSupportView(closeTitle: "Close")`. Before this, the quiz showed the crisis copy as a failure with an exclamation icon and a "Try again" button.

## Tests

`swift test --scratch-path /private/tmp/merc-fixios-spm`, from a clean build of the test products: **744 tests in 107 suites passed**. The baseline before this step was 717. I added 27 tests: 25 in commit 1 and 2 in commit 2.
- `UnitDefenseResultTests`:
  - the server's exact crisis payload;
  - an old payload with no field;
  - `false`/`null`/`"false"`/`0`;
  - a quoted `"true"`;
  - the crisis flag outranking A/pass, and a crisis body with only a `message`;
  - non-crisis bodies staying strict.
- `APIClientTests`:
  - a 503 crisis → `.crisisSupport` (not retryable, server copy);
  - a crisis body at 400/429/500/503 in all three spellings;
  - the fallback copy;
  - `crisis:false` leaving a busy 503 alone;
  - `crisisSupport` included in the message and retryable checks.
- `APIClientEndToEndTests` (StubURLProtocol): `gradeUnitDefense` with a 200 crisis, a 200 normal grade, and a 503 crisis.
- `UnitDefenseGradingTests` (AppFeature):
  - 200 crisis → `.crisisSupport`;
  - non-2xx crisis → `.crisis`;
  - normal grade mapping;
  - the 404 and refusal mappings unchanged;
  - an end-to-end run from the server payload to `phase == .support`, with no grade and no retake.
- `UnitTestViewModelTests`:
  - crisis → support (no grade, no error, no pass, no retake);
  - the crisis flag outranking a grade;
  - the thrown `.crisis` path;
  - `retake()` doing nothing in support;
  - `offersRetake` only after a graded fail.
- `CrisisResourcesTests`: the exact URLs and schemes.
- `QuizViewModelTests`: the crisis error → `.support`, and the real 503 body → `.support`.

App build: `xcodegen generate`, then `xcodebuild build` for the simulator (Audit 16PM) with derived data in `/private/tmp/merc-fixios-dd`: **BUILD SUCCEEDED**, with both commits in.

I did **not** run `xcodebuild test`. UnitTestView and the support view have no snapshot tests. The QuizView snapshots (loading, loaded, failed) cover states this step doesn't change, so I expect no snapshot drift from this step. I also avoided launching the snapshot target, because SnapshotTesting records any missing reference by default.

## Screenshots (`docs/ios-batch/shots/`)

All were taken from the real view-model flow via `-UnitTestCrisisPreview` or `-QuizCrisisPreview`. The 16PM sim is in light mode and the SE3 sim in dark mode.
- `01-crisis-16pm-L.png`, `01-crisis-16pm-AX5.png`
- `01-crisis-se3-L.png`, `01-crisis-se3-AX5.png`
- `01-crisis-se3-L-via503.png`: the non-2xx path. It is pixel-identical to `01-crisis-se3-L.png` (the PIL diff bbox is None).
- `01-quiz-crisis-16pm-L.png`, `01-quiz-crisis-se3-L.png`

Both sims' text size was reset to `large` afterwards.

## Other surfaces checked (not changed here)

- **Free chat and lesson chat:** a crisis reply arrives as a normal Merc bubble, not as a grade or an error. But **the hotlines are not tappable there**:
  - `ReplyLinkPolicy` lets through only `https` links, so `tel:` and `sms:` are dropped, and plain-text numbers aren't auto-linked.
  - A follow-up could show `CrisisSupportView` under a reply when the server marks it (a server flag or marker; matching the copy in the client would be brittle).
  - I haven't checked whether Merc's presence or animation on such a reply reads as cheerful.
- **Chat non-2xx or SSE error with crisis:** the server never sends one. If it ever did, a non-2xx would now become `.crisisSupport`, shown as a failed bubble with the copy and no Retry. An SSE `{"type":"error","code":"crisis"}` frame would still go through `.streamError` (sanitized, with Retry). Any future server-side crisis signal in chat needs client work.
- **Report card, concept map, fact-check, analyze:** iOS doesn't call these.
- **The web widgets** already handle `error:"crisis"` (`public/widget.js` around line 1573). They are out of scope here.

## Open risks / notes for the founder

- **Copy is client-side.** The support view uses fixed client copy that mirrors `CRISIS_COPY` and doesn't display the server's text, so the hotlines aren't duplicated as untappable text. If the server's copy changes, update `CrisisSupportView` to match. The heading "I'm really glad you told me" is shown even when the deterministic `crisisSignal` regex fires on a false positive. That matches the server's own copy.
- **The links haven't been tapped on a real device.** `tel:` and `sms:` do nothing useful on the simulator, and I didn't tap them. Only the URL strings are unit-tested. `sms:741741&body=HOME` is the iOS prefill form; on an iPad without cellular, `tel:` may offer FaceTime or nothing at all.
- **Possible stale SwiftPM test-build crash.** `APIError.crisisSupport` was appended as the last enum case. Twice, an incremental `swift test` crashed or misread enum cases: a test module compiled against the old `APIError` layout wasn't rebuilt. A clean build of the test products (`rm -rf <scratch>/arm64-apple-macosx`) fixed it each time. CI builds clean, so this shouldn't affect it. If anyone sees a SIGTRAP in `APIError.userFacingMessage` locally, that's the cause.
- `ConsentGate.currentVersion` is untouched, and nothing here needs it bumped.
- The docs and shots in `docs/ios-batch/` are left **uncommitted**, so the commits stay code-only.
