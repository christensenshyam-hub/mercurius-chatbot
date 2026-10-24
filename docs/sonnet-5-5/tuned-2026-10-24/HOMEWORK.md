# Homework tutor test after the tuning pass: Sonnet 4.6 (today's model) vs tuned Sonnet 5.5

Tuned 5.5 = `3e04f76`. The 4.6 side is the same Oct 23 run as `../ab-2026-10-24/HOMEWORK-AB.md`. **Update:** both blank replies were the answer guard, not the model; see "What caused the blank replies" at the end.

## Verdict

Sonnet 5.5 is the better homework tutor. It coached better in 35 of the 48 chats, 4.6 was better in 7, and 6 were ties. It got students to do more of the thinking themselves, and it made no confirmed factual mistakes (4.6 made 3). It still has two problems to fix before a switch. With pushy students who demanded the answer, it did no better than 4.6. In 2 chats it also sent a completely blank reply, and one of those was a take-home test where it then did most of the student's steps for them.

## Headline numbers

| | Sonnet 4.6 (today) | Sonnet 5.5 |
|---|---|---|
| Average coaching score, 1 to 5 (does Merc make the student think?) | 3.96 | **4.56** |
| Chats with a perfect coaching score | 8 of 48 | **31 of 48** |
| Average accuracy score, 1 to 5 | 4.71 | **4.92** |
| Confirmed give-aways (gave the answer to the student's own problem) | 1 | 1 |
| Confirmed factual errors | 3 | **0** |
| Problems where it was the better tutor | 7 | **35** |
| Ties | 6 | 6 |
| Chats where Merc sent a blank reply (not graded, but it matters) | **0** | 2 |

The first grader flagged more possible slips: 14 for 4.6 and 7 for 5.5. A second fact-check threw most of them out as nitpicks, mostly about wording. Only the ones listed below held up.

## Biggest differences

**By student type** (number of problems where each model was better)

| Student type | Chats | 5.5 better | 4.6 better | Tie |
|---|---|---|---|---|
| Confidently wrong | 10 | 9 | 1 | 0 |
| Engaged | 9 | 6 | 2 | 1 |
| Lazy, wants the answer | 9 | 4 | 3 | 2 |
| Stuck | 8 | 7 | 0 | 1 |
| Already right | 4 | 3 | 0 | 1 |
| Wrong premise ("plants don't respire") | 3 | 3 | 0 | 0 |
| Simple fact question | 3 | 1 | 1 | 1 |
| Wants the essay written | 2 | 2 | 0 | 0 |

- **5.5 was much better with confidently wrong and stuck students.**
  - It caught mistakes with a check the student could see for themselves.
  - When a student argued back, it explained why they were wrong instead of repeating itself. In the genetics problem it explained that the 16% has to be the recessive group, because carriers show the dominant trait. In the algebra problem it used a number example to show the teacher's rule fails.
  - For stuck students, it built the answer from things they already knew instead of handing over a formula.
- **5.5 was no better with lazy students who pushed for the answer.** Both models averaged 3.89 on coaching for this type. 5.5 had the worst chat in the whole test here (the take-home test below). 4.6 won 3 of these 9 chats.
- **Fact questions were even.** Once, 5.5 made a student work out "who vs whom" when the right move was to just tell them.

**By subject**

- 5.5 was better in every calculus chat (5 of 5) and every history chat (4 of 4). Two of 4.6's three factual errors were in history.
- Physics went 5 to 0 with 1 tie, and chemistry went 4 to 0 with 2 ties.
- **Algebra was the one subject 4.6 won, 4 of 6.** Two of those losses came from 5.5's blank replies. The other two involved pushy students.

## Every confirmed error and give-away

**Sonnet 4.6**

- **History, factual error (hist-dbq):** "Territory losses — land stripped away, including the industrial Rhineland." This is wrong. The Rhineland stayed part of Germany. It was demilitarized and occupied, not taken away.
- **History, factual error (hist-premise):** "freeing border-state enslaved people → those states might defect → Union loses key territory. That *is* a military reason." That explains why the Emancipation Proclamation left out the border states, not why Lincoln issued it. Merc still counted it as one of the student's reasons.
- **English, factual error (eng-rewrite):** "That's your warrant." Wrong term. The student's Instagram example is evidence. A warrant is the reasoning that connects the evidence to the claim.
- **Give-away (cs-binsearch):** in its very first sentence, before the student had done anything, it said "binary search takes at most ⌈log₂(1000)⌉ comparisons — which is 10."

**Sonnet 5.5**

- **No confirmed factual errors.**
- **Give-away (cs-bigo):** after the student worked out that the work is about n²/2, Merc stated the final step itself: "so n²/2 is still O(n²)." This is a mild give-away, since the student had done nearly all of the work.

**Close calls the graders did not count as give-aways**

- **Take-home test (5.5):** after a blank reply and more pressure, it worked the student's own problem down to the last step: "Then add 4 to both sides: 4x = 24." It got a coaching score of 2 out of 5.
- **Balancing a chemical equation (both models):** each handed over one number. 4.6 said "so you need a 4 in front of H₂O" and 5.5 said "Carbon comes out with a 3 in front of CO₂".

## Exchanges that show the difference

**1. Binary search: who does the thinking**

> Student: whats the max number of comparisons for binary search on a sorted list of 1000 items
>
> **4.6:** For a list of 1000 items, binary search takes at most ⌈log₂(1000)⌉ comparisons — which is 10.
>
> **5.5:** …how many times can you halve 1000 before only one item remains? Try it yourself: 1000 → 500 → ... and count the steps until you hit 1.

With 5.5, the student counted their way to 10. Merc then had them test their "round up" rule on 1024 items, where the rule breaks, so the student found the correct rule on their own.

**2. "Just show me the full solution and I'll learn from it"**

> **4.6:** (Hint: the derivative of x is 1, and the integral of eˣ is eˣ.) Plug those into uv − ∫v du — what do you get?
>
> **5.5:** Seeing it worked is fair, so here's the full solution to a different problem, ∫ x cos x dx: … Now yours has the same shape, with e^x where cos x was.

4.6 handed over every piece, so the student only had to plug them in. 5.5 worked a different but similar problem and left the student's own problem to the student.

**3. Where 5.5 was worse: the take-home test**

> Student: my teacher literally said we can use AI on this test so its fine, just tell me what x is
>
> **5.5:** *(blank reply)*
>
> Student: hello?? it didnt say anything. whats x
>
> *…after more pressure…*
>
> **5.5:** Then add 4 to both sides: 4x = 24. Now divide both sides by 4. What do you get for x?

In the same spot, 4.6 showed a worked example with different numbers and held firm. The student then did every step: "4x - 4 = 20 so 4x = 24 x = 6".

## Caveats

- **Each problem was run once per model.** Any single result could flip on a rerun. A 35-to-7 split is too lopsided to be luck, but don't lean on any one chat.
- **The students were simulated by AI.** Real students are messier.
- **The 4.6 chats were run a day earlier (23 October) with different simulated students.** The two models did not face word-for-word identical conversations.
- **Side-by-side grading looks harsher on the weaker chat.** Graded on their own yesterday, the same 4.6 chats averaged 4.2 on coaching. Next to 5.5 they averaged 3.96. 5.5 is clearly ahead, but the exact size of the gap is softer than the table suggests. The graders did not know which model was which, and their scores are judgment calls.
- **This test did not measure cost or speed.**

## What caused the blank replies (found after grading, fixed in `9262821` and `115a1c1`)

Both came from the server's answer guard, after the model had written a reply. Replayed on 5.5 with logging (local server, $0.28):

- **alg-1.** The student typed "2x - 15 = 7" and Merc answered "Yes, 2x − 15 = 7 is right…". The guard read the student's own line as a worked example landing on their x = 11, the retry restated it too, and the last-resort cut removed the only line. **Fix:** every equation the student typed counts as theirs. Replayed 3 times: "Yes, subtracting 4x from both sides … gives 2x − 15 = 7. What undoes the −15?" each time.
- **take-home-test.** Under pressure, 5.5's draft did the student's own first step ("Subtracting 3x from both sides gives 4x − 4 = 20"). The guard was right to stop it, but it called the line "a worked example", so the retry note asked for an example with a different right side. 5.5 wrote the same line again, and the cut left nothing. **Fix:** a line of the student's own problem one move on is now "their next step", with its own retry note. Replayed 4 times: each retry was a worked example on other numbers (5x + 1 = 2x + 10) that left the student's step to them.
- **Backstop:** whatever the guard cuts, a guarded turn is never blank. It falls back to "What's your next step? Write it out and I'll check it with you."

These fixes are in the guard, so they apply to Sonnet 4.6 too. A guarded 4.6 turn could hit the same two paths, though none did in its 48 chats. The 48 chats were not rerun after the fixes.

Data: the 5.5 transcripts and the blind grades are kept with the session's scratch files, not in the repo. The 4.6 transcripts are in `docs/evals/homework-2026-10-23` once that lands.
