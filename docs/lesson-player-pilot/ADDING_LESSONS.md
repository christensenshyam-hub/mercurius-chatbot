# Adding a lesson to the interactive player

How to convert the next curriculum lesson, using the two pilot lessons as models:
- `ios/Packages/LessonPlayer/Sources/Content/Lesson_u1_l3.swift` (Deep dive)
- `Lesson_b1_l1.swift` (Basics)

## 1. Start from the lesson's real objective and assessment

- **Objective, title and id:** take these from `CurriculumFeature/Sources/Curriculum.swift` (Deep dive) or `BasicsCurriculum.swift` (Basics).
- **Teaching guide:**
  - Deep dive: the lesson's entry in `server.js` `CURRICULUM_PROMPT` (Teach, Key examples, Exercise, Grading note, Common mistake).
  - Basics: `lib/basicsGuide.js` (ideas, practice, check, safety point, Notes).
- **Facts:** use only the guide's checked facts. Every other claim, number, source or excerpt is invented, and is marked `.fictional`.
- **Prerequisites:** the previous lesson in the unit, or none for a unit's first lesson. `LessonPlayerCurriculumTests` checks this against the app's sequential gate.
- **Assessment:**
  - Deep dive lessons complete on demonstrated proficiency, so their activities go in `mustBeCorrect`.
  - Basics lessons complete once the practice is done and the check is answered, so those go in `mustBeAnswered`.
  - In the four Basics safety lessons the check must be right, so it goes in `mustBeCorrect`.

## 2. Write the sequence, don't split the old one

**Rhythm:**
1. A realistic scenario, with a decision on the **first screen**.
2. Brief, specific feedback.
3. A short teaching step.
4. New applications.
5. A clear finish.

**Editorial targets:**
- 6–8 steps.
- Questions 15–35 words.
- Explanations 30–60 words.
- Feedback 15–35 words.
- About 100 visible words or fewer per step.

`LessonValidator` warns when you exceed these. A justified exception is fine; record it in the lesson's header comment.

**Activities:**

| Need | Kind |
|---|---|
| One answer | `.choice` (single) |
| Several answers | `.choice` (multiple, with `partialFeedback`) |
| Weigh a claim against evidence | `.choice` with `presentation: .claimVersusEvidence`, plus `scenario` and `evidence` |
| Pick spans of a passage | `.claimSelection` (stable claim ids; the player also lists them as rows) |
| An original answer graded against a rubric | `.shortResponse` (also add the rubric to `lib/lessonPlayerRubrics.js`, see step 4) |
| A real message to the live tutor, not graded | `.practice` |

Every wrong option gets feedback that names its misconception. Watch for the answer giving itself away:
- Vary the position of the right answer across steps.
- Keep the right option from being the longest.
- Where the scenario is a real tradeoff (ethics, bias), give credit to the defensible alternatives in the feedback instead of grading one opinion as the only right one.

**Optional depth (`DepthItem`):**
- `.why`: the reasoning.
- `.example`: a worked example.
- `.stage(1…n)`: "Go deeper", the more demanding cases, in order.

Real cases carry `.real(SourceInfo)`.

## 3. Register and test

1. Add the lesson to `LessonCatalog.all`. Keep older versions of a lesson there for as long as an unfinished attempt might be pinned to them.
2. Add the id to `PILOT_LESSONS` in `lib/lessonPlayer.js`. The server switch can narrow the set with `LESSON_PLAYER_LESSONS`.
3. Write a test suite like `Lesson3Tests` or `BasicsLesson1Tests`: no validation errors, identity and prerequisites, the answer key, one played-through run, and a wrong-path run.
4. Run `cd ios/Packages && swift test --filter "LessonPlayerTests|AppFeatureTests"`.

## 4. A short response needs a server rubric

Add an entry to `RUBRICS` in `lib/lessonPlayerRubrics.js`:
- Key it by a `rubricId` such as `u2_l1.transfer.v1`.
- Give the same `lessonId`, `contentVersion` and `stepId` as the lesson data.
- Include the task as the learner sees it, the material, the core / rewarded / flag lines, and judging notes.

Then mirror the rubric in the Swift `ShortResponseActivity` so reviewers can see it. `tests/lessonPlayerEvaluate.test.js` checks that the ids match.

Without a matching registry entry the server answers 404, and the player shows "not graded yet". The lesson never completes on that.

## 5. Changing a lesson later

- Any learner-visible change bumps `contentVersion`. Keep the old version in the catalog, because unfinished attempts stay on the version they started on, and add the new one.
- A changed rubric gets a new `rubricId` (`.v2`). Keep the old rubric while old attempts may still submit.
- Remove an old version only once its attempts are likely finished. An attempt whose version is gone falls back to the legacy lesson. Its record is kept, but it can't be resumed.
