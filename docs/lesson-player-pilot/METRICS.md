# Lesson player pilot: metrics

This file says what the pilot measures and how. It reports no results: none have been collected.

## Where events go today

The app has **no client telemetry pipeline**. Before the pilot, the client's only logging was a local OSLog sink for the first-run flow (`OnboardingTelemetry`).

On the server, a player lesson now reports start, resume and complete to `POST /api/lesson-player/activity` (ids only), so:
- it counts toward the streak as a chat lesson does, and
- it writes the same `lesson_events` start and complete rows.

The admin D1/D7 numbers still count only `/api/chat` messages, so a learner who only uses the player does not appear in them.

So the pilot adds a thin event interface (`LessonEventSink`, AppFeature) with one implementation: the device log. No SDK, no network, no new endpoint.

- **Where it goes:** Console.app, subsystem `com.mayoailiteracy.mercurius`, category `lessonPlayer`.
- **From a terminal:** `log stream --predicate 'subsystem == "com.mayoailiteracy.mercurius" AND category == "lessonPlayer"' --info`. For a simulator, prefix `xcrun simctl spawn <udid>`.
- **Collecting from real users:** this needs a reviewed pipeline: a new sink and an endpoint, with a privacy review. **That is a decision for the founder.** Until then, numbers come only from devices observed in student testing (see HANDOFF.md).

## Privacy

- Events carry ids, versions, enums, counts and durations: **never answer text, option text, passage text or chat content**. A test plays Lesson 3 with a marked answer and checks that no event field contains it.
- `install_id` is a random UUID on the device. It is not the server session id, and "Delete my data" replaces it.
- `attempt_id` is random per attempt.
- No ages, names, or IP addresses.

## Events

Every event carries `install_id` and `app_version`. Player events also carry `attempt_id`, `lesson_id`, `content_version`, `experience` (`player` | `legacy`) and `active_seconds`, the foreground seconds in the attempt so far (paused while the app is in the background, capped at 60 s per tick).

| Event | When | Extra fields |
|---|---|---|
| `first_open` | Once per install, at the first launch, before any network call or gate, **for a new learner only** (no onboarding seen, no completed lessons). Existing learners updating to this build are marked as seen without an event. | `experience`: `player`, `legacy`, or `unknown` (the switch wasn't known yet, as on a fresh install) |
| `lesson_start` | A new attempt starts (player); a lesson's conversation is created (legacy) | none |
| `lesson_resumed` | An attempt is reopened after leaving it (player); a saved lesson is reopened (legacy) | none |
| `step_viewed` | A step is shown, including the first | `step_id` |
| `answer_submitted` | Check answer | `step_id`, `attempt_index` (0 = first try), `interaction` (`single_choice`, `multi_select`, `claim_selection`, `claim_vs_evidence`, `short_response`) |
| `feedback_shown` | Feedback appears | `step_id`, `grading_status`: `graded_correct`, `graded_partial`, `graded_incorrect` (a short response's "meets" is `graded_correct` and its "not yet" is `graded_incorrect`), `not_graded` (a practice message Merc answered), or `ungraded_<reason>` |
| `explanation_expanded` | Why?, Show an example, or a Go deeper stage is opened (once each per attempt) | `step_id`, `depth_id` |
| `help_used` | A hint is shown, or Ask Merc is opened | `step_id`, `help` (`hint`, `ask_merc`) |
| `lesson_completed` | The lesson's completion rule is met (once per attempt), as the learner leaves the last activity and before the finish screen's `step_viewed` | `success`: `independent` (every graded step right first time, no hints); `assisted` (right in the end, after a retry or hint); `notDemonstrated` (a step ended on a wrong or revealed answer) |
| `lesson_error` | A short-response check or practice message fails | `step_id`, `error` (`offline`, `timeout`, `invalidResult`, `unavailable`) |

Legacy lessons log `lesson_start`, `lesson_resumed` and `lesson_completed`, with `experience=legacy` and `lesson_id`. That is logging only; the legacy lesson is unchanged. They have no step events, because the legacy lesson has no steps.

## Definitions

**Cohorts and windows.**
- Days are the learner's local calendar days, from the device clock.
- A learner is one `install_id`.
- The cohort day is the date of `first_open`.
- Every figure is split by `experience` (player vs legacy) and `app_version`.

**Activation.**
- Numerator: introductory-lesson completers, meaning `install_id`s with a `lesson_completed` for `b1_l1` (the Basics path) or `u1_l1` (Deep dive) within 7 days of `first_open`.
- Denominator: **eligible first-open users**, meaning every `install_id` with a `first_open` in the cohort window. That includes people who leave during onboarding, choose "Just chat", or never start a lesson. Real early abandoners stay in the denominator, because `first_open` is written at launch before anything else.
- **Arm:** a learner's arm is the `experience` of their first `lesson_start`. Learners who never start a lesson are reported as their own group, by their `first_open` experience (`player`, `legacy` or `unknown`). They stay in the denominator in every view.
- Report the Basics and Deep dive paths separately as well as together. The pilot converts `b1_l1` only, so for Deep dive starters the comparison is on Lesson 3.

**Starter completion.**
- For one lesson: `install_id`s with `lesson_completed` ÷ `install_id`s with `lesson_start` for that lesson, within 7 days of their first `lesson_start`.
- A resumed attempt counts once.

**Time to first submitted learning decision.**
- Seconds from `lesson_start` to the first `answer_submitted` in the same attempt, using `active_seconds` at that event.
- Reported per lesson as a median and interquartile range, not a mean.
- The legacy lesson has no comparable event, so this is player-only.

**Step drop-off.**
- For each `step_id` **before the finish step**: attempts with a `step_viewed` for that step and no later `step_viewed` or `lesson_completed` in the same attempt, ÷ attempts that viewed it.
- Shown as a funnel in step order.
- The finish step is not counted: `lesson_completed` already fires as the learner leaves the last activity, before the finish screen appears.

**Active completion time.**
- `active_seconds` on `lesson_completed`.
- Median and interquartile range, per lesson and experience.
- Time spent in the background or in the Ask Merc sheet is excluded only in so far as the app was inactive.

**Meaningful D1 and D7 return.**
- Day 1 and day 7 after the cohort day.
- A learner counts as returned on day N when, on local day `cohort day + N`, they have any `lesson_start`, `lesson_resumed` or `answer_submitted`. Opening the app is not enough.
- Only learners whose cohort day is at least N + 1 days before the report date are included, so every included learner had a full day N.
- Fixed windows: exactly day 1 (not "within 1 day") and exactly day 7.

**First-attempt performance.**
- For each graded objective step: `answer_submitted` with `attempt_index = 0` whose next `feedback_shown` is `graded_correct`, ÷ `answer_submitted` with `attempt_index = 0`.
- Also lesson-level: the share of `lesson_completed` with `success = independent`.

**Transfer to a new scenario.**
- Immediate transfer: Lesson 3's `transfer` step (a new claim, in the learner's own words).
  - The rate is the share of first submissions (`attempt_index = 0`) whose `feedback_shown` is `graded_correct` (the server's "meets"), out of first submissions with any `graded_*` status.
  - Submissions with an `ungraded_*` status are reported as their own count, never as misses or passes.
- Delayed transfer: a documented student-testing procedure (HANDOFF.md), not built into the app.

## Rules for any later report

- Give the **cohort dates**, the **counts**, and the **denominator** of every rate.
- Include only learners old enough for each retention measure: D1 needs a cohort day at least 2 days before the report; D7 needs one at least 8 days before.
- Make **no claim of statistical significance from small samples**. With fewer than about 100 learners per arm, report counts and rates descriptively and say the sample is small.
- Say which lessons, content versions and app versions are included, and whether the switch changed during the window.
- Ungraded short responses are counted on their own, never as failures or passes.
