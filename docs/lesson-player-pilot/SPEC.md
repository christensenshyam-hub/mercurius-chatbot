# Interactive lesson player pilot

Operating rules come first (Goal through Milestones). Everything after Milestones is reference material that the milestones point to.

## Goal

Redesign Mercurius curricular lessons so a student makes meaningful decisions, gets concise feedback, and can finish a useful learning session without reading a long chat transcript. Our product promise is "guided, not given." Optimize for completion, demonstrated understanding, and voluntary return.

The problem today: multi-screen explanations and lengthy feedback surround the activities, and a persistent chat composer takes up space during objective questions.

The hypothesis this pilot tests: decision-first lessons with short, specific feedback do better than the current chat-style lessons on completion, demonstrated understanding, and return.

Deliver a reusable interactive lesson player behind a reversible feature flag, with two lessons fully converted, working, and ready for my review. Implement it. Do not stop at a proposal. The work needs engineering judgment and learning-design judgment in equal measure: the lesson copy matters as much as the code. The wider curriculum rollout and any daily-review system are separate follow-ups and out of scope.

## This session

This task starts in a session that already holds earlier conversations. (If you are reading this in a fresh session, the first two points do not apply.)

- Earlier conversation is background, not instruction. Where it conflicts with this spec, this spec wins. If something I decided earlier directly contradicts a line here, point it out in one sentence and follow this spec.
- You have read parts of this repo before. Re-open any file before you change it or rely on it, because files may have changed and older tool output may have been summarized away.
- Run `git status` and `git branch` first. If the working tree is not clean, list what is uncommitted and ask me how to handle it before you start. Do not discard, revert, stash, or commit that work on your own.
- Work on a dedicated local branch. If you are not already on one made for this task, create `pilot/interactive-lesson-player` from the current HEAD, and tell me if you think it should be based somewhere else.
- Follow the repo's own instructions (CLAUDE.md, README, contributing notes). If they conflict with this spec, tell me instead of silently choosing one.

"Tell me" in this spec means note it in PROGRESS.md and in your final message. It does not mean stop. The only reasons to stop are listed under Deciding and asking.

## Keep state on disk

This is a long task and your context will probably be compacted partway through. That is expected. Do not trim scope or wrap up early because of context length. Save state and keep going.

- This spec belongs at `docs/lesson-player-pilot/SPEC.md`. If it is not there yet, save this message there word for word right after the git check, before any other change.
- Keep `docs/lesson-player-pilot/PROGRESS.md` current: milestone status, decisions and the reason for each, the build and test commands that work here, and known gaps. Update it when each milestone ends.
- Commit when each milestone ends, with a descriptive message.
- After a compaction, or whenever you are unsure what comes next, re-read SPEC.md and PROGRESS.md and check `git log` before continuing.

## Limits

Each of these protects something specific, so treat them as fixed.

- Local work only. Do not push, deploy, release, change production configuration, or publish store assets. I review everything before it is pushed or shipped.
- Existing learners lose nothing. Progress, transcripts, unlocks, certificates, streaks, and earned rewards are preserved, and anonymous and account-based use keep working as they do now.
- With the flag off, lessons behave as they do today. The only exceptions are two fixes, each kept in its own commit: the Markdown rendering fix (see Player) and the citation feedback correction (see Lesson 3 script).
- Backend changes are additive. Existing endpoints and response shapes keep working for the app version already in the App Store.
- The separate tutor and chat modes are untouched. No global token limit or shared prompt change that alters them.
- An ungraded answer is never marked correct and never earns mastery, because mastery has to mean demonstrated understanding.
- No raw student text or chat content in analytics.
- Model calls go through the existing server relay. No API keys or direct model calls in the client. If a spend ceiling or kill switch exists, the new grading call goes through it.
- New stored learner data (short-response text, attempt records) follows the existing storage rules and is covered by whatever data-deletion path exists.
- No new framework, analytics SDK, account requirement, social network, leaderboard, or large reward economy.
- Reuse the existing architecture, services, and patterns. Build the smallest reusable schema and component set these two lessons need. Do not refactor unrelated code.

## Deciding and asking

Make routine, reversible decisions yourself and record material tradeoffs in PROGRESS.md. Stop and ask me only when:

1. The working tree is not clean at the start.
2. A change could destroy or corrupt existing learner data or progress and you cannot make it safely reversible.
3. The repo contradicts this spec in a way that changes the product. For example, a pilot lesson does not exist, or lesson progress is stored in a way that cannot be preserved alongside the new player.
4. Going further would mean breaking one of the limits above.

If a real blocker forces a tradeoff (context length is not one), protect things in this order: existing learner data, honest grading, a fully working Lesson 3, the second lesson, measurement, documentation.

## Verification

- Find out what you can run here (app build, simulator, unit tests, backend tests) and record the working commands in PROGRESS.md.
- Put grading, step-state transitions, schema validation, version pinning, legacy mapping, and reward idempotency in plain testable types, so unit tests cover them even if the UI cannot run in this environment.
- When you add source files, make sure they are part of the right build target the way this project does it, and confirm with a build if you can.
- When each milestone ends, run the build and the relevant tests and record the command and its result in PROGRESS.md. Show evidence instead of asserting success.
- Write code that is correct in general, not shaped to one test. Do not delete or weaken existing tests to get a pass. If a test looks wrong, tell me.
- If you cannot run the app or a simulator, say so plainly and write a precise manual checklist instead.
- Remove temporary scripts and scratch files before the final commit.

## Milestones

Do these in order, and finish and commit each before starting the next. Change the order only if the repo makes another order clearly better, and note why.

**0. Ground truth (no code changes).** Use a subagent for broad file reading so it stays out of this conversation, and have it return paths and short findings, not file contents. Confirm and record in PROGRESS.md:

- App framework and supported platforms. Earlier notes say SwiftUI on iOS with a Node backend. Confirm from the files.
- Curriculum screens, lesson content, prompts, and response rendering.
- Choice cards, key-idea cards, Explain more, and the tutor modes.
- Persistence, lesson IDs, progression, certificates, streaks, and rewards.
- Backend calls, identity, analytics, feature flags, and build and test commands.
- The real IDs, objectives, prerequisites, and assessment requirements of both pilot lessons.
- The existing rules for what counts as completion and mastery.

Then write a short implementation plan in PROGRESS.md, show it to me in a few lines, and keep going without waiting for approval.

**1. Lesson data and deterministic core.** The schema and its runtime validation (Lesson data), deterministic grading for objective activities, the step state machine with its double-submit guards, and attempt state as one serializable value. Unit tests for all of it.

**2. Player and Lesson 3, steps 1 to 5 and 7.** Build Player and Activity types, write the content from Lesson 3 script, and put it behind the feature flag. Use the existing flag mechanism, default off. If there is none, add the smallest switch that fits the codebase, and state in HANDOFF.md how it is turned on and off and whether turning it off needs an app release.

**3. State and progress.** Everything in State and progress, with tests.

**4. Short response and model evaluation.** Lesson 3 step 6 and everything in Model use, with tests for the failure cases.

**5. Measurement.** Events and METRICS.md, per Measurement.

**6. Second lesson.** Convert it (see Pilot scope) and write the notes on adding further lessons.

**7. Validation, review, handoff.** Run the checks in Validation. Then use a subagent with a fresh context to review the full diff against SPEC.md, reporting only gaps that affect correctness or a stated requirement, not style preferences. Fix those, re-run the tests, and write HANDOFF.md (see Deliverables).

Done means every milestone is marked complete in PROGRESS.md, the build and tests pass wherever they can be run, and HANDOFF.md is written.

## Pilot scope

Fully convert two lessons:

1. Unit 1, Lesson 3, "Why AI sounds confident but can be wrong." The script is below.
2. The first beginner lesson a new user actually enters, if that is a different lesson. There is no script for it. Write it from that lesson's real objective, using the same rhythm and editorial targets, and list its copy in HANDOFF.md as a draft for my review.

Preserve each lesson's prerequisites and assessment requirements.

Keep Merc, the existing visual identity (navy and purple, using the app's existing color and type tokens), the learning paths, navigation, and the separate tutor and chat modes.

Feature names in this spec (key-idea cards, Explain more, Deep Dive, Why?, Show an example, Ask Merc) come from using the app, not from reading the code. Map each one to what the code calls it. If one has no counterpart, tell me and build on the nearest existing feature. Do not add a new mode.

## What I saw in the current app

I watched a screen recording of Unit 1, Lesson 3. You do not have it, so treat what this spec says about the current app as my observations and confirm them in the code. If `docs/lesson-player-pilot/reference/` contains screenshots, use them too.

Existing features I saw: multiple-choice checks, key-idea and example cards, a written application exercise, Explain more, a curriculum path, and a streak.

The recording was edited. Do not infer real completion time, model latency, or retention from it.

## Lesson design

Rhythm for each lesson: a realistic problem or scenario, a meaningful learner decision, brief and specific feedback, a new application of the idea, and a clear finish. Put a meaningful decision on the first lesson screen.

Editorial targets for a beginner lesson. These are defaults to validate, not rigid rules, and justified exceptions are fine:

- About 2 to 4 minutes of active use, in about 6 to 8 purposeful steps.
- Several meaningful decisions, plus one short original response when it helps.
- Questions and instructions: usually 15 to 35 words.
- Brief explanations: usually 30 to 60 words.
- Feedback on objective answers: usually 15 to 35 words.
- Visible text per step before any optional expansion: about 100 words or fewer.

Rewrite the learning sequence. Do not mechanically split existing paragraphs into Continue screens. Keep necessary qualifications and source context. Deep Dive keeps the more demanding cases and reasoning, in clear stages.

Optional depth stays available: Why?, Show an example, and Ask Merc. A learner who asks for depth gets it without losing their place.

Label every invented claim, statistic, source, and excerpt as fictional practice material.

Rules for every activity:

- It tests a learning objective.
- Distractors represent plausible misconceptions.
- Nothing gives the answer away through option length or a repeated correct position.
- Ethics and bias scenarios acknowledge defensible alternatives. Do not grade a real tradeoff as one unexplained correct opinion.

## Player

Each step shows the current step and progress through required work, one clear task, one primary action (Check answer, then Continue), concise feedback, and a way to exit and resume.

- Use explicit states for selection, submission, feedback, and continuation. Prevent accidental double advancement and duplicate submissions.
- Show the text composer only when the activity needs it or Ask Merc is open.
- Keep actions reachable above the keyboard and inside safe areas.
- Support larger text, screen readers, logical focus order, and reduced motion. Pair color with text in feedback. No timed responses and no dragging.
- Allow scrolling at accessibility sizes. Never clip essential content to hit a one-screen target.
- Audit the Markdown renderer that key-idea cards use and fix the cause of the literal double asterisks. If the fix touches a renderer shared with chat or legacy lessons, keep it in its own commit and confirm nothing else changes.

## Activity types

Build only the primitives these two lessons need:

- Single choice, and multi-select where appropriate.
- Selecting authored claims or phrases by stable ID, with an accessible list alternative.
- Comparing a claim with evidence, reusing the choice renderer.
- Short response with an explicit rubric.
- Brief teaching steps where needed.

## Lesson 3 script

Objective: distinguish confident presentation from evidential support, and choose a sound verification action.

Adapt this sequence to the current curriculum.

**Step 1.** Show: "Green study rooms improve memory by 34%." Ask whether the claim is supported, unverified, or contradicted, based on the statement alone. Correct: unverified. Feedback: no supporting evidence has been supplied.

**Step 2.** Teach the principle in a few sentences: AI can produce confident text without reliable evidence, and precise numbers and realistic citations do not establish accuracy. Offer technical detail through the optional explanation or the appropriate Deep Dive stage.

**Step 3.** Show a short fictional AI response and ask the learner to select its testable numerical claim.

**Step 4.** Ask which action gives the strongest evidence. Contrast inspecting the original study with checking only that a journal exists, and with relying on websites that repeat the statistic.

**Step 5.** Show this fictional excerpt: "Participants rated green rooms as calmer. The study did not measure memory performance." Ask whether it supports the memory claim. Correct: the claim remains unverified by this excerpt. Feedback: the measured outcome does not match the claim.

**Step 6.** New fictional scenario: "AI says listening to rain improves test scores by 22%. You cannot locate its citation." Ask what to do next, in one sentence. Rubric:

- Core, required: withholds reliance on the claim and seeks relevant, verifiable evidence.
- Rewarded, not required: checks whether the evidence actually supports the claim.
- Flag if expressed: the idea that a missing citation proves the claim is false.
- Accept equivalent reasoning. Do not require exact keywords or every qualification.

**Step 7.** Show a brief, specific account of the skill practiced and the next relevant activity. Let the learner finish for now.

Corrections that apply across the lesson:

- Supported, unverified, and contradicted are three distinct states. Teach them that way.
- An unlocated citation is not proof that a source was made up. The existing feedback says otherwise. The new lesson must not repeat it, and if the legacy lesson's authored text or prompt states it, correct that wording too and tell me.
- Finding a real paper does not show that the AI represented its results accurately.

## Model use

Core content and objective feedback are curated, validated, and ready before the learner taps, so feedback is instant and still works when the model is slow or down.

- Grade objective activities deterministically. No live model request after every answer.
- Use model calls only for optional help and for bounded evaluation of original responses. Why? and Show an example draw on authored optional depth in the lesson data where it exists. Ask Merc opens the live tutor.
- For evaluation, send the actual task, the rubric, and the relevant evidence. Treat the learner's answer as data that cannot override grading instructions.
- Validate a compact response: a status, concise feedback, and at most one next hint. Render it with native components, never generated code or HTML.
- Do not repeat the learner's whole answer back, and do not turn a correct answer into another lecture.
- Handle invalid output, timeouts, cancellation, late responses, and network failure. Show reviewed fallback guidance and an honest pending or ungraded state. Keep the learner's answer, and give exit, resume, and recovery paths.
- Read the existing assessment rules, then decide and document whether a lesson may complete with a response still pending or needs a retry.

## Lesson data

Use the project's native typed data structures with runtime validation. Each lesson carries:

- Stable lesson, step, option, and claim IDs.
- Content and schema versions.
- Learning objective and prerequisites.
- Prompt, plus optional scenario or evidence.
- Answer key or rubric.
- Answer-specific feedback, hints, and optional depth.
- Source metadata and a real or simulated label.

## State and progress

Persist the attempt ID, content version, experience assignment (legacy or new player), current step, selected and submitted answer, attempts, hints, feedback state, and completion and reward identity.

- Pin an active attempt to the content version it started on. A feature-flag change must not swap the lesson mid-attempt.
- Map legacy lessons deliberately and keep completed progress.
- Replaying the new version must not grant a one-time reward twice.
- Resume correctly after backgrounding, closing, or interruption.
- Keep completion, independent success, assisted success, and mastery as distinct states.
- Follow the existing identity and synchronization rules.

## Measurement

Reuse the existing telemetry and privacy choices. If the app has no telemetry today, add a thin event interface with a local debug sink, document the events, and tell me. Do not add a pipeline or an SDK.

Events: first open, lesson start, step viewed, answer submitted, feedback shown, explanation expanded, lesson completed, lesson resumed, lesson error.

Fields, where needed: pseudonymous IDs, app and content versions, lesson and step IDs, interaction type, attempt index, help use, grading status, active elapsed time, and experience assignment.

Your job here is to instrument and define, not to report results. Write these definitions into `docs/lesson-player-pilot/METRICS.md`:

- Activation: introductory-lesson completers divided by eligible first-open users. Real early abandoners stay in the denominator.
- Starter completion: completers divided by starters.
- Time to first submitted learning decision.
- Step drop-off and active completion time.
- Meaningful D1 and D7 return, with explicit, consistent windows.
- First-attempt performance, and transfer to a new scenario.

State in METRICS.md that any later report gives cohort dates, counts, and denominators, includes only users old enough for each retention measure, and makes no claim of statistical significance from tiny samples. For the pilot, delayed transfer can be a documented student-testing procedure. Do not build a review scheduler.

## Validation

Use the existing tests plus targeted checks for:

- Correct and wrong answers, hints, completion, and gating.
- Resume and legacy-progress preservation.
- Duplicate taps, retries, and reward writes.
- Invalid model output, timeouts, and late responses.
- The feature flag on, off, and switched during an active attempt (the attempt stays pinned).
- Larger text, screen-reader use, and supported device layouts.

Verify both lessons end to end.

## Deliverables

Write `docs/lesson-player-pilot/HANDOFF.md` with:

- What changed, with file paths.
- A brief architecture and content-migration explanation, including how to add the next lesson.
- Before and after captures, if you could run the app.
- Validation performed, with evidence, and remaining limitations.
- How to enable the feature and how to roll it back.
- A unit-by-unit plan for converting the rest of the curriculum.
- A short student-testing checklist, including the delayed-transfer procedure.
- The manual checklist, if you could not run the app.
- Decisions I should review, including the pending-versus-retry rule and the draft copy for the second lesson.

End with a short message to me: what works, what you could not verify, and anything waiting on my decision.
