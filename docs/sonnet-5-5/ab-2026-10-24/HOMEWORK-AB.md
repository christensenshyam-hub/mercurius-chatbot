**Verdict:** Sonnet 5.5 was the better tutor in 34 of 48 homework chats. Sonnet 4.6 (today's model) was better in 9, and 5 were ties. Most of the gap comes from 5.5 letting the student do the thinking more often, especially students who were stuck (5.5 better in all 8) or confidently wrong (5.5 better in 8 of 10). Accuracy was about the same, with 1 confirmed give-away and 4 confirmed errors each. 5.5's weak spot is the lazy student who keeps pushing for the answer: there it sometimes writes a big piece of the student's own problem, and that was the closest group (5 to 4).

## Headline numbers

| | Sonnet 4.6 (today) | Sonnet 5.5 |
|---|---|---|
| Average coaching score, out of 5 (did the student do the thinking?) | 4.02 | **4.60** |
| Average accuracy score, out of 5 | 4.71 | 4.83 |
| Chats with a perfect 5 for coaching | 11 of 48 | 33 of 48 |
| Confirmed give-aways (tutor handed over the answer to the student's own problem) | 1 | 1 |
| Confirmed errors | 4, in 3 chats (2 of them were caused by our server, not the model; see below) | 4, in 3 chats |
| Chats where this model was better | 9 | **34** |
| Ties | 5 | 5 |

A second checker reviewed every error the graders flagged and threw out 14 flags: 10 against 4.6 and 4 against 5.5. That hints 4.6 had more sloppy moments, but those flags are not counted above.

## Biggest differences

**By type of student**

| Student type | Chats | 5.5 better | 4.6 better | Tie | Coaching score, 4.6 vs 5.5 |
|---|---|---|---|---|---|
| Stuck | 8 | 8 | 0 | 0 | 3.88 vs 5.00 |
| Confidently wrong | 10 | 8 | 1 | 1 | 3.90 vs 4.80 |
| Engaged | 9 | 7 | 1 | 1 | 4.11 vs 4.89 |
| Lazy answer-seeker | 9 | 5 | **4** | 0 | 3.89 vs 4.11 |
| Already right | 4 | 2 | 1 | 1 | 3.75 vs 4.25 |
| Wrong premise | 3 | 2 | 1 | 0 | 4.67 vs 4.33 |
| Fact question | 3 | 1 | 1 | 1 | 4.33 vs 4.33 |
| Essay writer | 2 | 1 | 0 | 1 | 4.50 vs 4.50 |

- **Stuck and confidently wrong students are where 5.5 pulls ahead.** It usually opens with a quick check the student can see, like "pH 2 would be acidic, but NaOH is a base." Then it lets the student find the mistake. 4.6 more often runs that check itself or hands over the key step.
- **Lazy answer-seekers are where 5.5 is weakest.** 4.6 won 4 of these 9 chats:
  - In calc-int, sys-1 and proof-ind, 5.5 gave in after one or two pushes and wrote out most of the student's own setup.
  - In take-home-test it turned curt and fired off one-line questions, which read as stonewalling.
  - 5.5 won the other 5, often clearly. In balance-1, cs-code and multi-problem it held firm and used a worked example on different numbers.
- **Already-right and fact-question students: both models sometimes over-quizzed.**
  - 4.6 made already-right students ask "so is it right?" in stats-sd and calc-deriv.
  - 5.5 did the same in molarity-1, and it held back a simple grammar answer (who vs whom) in eng-grammar.

**By subject**

| Subject | Chats | 5.5 better | 4.6 better | Tie |
|---|---|---|---|---|
| Math (algebra, calculus, statistics, geometry, proof) | 18 | 13 | 5 | 0 |
| Physics | 6 | 5 | 0 | 1 |
| Chemistry | 6 | 4 | 2 | 0 |
| History and civics | 5 | 4 | 0 | 1 |
| Computer science | 4 | 4 | 0 | 0 |
| Biology | 4 | 2 | 1 | 1 |
| English | 4 | 1 | 1 | 2 |
| Economics | 1 | 1 | 0 | 0 |

- Physics, computer science and history went clearly to 5.5.
- English was basically even.
- All 5 of 4.6's math wins came from the lazy-student pattern above (4 of them) or from 5.5's wrong first reply in calc-def.

## Every confirmed error and give-away

**Sonnet 4.6**
- **Give-away (cs-binsearch).** This was its very first reply, before the student had done anything: "For a list of 1000 items, binary search takes at most ⌈log₂(1000)⌉ comparisons — which is 10."
- **Error (hist-dbq).** "land stripped away, including the industrial Rhineland". This is false: the Rhineland stayed German. It was demilitarized and occupied for a time, not taken away. A student could copy this into an essay.
- **Error (alg-1).** "notice what you just did — you verified your own answer by substituting back in". The tutor did that check, not the student.
- **Errors (quad-1, counted twice).** "The ground means height = ?, so set the equation equal to 0: −16t² + 64t + 80 = ?" and, in the worked example, "(t − 3)(t + 1) = ?". **This was our server's fault, not the model's.** The answer guard (the code that blocks replies that give answers away) replaced "= 0" with "= ?". Yesterday's report already listed it as a display bug, and none of the 5.5 chats show it. If you don't count it, 4.6 has 2 real errors.

**Sonnet 5.5**
- **Give-away (proof-ind).** After one "just write it" push, it wrote most of the student's own inductive step: "Then adding the next odd number, (2k + 1), to both sides gives: 1 + 3 + ... + (2k − 1) + (2k + 1) = k² + (2k + 1). To finish, you need the right side to look like (k + 1)²."
- **Error (calc-def).** Its first reply said: "your 12 would be right if the antiderivative came out to x³ − x² and you plugged in 2 with the 0 term dropping out". That's false, because doing exactly that gives 4.
- **Error (calc-def, same reply).** "So the slip is somewhere before the plugging-in." This is wrong: the slip was in the plugging in (8 + 4 instead of 8 − 4). It fixed this in its next reply, but the student got a confusing start. This is the worst single error in either model's chats.
- **Error (stats-sd).** "your teacher's point is a real one: a sample tends to miss the extremes ... Dividing by n − 1 corrects for both." Dividing by n − 1 only fixes the second effect, measuring from the sample's own average. So it went along with a misconception instead of correcting it.
- **Error (calc-rr).** "You just ran the same substitution test that catches a wrong answer". The tutor ran the check, not the student. This is the same kind of slip as 4.6's alg-1.

**Things the simulated students noticed in 5.5 that the graders did not count:**
- Its "how would you check an AI's answer" asides felt forced in several plain homework chats (hist-fact, growth-1, molarity-1, multi-problem).
- Small misstatements:
  - In cs-code it said "You already told me the palindrome test" when the student hadn't.
  - In stoich-1 it called the student's own wrong 18 g "an answer from an AI".
- In energy-1 it confirmed a bare guess ("is it 19.8") with no work shown.
- In take-home-test it coached a graded take-home test like homework and never responded to "my teacher allows AI". 4.6 didn't respond to that claim either.

## Three exchanges that show the difference

**1. Engaged student, binary search (cs-binsearch)**
> Student: whats the max number of comparisons for binary search on a sorted list of 1000 items
>
> **4.6:** For a list of 1000 items, binary search takes at most **⌈log₂(1000)⌉** comparisons — which is 10.
>
> **5.5:** Think about what each comparison does to the list: it cuts the remaining items roughly in half. So starting from 1000 items, how many times can you halve before you're down to 1 item?

The student then counted 9 halvings. 5.5 caught the off-by-one ("a halving isn't quite a comparison"), and the student reached 10 on their own.

**2. Confidently wrong student, chemistry (ph-1)**
> Student: pH of 0.01 M NaOH. i got 2
>
> **4.6:** Check it: NaOH is a strong base, so [OH⁻] = 0.01 M, which gives pOH = 2. What's the relationship between pH and pOH?
>
> **5.5:** Check it: pH 2 would mean [H⁺] = 10⁻² M, which is acidic. NaOH is a strong base, so something went sideways early on. What does 0.01 M NaOH release into the water, and which ion's concentration does that give you directly?

4.6 did the hard step for the student. 5.5 showed why 2 can't be right and left the hard step to the student.

**3. Lazy student, induction proof (proof-ind): the case where 4.6 did better**
> Student: bro i just need it written out, can u just type the whole proof pls
>
> **4.6:** Start with the base case — what does each side equal when n = 1?
>
> **5.5:** Here's the engine of an induction proof: assume the formula works for some k... Then adding the next odd number, (2k + 1), to both sides gives: 1 + 3 + ... + (2k − 1) + (2k + 1) = k² + (2k + 1). To finish, you need the right side to look like (k + 1)².

4.6 kept asking one question per step, and the student built the whole proof. 5.5 wrote most of it after a single push. It still did good work later: it caught the student's circular "assume it's true for all k".

## Caveats

- **Each problem was run once per model.** Any single chat could go differently on a rerun. The overall gap (34 to 9) is large enough to trust, but the splits by student type and subject rest on only 1 to 18 chats each (economics has only 1).
- **The students were simulated** by an AI following a script ("make one slip", "push for the answer 3 times"), not real teenagers. The graders and the error checker were AI too, so the scores are judgment calls.
- **The 4.6 chats were run a day earlier, with different simulated students.** The two conversations for a problem were not word-for-word the same, so some differences come from what the student said, not from the tutor. The graders said this outright about bio-fact.
- **The server was not guaranteed to be identical between the two runs.** Both ran through Mercurius's answer guard, which rewrote replies that gave answers away about 8 times in the 4.6 run and about 12 in the 5.5 run (from the server logs). The give-away counts are therefore what a student would actually see, not each model's raw behavior. The quad-1 "= ?" bug, which counts against 4.6, came from the guard.
- **Cost and speed were not measured here.**

