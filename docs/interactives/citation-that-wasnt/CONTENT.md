# "The Citation That Wasn’t": the content

**What this is:** every line a student sees or hears in Unit 1 Lesson 3's interactive on the iPhone and the Mac, every number with its source or derivation, every factual claim with its source, the invented-name searches, and the checklist for the teacher who reviews it.
**Where it shows:** Unit 1, Lesson 3 ("Why AI sounds confident but can be wrong"), as a card at the end of the part of Merc's first reply that holds its first [EX] example (the hallucination example, usually Mata v. Avianca), before that reply's check. Anchor `.firstExample`, no spoiler terms (SLATE.md ★3).
**Status:** built on both platforms, **shipping dark** (`enabled: false` in `InteractiveRegistry`). It turns on only in its own last commit, after the teacher's sign-off below is recorded and the founder says OK.
**The code** (`ios/Packages/LessonInteractives/`):
- `Sources/Cards/CitationThatWasnt/CitationContent.swift`: the authored data (slots, candidates, chances, the two paths) and the pure logic (`CitationWalk`, ranks, the references).
- `…/CitationCopy.swift`: every line below, and what VoiceOver says.
- `…/CitationState.swift`: the student's walk, guess, reveal and rewrite, in memory only; the card's DEBUG arguments.
- `Sources/Views/Citation/`: the body and pieces both platforms draw. `Sources/Views/Phone/CitationPhoneCard.swift` (iPhone) and `Sources/Views/Mac/NightCitationCard.swift` (Mac: the night-sky reply, the candidate columns and their keys).
- `Tests/CitationThatWasntTests.swift` and `ios/MercuriusUITests/CitationThatWasntUITests.swift`.

The card is a picture the app draws. It sends nothing, stores nothing, runs no model, and changes nothing in the prompt, the wire or the lesson.

---

## 1. Every line the student sees

Curly quotes and apostrophes are as drawn.

### The card

| Where | Text |
|---|---|
| Eyebrow | INTERACTIVE |
| Title | The Citation That Wasn’t |

### The hook (readable before any tap)

| Where | Text |
|---|---|
| The student's bubble (trailing, drawn as the student's own turn) | Can you give me a study showing that houseplants help students concentrate? |
| The example reply's label (inside the reply) | EXAMPLE REPLY, WRITTEN FOR THIS LESSON |
| The reply | Sure, here’s one: |
| The reference, before any slot is written | [author] ([year]). [title]. [journal], [volume, pages]. (the slot being written is underlined; the others are dimmed) |
| Label under the reply (kind: example) | Example, written for this lesson. Every name in this reference is invented. The model here writes from memory, with no search. |

The reference fills in as the student goes: "Quillfeather, T. ([year]). [title]. …", until it reads in full: **Quillfeather, T. (2018). Houseplants and attention in secondary-school classrooms. Journal of Classroom Ecology, 14(3), 211–229.** Every piece arrives in the same type as the rest, with no hedge (and no italics: the app's Lexend has no italic face).

### Guess the next piece (one slot at a time)

| Where | Text |
|---|---|
| Heading | Guess the next piece |
| Step strip (decoration; not at the accessibility sizes, nor where it doesn't fit) | Author · Year · Title · Journal · Pages (written slots carry a check; the slot being written is bold with a filled bar) |
| The step's heading | Step 1 of 5 · First author / Step 2 of 5 · Year / Step 3 of 5 · Title / Step 4 of 5 · Journal / Step 5 of 5 · Volume and pages |
| Prompt (until the guess) | Which piece will the model draw next? |
| Under the candidates | + many more names / + other years / + many more titles / + many more journals / + many more numbers |
| Label beside the bars (kind: illustrative) | The chances are illustrative, not from a real model. Shown a few words at a time; real models go one small piece (token) at a time. |

**The candidates** (each a button: the words, the chance printed, and a bar on a 0–100% track):

| Slot | 1st bar | 2nd bar | 3rd bar |
|---|---|---|---|
| First author | Quillfeather, T. 12% | Ambervale, R. 11% | Fernwhistle, M. 9% |
| Year | 2019 24% | 2018 21% | 2020 19% |
| Title | Houseplants and attention in secondary-school classrooms 62% | Indoor plants and student focus: a classroom study 14% | Classroom greenery and adolescent attention: a pilot study 8% |
| Journal | Journal of Classroom Ecology 41% | Indoor Learning Review 22% | Bulletin of School Botany 10% |
| Volume and pages | 14(3), 211–229 8% | 9(2), 45–61 7% | 22(1), 102–118 7% |

**After the student's guess** (whatever they guessed, the model's authored pick is drawn):

| Where | Text |
|---|---|
| The model's pick | lit, with a check and the word **picked** |
| The student's guess, when it wasn't the pick | a dashed edge, a hand and the words **your guess** |
| Line, guess ≠ pick | The model drew 2018 this time. |
| Line, guess = pick | The model drew Quillfeather, T. this time, the same as your guess. |
| Extra line, when the pick isn't the likeliest (the walk: only the year) | Drawn by chance, not always the likeliest. |
| Extra line at the title (the walk draws the 62% one) | The likeliest title just echoes the question. That’s why it sounds so right. |
| Button (slots 1–4) | Next piece |
| Button (slot 5) | See the finished reference |

There is no score, and nothing says right or wrong.

### The finished reference

| Where | Text |
|---|---|
| Heading | The five pieces it drew |
| Five rows | Author · ✓ Quillfeather, T. · 12% / Year · ✓ 2018 · 21% / Title · ✓ Houseplants and attention in secondary-school classrooms · 62% / Journal · ✓ Journal of Classroom Ecology · 41% / Pages · ✓ 14(3), 211–229 · 8% (each with its bar) |
| Label | (the illustrative label again, beside these bars) |
| Caption | Its chances ran from 8% to 62%, but the finished text looks equally sure at every step. |

On the Mac the night-sky reply glows once as the fifth piece lands (not under Reduce Motion, Increase Contrast or Reduce Transparency).

### Predict, then reveal

| Where | Text |
|---|---|
| The question (a header) | This study doesn’t exist. At which step did the model decide to make it up? |
| Chips (one tap locks; it can't be changed) | The author / The journal / The page numbers / No step did. Once locked they are no longer buttons: the pick keeps its check and accent fill, the others read in reading text (`ink2`), all at 4.5:1 or better |
| Button, once locked | Show me |
| Reveal, "You guessed" (not in spoiled mode) | e.g. The author |
| Reveal, "What happened": first, whatever the guess | No step did. None of these steps chose to invent it, and none of them checks that the source is real. |
| …then, after "The author" | The author was the first invented piece, but that step only drew one likely-looking name (12%). |
| …after "The journal" | The journal (41%) is as made up as the author (12%): each was just one of the likeliest next pieces. |
| …after "The page numbers" | The page numbers were the least likely piece (8%), but the title (62%) is just as made up. |
| …after "No step did" (and in spoiled mode) | Each piece, at 8% or at 62%, was just one of the likeliest next pieces. |
| Under the reveal | There may be real research on this question. This reference isn’t part of it. |

The last sentence answers the reason behind each guess (refutation text names the idea, then refutes it: RESEARCH.md §1). Two choices are the low bars, which invites "the unlikely piece is the made-up part"; their answers set each beside a likelier piece that is just as made up. None says right or wrong.

At the reveal all five rows of drawn pieces light up at once (a wash and an accent edge; under Increase Contrast a solid 2 pt edge instead of a glow).

### Write it again

| Where | Text |
|---|---|
| Button (after the reveal, once; the ↺ glyph, as Patch the Reward's "Play it again") | Write it again |
| A second example reply | The same question, asked again · EXAMPLE REPLY, WRITTEN FOR THIS LESSON · Sure, here’s one: · **Ambervale, R. (2019). Indoor plants and student focus: a classroom study. Indoor Learning Review, 9(2), 45–61.** (written one piece after another; all at once under Reduce Motion, and when VoiceOver is on) |
| Line under it | This time the first draw was Ambervale, R. (11%), not Quillfeather, T. (12%), and every piece after it followed from that start. |
| Caption | A model draws from its chances at every step, so the same question can get a different made-up source. |

The line ties the second reference to the bars the student saw, and only to step 1's: that is the one step whose chances a second try shares (nothing is written yet). Every later piece's chances would depend on what came before it, so the card quotes none of them (§3, labelled simplifications).

### The takeaway (shown with the reveal)

| Where | Text |
|---|---|
| Heading (the family's takeaway style, `InteractiveTakeaway`) | Likely isn’t the same as true. |
| Line | ChatGPT wrote the fake court cases in Mata v. Avianca (2023) the same way, one likely piece at a time. |

A callback to the example in Merc's reply just above the card (the guide's Mata v. Avianca line), not a second telling of it.

Then the lesson's own check continues below the card.

### Spoiled mode

The registry gives this card no spoiler terms (the hook doesn't give away a mechanism question), so a student never sees spoiled mode unless that changes. It exists, as every card's does: no step question; the reveal (without "You guessed") comes with "See the finished reference"; "Write it again" follows. DEBUG's `-InteractiveState spoiled` shows it.

### The compact card (Mac only: narrower than 440 pt)

| Where | Text |
|---|---|
| Eyebrow, title | INTERACTIVE · The Citation That Wasn’t |
| Line | Guess each piece as a model writes a study’s reference, and see how a source that never existed gets written. |
| Button | Try it |

### What VoiceOver says

| Element | Spoken |
|---|---|
| The card's title (a header; its value is the state in one sentence) | Interactive: The Citation That Wasn’t. Value, e.g.: "Step 2 of 5, Year: the model drew 2018, at 21 percent, the 2nd likeliest of 3." After the reveal: "No step decided to make it up: each piece was one of the likeliest next pieces, and no step checks that the source is real." After the rewrite: "Written again: Ambervale, R., 2019. … A different made-up source." |
| The student's bubble | A student asks: Can you give me a study showing that houseplants help students concentrate? |
| The example reply (one element) | Example reply, written for this lesson. Sure, here’s one: Quillfeather, T., 2018. Not written yet: title, journal, volume and pages. |
| The step's heading (a header) | Step 2 of 5, Year. Written: First author. |
| Each slot (a group named for the slot) holding three choices | First author. Quillfeather, T., 12 percent, illustrative, 1 of 3. Button. Hint: Which piece will the model draw next? |
| A choice after the draw | no longer a button (the slot is written); value "picked", "your guess", or "your guess, picked"; the pick is also "selected" |
| Pages are said in words | Volume and pages. volume 14, issue 3, pages 211 to 229, 8 percent, illustrative, 1 of 3. |
| Announced after a guess | The model drew 2018 this time. Drawn by chance, not always the likeliest. (at the title: "… The likeliest title just echoes the question. That’s why it sounds so right."; after the fifth: "… The reference is finished: Quillfeather, T., 2018. Houseplants and attention in secondary-school classrooms. Journal of Classroom Ecology, volume 14, issue 3, pages 211 to 229.") |
| On Next piece | iPhone: VoiceOver's focus moves to the new step's heading ("Step 3 of 5, Title. Written: First author, Year. Heading."), since the button pressed is gone. Mac: announced, "Step 3 of 5 · Title" (its keyboard flow moves focus to the first candidate). |
| On See the finished reference | iPhone: focus moves to "The five pieces it drew, heading" (the whole reference was just read after the fifth draw). Mac: announced, "The finished reference: … Its chances ran from 8% to 62%, but the finished text looks equally sure at every step." |
| Each drawn-piece row | Year: 2018, 21 percent, picked. |
| The step question | a header, then four buttons; once locked they are no longer buttons: the pick reads "The author, selected, Your guess, locked in", the others their words |
| On Show me | iPhone: focus moves to the reveal, which reads "You guessed The author. No step did. None of these steps chose to invent it, … The author was the first invented piece, but that step only drew one likely-looking name (12%)." Mac: announced, "You guessed The author. No step decided to make it up, and no step checks that the source is real. The author was the first invented piece, …" |
| Write it again | Write it again. Hint: Draws again from the start, one likely piece at a time |
| On Write it again | iPhone: focus moves to the second reference (written whole while VoiceOver is on), then the line and caption under it. Mac: announced, "Written again: Ambervale, R., 2019. … This time the first draw was Ambervale, R. (11%), not Quillfeather, T. (12%), and every piece after it followed from that start. A model draws from its chances at every step, so the same question can get a different made-up source." |
| The takeaway (one element) | Likely isn’t the same as true. ChatGPT wrote the fake court cases in Mata v. Avianca (2023) the same way, one likely piece at a time. |

---

## 2. Every number, and where it comes from

| Number(s) on the card | Source or derivation | Checked by |
|---|---|---|
| The fifteen chances (12, 11, 9 · 24, 21, 19 · 62, 14, 8 · 41, 22, 10 · 8, 7, 7 %) | **Authored, illustrative** (slate.json `data.slots`, unchanged). Not from a real model, and labelled so beside every set of bars and in every VoiceOver line that says one. Their shape is chosen to show a contrast (flat names vs. a peaked title that follows from the question); a whole multi-word piece such as a title would be far less likely in a real model, which goes one token at a time | `CitationContentTests.slots` asserts them against the slate's values, typed into the test (slate.json is outside the repo, so that comparison was made by hand; it matches but for the two recorded changes). It also checks each slot's three are listed top first, positive, and leave room for "+ many more" |
| "Drawn by chance, not always the likeliest" (the year) | Derived: the walk's pick at the year is candidate 2, ranked 2nd of 3 by its chance; every other pick on the walk is the likeliest | `ranks` (`notTopSlots(path: 0) == [.year]`) |
| "from 8% to 62%" (the finished caption); "the least likely piece (8%)", "the title (62%)", "at 8% or at 62%" (the reveal) | Derived: the lowest and highest chance among the walk's five picks (the pages, the title) | `quotedChances` (`leastLikely(path: 0) == .volumeAndPages`, `mostLikely(path: 0) == .title`, the min and max of the five) |
| "(12%)" for the author, "(41%)" for the journal (the reveal) | Derived: the walk's picks at those slots | `quotedChances` |
| "Ambervale, R. (11%), not Quillfeather, T. (12%)" (under the second reference) | Derived: step 1's pick on each path. Only step 1 is quoted: its chances are the only ones a second try shares | `quotedChances` (and no later slot's chance appears in the line) |
| The second path's four lower bars | Derived the same way (the author, title, journal and pages are 2nd bars; 9(2) and 22(1) tie at 7%, and the order shown breaks the tie) | `ranks` |
| Step 1–5 of 5, "1 of 3", "the 2nd likeliest of 3" | Counts of `CitationSlot` and of each slot's candidates, and a pick's rank | `steps`, `voiceOver`, `summaries` |
| 2018, 2019, 2020; 14(3), 211–229; 9(2), 45–61; 22(1), 102–118 | **Authored parts of the invented references.** They are not facts about anything | `everyNumberAccountedFor` (every number in every line is one of these, a chance, a count, or the guide's two numbers) |
| 2023 | **The lesson guide** (`CURRICULUM_PROMPT`, U1L3 Key examples, in PR #44's `server.js`; fact-check row 13): "Mata v. Avianca (2023): lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000." The takeaway now names the case and its year only (Merc's reply above the card gives the rest, $5,000 included) | `guideNumbers` (the takeaway's only number is the guide's year) |

No fabrication rate, no calibration figure and no probability of the whole reference is shown (SLATE.md accuracy notes). The card never multiplies the chances.

---

## 3. Every factual claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | A model writes a reply one piece at a time, each a likely next piece given everything before it; "real models go one small piece (token) at a time" (the card shows a few words at a time, labelled). | True; **read** 2026-10-21. The guide's U1L1 As-of note: "models still write one token at a time". | 3Blue1Brown, *But what is a GPT?* (Deep Learning ch. 5): to generate longer text, "take a random sample from the distribution it just generated, then run it all again"; that repeated prediction and sampling is what happens in ChatGPT. <https://www.3blue1brown.com/lessons/gpt> |
| C2 | Models usually **draw** from their chances rather than always taking the top piece ("Drawn by chance, not always the likeliest"; "A model draws from its chances at every step, so the same question can get a different made-up source"). | True for chat models at their usual settings; a temperature of 0 (greedy decoding) would always take the top piece. **New fact row** (BUILD_PLAN.md §4.2: "Models usually sample from next-token chances rather than always taking the top one"), to be added to `curriculum-factcheck.md` and verified by someone other than its author. Not a statistic, so no guide line is needed. It also corrects `ut1_q2`'s explanation ("predicts the most likely next token"), which the fact-check already flags as a simplification. | 3Blue1Brown (above, **read** 2026-10-21): the next piece is a random sample from the distribution; a temperature T in the softmax sets how much the largest values dominate, and at T = 0 "all the weight goes to the maximum value". · Cho et al. 2024, *Transformer Explainer* (arXiv 2408.04619): the abstract (**abstract** read 2026-10-21) describes "observing next-token predictions in real time" and adjusting hyperparameters; its temperature and sampling controls are in the tool itself, not re-checked here. <https://arxiv.org/abs/2408.04619> |
| C3 | No step decides to make the reference up, and none of these steps checks that a source is real; each piece was just one of the likeliest next pieces. | True of next-token writing from memory (the card's scenario: "The model here writes from memory, with no search"). It is the guide's own teach point: "next-token prediction optimizes for plausibility, not truth". The card says "none of **these** steps checks", not "nothing inside the model could stop it": see the teacher note. | Guide U1L3 Teach line. · **Teacher note only (not on the card):** Anthropic, *On the Biology of a Large Language Model* (2025; re-read 2026-10-21) describes default circuits that push the model to decline, which "known entity" features suppress so it can answer; "at least some hallucinations can be attributed to a 'misfire' of this inhibitory circuit". A mechanism behind *whether* a model answers, not a decision to lie. If a student says the model "decided" when it wrote "Sure, here’s one:", that is the closest real answer: a misfiring "I know this" signal deciding whether to answer at all, before the first piece, not a choice to invent; some models do decline at that point. <https://transformer-circuits.pub/2025/attribution-graphs/biology.html> |
| C4 | "The model here writes from memory, with no search." | A scenario label, true of the example. It's there because chatbots now can search (guide row 12), and a student may know that. | Guide U1L2 As-of note; fact-check row 12. |
| C5 | ChatGPT wrote the fake court cases in Mata v. Avianca (2023) the same way, one likely piece at a time. | True. The case, its year and ChatGPT's part are the guide's line (row 13, High), which Merc's reply above the card gives in full ($5,000 included). **Primary**, read 2026-10-22: Judge Castel's Opinion and Order on Sanctions (S.D.N.Y. 22-cv-1461, Doc 54, filed and dated June 22, 2023). Page 1: the respondents "submitted non-existent judicial opinions with fake quotes and citations created by the artificial intelligence tool ChatGPT"; page 34: "A penalty of $5,000 is jointly and severally imposed on Respondents", who are LoDuca, Schwartz and the Levidow firm (page 1). The filing that first cited them was a March 1, 2023 "Affirmation in Opposition" (page 4), which the guide's "brief" simplifies fairly. "The same way, one likely piece at a time" is C1: ChatGPT writes every reply by repeated next-token prediction and sampling. (Wikipedia contradicts itself on the date, May vs. June 22; the opinion settles it.) | CourtListener RECAP, Doc 54: <https://storage.courtlistener.com/recap/gov.uscourts.nysd.575368/gov.uscourts.nysd.575368.54.0.pdf> (pp. 1, 4, 34) · row 13's source, the Steptoe SDNY blog: <https://www.steptoe.com/en/news-publications/sdny-blog/judge-castel-sanctions-lawyers-who-submitted-fake-cases-generated-by-chatgpt.html> · C1 |
| C6 | "There may be real research on this question. This reference isn’t part of it." | True: there is real research on plants in classrooms (e.g. a 2020 *Building and Environment* paper of three field experiments, one in a secondary school, found up in the name search below). The card cites none of it on purpose; it only refuses to call the topic unstudied. | Van den Bogerd et al., "Greening the classroom: three field experiments on the effects of indoor nature on students' attention, well-being, and perceived environmental quality", *Building and Environment* 171 (2020); **abstract** seen 2026-10-21 (VU Amsterdam research portal). <https://research.vu.nl/en/publications/greening-the-classroom-three-field-experiments-on-the-effects-of-/> |
| C7 | The example reply, its reference and every name in it are invented for the lesson. | True: see §4. | — |
| C8 | **Teacher note only (not on the card):** real made-up references usually borrow real journal names and ordinary or real author names, so checking that the journal exists isn't enough; the check is finding the article itself. The card invents every piece, the journal included, because it may not name a real journal or person beside a fake (FACT RULE row 7); a student shouldn't generalize from that. | True; **read** 2026-10-22. In a study of ChatGPT-generated literature-review citations, the fabricated ones "include the names of real journals, publishers, and organizations"; in its Table 3 about 2% of fabricated article citations (GPT-3.5 and GPT-4 alike) had a fabricated journal. No rate goes on the card (it isn't in the guide). | Walters, W. H. & Wilder, E. I. (2023), "Fabrication and errors in the bibliographic citations generated by ChatGPT", *Scientific Reports* 13, 14045. <https://pmc.ncbi.nlm.nih.gov/articles/PMC10484980/> |

**Labelled simplifications:**
- **A few words at a time.** The card writes a few words per step; real models go one token at a time. Labelled on the card beside every set of bars.
- **One set of chances per step.** In a real model each step's chances depend on the pieces before it ("given everything before it", C1), so once Ambervale, R. (2019) is written the title's, journal's and pages' chances would change. The card shows one set per step (the walk's). "Write it again" therefore quotes only its first draw against step 1's bars ("Ambervale, R. (11%), not Quillfeather, T. (12%)", the one step whose chances a second try shares, since nothing is written yet) and says every piece after it "followed from that start"; it never says the second try reused every step's chances (a test holds that no line says "same chances").
- **Every piece invented, the journal too.** Real fakes usually borrow real journal names (C8). The card can't, by rule; the teacher note covers it.

**What the card avoids saying, on purpose:**
- that a low chance marks the made-up part (the flat author bars are not "where it went wrong"; the peaked title is just as invented), and it never multiplies the chances into a probability for the whole reference;
- that the model chose, wanted, knew or lied (intent words appear only in the step question and the reveal lines that refute it);
- that a second try reuses every step's chances (only step 1's are the same);
- that houseplants don't help students, or that nobody has studied them (only that THIS reference doesn't exist);
- any fabrication rate or calibration figure (those stay in the tutor's text);
- that this is how Mercurius's own model answered (it's labelled an example written for the lesson, and the chances "not from a real model");
- how to check a reference (that is the lesson's exercise, which the card leaves to the student).

---

## 4. The invented names: searches (2026-10-21)

Every author, title and journal was searched before ship (FACT RULE row 7; BUILD_PLAN.md §4.4). Scripted searches: the **Crossref** REST API (works by author; works by bibliographic title; journals), the **ORCID** public API (family name), **OpenAlex** (authors; works by title; sources, which index journals with their ISSNs). A **web search** of each exact phrase in quotes stood in for Google Scholar. Positive controls (a real 2017 classroom-plants title, *Learning Environments Research*, *Journal of Learning Spaces*) were found by the same scripts, so a miss means a miss.

| Name | Crossref | ORCID | OpenAlex | Web (quoted) | Result |
|---|---|---|---|---|---|
| Quillfeather (author) | 0 | 0 | 0 | no researcher (only a fictional Forgotten Realms character and a blog username) | kept |
| Ambervale (author) | 0 | 0 | 0 | none | kept |
| **Thistlewood** (the slate's third author) | 138 works, many by D. Thistlewood (art and design education) | 15 people | 17 authors | — | **replaced**: a real surname with published researchers, some in education |
| Fernwhistle (its replacement) | 0 | 0 | 0 | no person (only a fantasy fairy-name generator; no surname record) | used |
| Houseplants and attention in secondary-school classrooms | no match | — | 0 | no exact match | kept |
| Indoor plants and student focus: a classroom study | no match (nearest: "Stress Reducing Effects of Indoor Plants in a Classroom Setting") | — | 0 | no exact match | kept |
| Classroom greenery and adolescent attention: a pilot study (authored for the slate's "(third title)") | no match | — | 0 | no exact match | used |
| Journal of Classroom Ecology | no journal | — | no source | no journal ("classroom ecology" is a research term, not a title) | kept |
| Indoor Learning Review | no journal | — | no source | no journal (nearest: *Informal Learning Review*, a different, real title) | kept |
| Bulletin of School Botany | no journal | — | no source | no journal (nearest: 1899 *Asa Gray Bulletin* articles on school botany) | kept |

**Not done by script (open for the reviewer):** the **ISSN Portal** search page doesn't answer scripted queries (a positive control failed too), and **Google Scholar** wasn't queried directly. Two partial stand-ins: OpenAlex's source index carries ISSNs and found none of the three journals, and a web search for portal.issn.org records of the three titles found the control's record (*Learning environments research*, ISSN 1387-1579) and none of ours. A by-hand ISSN Portal and Scholar search of the three journals and three titles is still item 8 of the checklist.

---

## 5. Placement and behaviour (for the reviewer)

- **Where:** Lesson 1.3's first reply with an [EX] example, at the end of that example's part, before the reply's check. With no example, at the reply's end before its check (today's rule). If Merc's first reply has no [EX] block, the card sits at its end (SLATE.md risk 2).
- **Never** mid-stream, in a cut-off reply, or in a thread with a crisis line. Once per thread; reopened in the same run it is back in the same place with the student's progress (the lesson's `InteractiveStateStore`, in memory only). A new lesson screen starts it fresh.
- **The hook doesn't spoil it.** Merc's text says hallucinations happen (that's the lesson); the card asks *which step decided*, which the text doesn't answer. So the card has no spoiler terms.
- **Nothing plays by itself.** Every slot, the reveal and the rewrite wait for a tap.
- **A tap keeps what it changed in view** (release builds too, not only the shots' DEBUG scrolls): after a guess, the draw's result and "Next piece" (the least scroll that shows them); after "Next piece", the new step's heading; after "See the finished reference", the five drawn pieces at the top; after "Show me", the reveal (at the top at the accessibility sizes); after "Write it again", the second reference. A jump under Reduce Motion; nothing moves when it already shows.
- **Exercise clash:** low. The exercise asks the student to flag claims in a paragraph and say how to check them; the card shows how a fake gets written, and never how to check one.

---

## 6. The VoiceOver walk-through (to do once on a device)

1. Swipe to the card: "Interactive: The Citation That Wasn’t, heading", with the state ("Step 1 of 5, First author: Pick the piece you think gets written next.").
2. The student's bubble, then the example reply ("… Not written yet: first author, year, title, journal, volume and pages."), then the label.
3. "Guess the next piece, heading". "Step 1 of 5, First author, heading".
4. The three choices, each "First author. … percent, illustrative, 1 of 3, button". Double-tap one: hear "The model drew Quillfeather, T. this time …".
5. "Next piece": focus lands on "Step 2 of 5, Year. Written: First author. Heading." Pick 2019: hear "The model drew 2018 this time. Drawn by chance, not always the likeliest."
6. Through the fifth slot (the title's draw adds "The likeliest title just echoes the question…"; the fifth reads the whole reference); "See the finished reference": focus lands on "The five pieces it drew, heading", then the rows and "Its chances ran from 8% to 62%, but the finished text looks equally sure at every step."
7. The question (a heading) and its four chips. Pick one (it reads "selected, Your guess, locked in"; the others are no longer buttons); "Show me": focus lands on the reveal, "You guessed …. No step did. …", ending with the answer to that guess.
8. "Write it again": focus lands on the second reference, read whole, then its line and caption. Then the takeaway, then the lesson's check, which still answers by double-tap.

## 7. The Mac's keys

- Tab reaches each candidate; ←/→ (and ↑/↓ while the lesson's check isn't waiting) move between a slot's candidates while one has focus; Space or Return picks.
- After a pick from the keyboard, focus moves to "Next piece"; after it, to the next slot's first candidate; after the fifth, to the first step chip, then "Show me", then "Write it again". A click picks without keeping the keyboard.
- While a card control has focus it holds Return, so the lesson's check never locks in from it. A–D and 1–4 still answer the check, and a pick there takes the keyboard back.
- Below 440 pt the card starts compact; "Try it" (Tab, Space or Return) opens it, and the keyboard goes to the first candidate.

---

## 8. Teacher checklist (BUILD_PLAN.md §4.5)

Walk the card on an iPhone and on the Mac, inside a real Lesson 1.3 run.

1. [ ] The aha lands in about 75–90 s, without the tutor's help: no step "decided"; likely pieces add up to a source that never existed. Try each of the four step guesses once: each reveal answers its own reason, and none reads as right or wrong.
2. [ ] Every label is visible and understood: "Example, written for this lesson", "Every name … is invented", "illustrative, not from a real model", "a few words at a time … (token)", "The model here writes from memory, with no search". **Teacher note (C8):** real made-up references usually borrow real journal names and ordinary or real author names, so "the journal exists" proves nothing; the check is finding the article itself. Say so if the class generalizes from this card's all-invented reference.
3. [ ] 9th-grade language; nothing reads as live AI or as Merc's own answer.
4. [ ] The tutor's reply above the card didn't answer the step question in that run (it has no spoiler terms; note it here if it did).
5. [ ] **Exercise clash:** do the lesson's exercise right after the card; the card didn't answer it.
6. [ ] **Ethics for minors:** no real person is named except in the guide's Mata v. Avianca line; no real journal or researcher is called fake.
7. [ ] **Accessibility:** a VoiceOver-only pass (§6); AX5 on an iPhone SE; keyboard-only on the Mac (§7); Reduce Motion; Increase Contrast.
8. [ ] **Names:** an ISSN Portal and a Google Scholar search, by hand, of the three journals and three titles (§4); any match is replaced.
9. [ ] **Fact row:** C2's new row ("models usually sample…") is in `curriculum-factcheck.md`, verified by someone other than its author.
10. [ ] **Wording changed from the slate** (§10): approve or replace each line, in particular "Likely isn’t the same as true." (the slate's "Likely isn’t true." reads as "probably isn't true"), "one of the likeliest next pieces" (the slate's "a likely next piece", beside picks at 8% and 21%), and the walk's heading "Guess the next piece".

**Sign-off:** _not yet signed_. (Name, date, device and OS, and the run's lesson transcript id when signed. Then, and with the founder's OK, a last commit sets `enabled: true`.)

---

## 9. Verification (2026-10-21/22)

Branch `feat/ia-citation-that-wasnt` (from `feat/interactives-wave1` at `4d401bd`). Shots are in `shots/`, kept out of git; the review pass below supersedes the first pass's results.

- **`swift test`** (ios/Packages): 1,310 tests pass, including the 4 suites in `CitationThatWasntTests`: the fifteen chances asserted against the slate's values (typed into the test; the comparison with slate.json itself was by hand), and the ranks, picks, both references, the counts and the guide's numbers derived; the register; the labels; every VoiceOver summary; the gate; spoiled mode; the DEBUG states; nothing encodable.
- **CI lint** (`ios/scripts/ci-compat-lint.py`): 0 findings.
- **iOS build and `xcodebuild test`** on an iPhone 16 Pro Max simulator (iOS 26.4), snapshot recording forced off, the snapshot suite run separately:
  - unit tests: 6 of 6 pass;
  - UI tests: 35. In the full run 32 passed. Three failed, and each passes when re-run: `CitationThatWasntUITests` (a query that matched two nested buttons; fixed with `firstMatch`), `testTabBarHasChatAndCurriculum` (a 15 s wait under load) and Lesson 1.1's `LessonInteractiveUITests` (it failed on a simulator holding state from this card's screenshot launches, and passed on a fresh install). The new test walks all five slots, locks "No step did", reveals, writes it again, and answers the lesson's check after the card with one tap.
  - The last change after that run is the step heading's no-break spaces (a string, re-tested in `swift test`).
- **Snapshots** (`ios-unchanged-check.sh`): the same 23 results as the baseline (11 pass, 12 already stale), with the same pixels for every stale render. No record run.
- **Mac:** the Debug build succeeds. Shots come from a renamed copy (`….macnsia4`), at 1280×800 and 700×600, light and dark: alone (`-InteractiveGallery`) at the year's draw, after the reveal and after "Write it again", and in the u1_l3 stub lesson after the example's part. The founder's running app was never touched. The script's "running before, is gone" notes were simulator app processes from other workflows.
- **iPhone shots:** 16 Pro Max at Large (light and dark) and AX3; an SE at AX5 (hook, walk, the five drawn pieces, reveal, rewrite: everything wraps inside the card, no sideways scroll) and at Large; a 7.2 s clip of the reveal and the rewrite (`-InteractiveState predicted -CitationAutoplay YES`).
- **Polish from the shots:**
  - On the iPhone, a drawn slot's candidates were disabled buttons, which dimmed the model's pick at the very moment it should light up, and took its words below 4.5:1. A drawn slot's rows now draw as themselves and read as the slot's choice.
  - At AX5 on an SE the step heading broke as "Step 2 of 5 / · Year" (then "Step 2 of / 5 · Year"). It now breaks only before the slot's name.
  - On the Mac, VoiceOver's press now picks a candidate.
- **Found in the shared framework** (shared views, not this card's files):
  - On the iPhone, once a guess is locked, `PredictChips` drew every chip as a disabled button: the chosen chip's words measured about 4.2:1 on its fill, the others about 2.6:1. **Fixed in the review pass below** (a locked chip is no longer a button). It was a hard prerequisite for `enabled: true`.
  - XCUI sees each `InteractiveActionButton` and chip as a Button inside a Button with the same label, so UI tests need `firstMatch`.

### The review pass (2026-10-22)

A review of the card (content, sources, every shot and the clip) found no false fact and every number correct, and raised 18 points. Fixed here:
- **The reveal answers the guess** (§1): one last sentence per choice; a low-bar guess (the 12% author, the 8% pages) hears that a likelier piece is just as made up. Every chance it quotes is re-derived (`quotedChances`).
- **"Write it again" no longer says "the same chances"** (only step 1's are shared); its new line ties the second reference to step 1's bars, "Ambervale, R. (11%), not Quillfeather, T. (12%)". A labelled simplification in §3.
- **Wording:** "Likely isn’t the same as true."; "Guess the next piece" / "Which piece will the model draw next?" (the student guesses; the model draws); "Drawn by chance, not always the likeliest."; the finished caption names the 8%–62% range; "The model here writes from memory, with no search."; VoiceOver's revealed state says "No step decided to make it up"; the title's draw notes that it echoes the question; the takeaway is a short callback, not a second telling of Merc's example. All in §10 for the teacher.
- **A tap keeps what it changed in view, in release builds** (§5), and on the iPhone VoiceOver's focus moves to what replaced the button pressed (§1, VoiceOver).
- **The shared `PredictChips`:** a locked chip is no longer a disabled button (`InteractiveChip`'s `isLocked`). Measured at AX5: the pick's white on its fill 8.4:1 (was about 4.2:1), the others' `ink2` on theirs 8.4:1 (was about 2.6:1). It affects only cards that use `PredictChips` (this one, in this branch); `StopControl`'s chips are unchanged.
- **Docs:** §2's "realistic on purpose" reworded; C8 (Walters & Wilder 2023) as a teacher note and in checklist item 2; C3's "Sure, here’s one:" note; C5 upgraded to the primary opinion (Doc 54, pp. 1, 4, 34, read 2026-10-22); the tests' and §9's claim narrowed (the chances are asserted against the slate's values; the rest is derived).

Verification after the fixes:
- **`swift test`** (ios/Packages): 1,312 tests pass (two new: `quotedChances`, `lockedChipInk`).
- **CI lint:** 0 findings.
- **iOS:** `xcodegen generate`, then `build-for-testing` on the iPhone 16 Pro Max simulator (iOS 26.4): succeeds. Unit tests 6 of 6; `CitationThatWasntUITests` 2 of 2 (the walk-through, updated for the locked chips, and a new one at AX5); Lesson 1.1's `LessonInteractiveUITests` 1 of 1. The full UI suite was not re-run (the change touches only this card's views and the chips `PredictChips` draws).
- **The AX5 tap-through** (`testAtAccessibilitySizesEachTapKeepsWhatItChangedInView`, no `-CitationScroll`): after each guess "Next piece" is on screen, after each "Next piece" the new step's heading, then the five drawn pieces, "Show me", the reveal and the second reference, each before any swipe. Its ten screenshots are `shots/iphone16pm-AX5-tapped-*.png`: the button lands at the bottom edge and each heading at the top, the least scroll that shows them. Run on the 16 Pro Max at AX5 (this pass's only simulator), not an SE.
- **Snapshots** (`ios-unchanged-check.sh`, recording forced off): the same 23 results (11 pass, 12 already stale), the same pixels for every stale render. No record run.
- **Mac:** the Debug build succeeds; shots from the renamed copy (`….macnsia4`) at 1280×800 light and dark and 700×600: the walk at the year, the reveal (locked chips readable) and "Write it again". The founder's running app was never touched (the copy script's "running before, is gone" lines were short-lived processes from other workflows; the founder's builds kept running).
- **Shots retaken:** iPhone 16 Pro Max at Large (the walk, the reveal light and dark, the rewrite light and dark), the AX5 tap-through, and the Mac set above. The shots from before the review (the hook, the SE set, AX3, the clip) show old wording and are in `shots/stale-before-review/`; retake them at sign-off. Key shots: `docs/interactives/key-shots/citation-that-wasnt-*.jpg`. The key shots were retaken on the merged `feat/interactives-wave1` build (2026-10-22), the same way for every card: iPhone 16 Pro Max at Large, light, the card's top in its lesson beside its reveal; Mac, the top (light) beside the reveal (dark). `-iphone-revealed.jpg` and `-mac-rewritten.jpg` are this branch's own, from before the merge.

Not changed, and why:
- **The slate's own files.** They are the approved concept, outside the repo; the card's departures are in §10, as with the earlier name changes.

---

## 10. Changes from the slate (for the teacher's sign-off)

The slate (SLATE.md ★3 and slate.json) is the approved concept and lives outside the repo; as with Fernwhistle and the third title, the card's departures from it are recorded here rather than written into it. Item 10 of the checklist asks the teacher to approve or replace each.

| Where | Slate | Card | Why |
|---|---|---|---|
| The walk's heading (step 2's name) | Be the model | Guess the next piece | The student's tap is a guess the model's draw overrides ("your guess" on 2019, "picked" on 2018); "Be the model" made it unclear who was writing |
| The walk's prompt | (none given) | Which piece will the model draw next? | The same: a guess about the model's draw |
| The compact card (Mac) | (none given) | Guess each piece as a model writes a study’s reference, and see how a source that never existed gets written. | The same |
| A pick that isn't the likeliest | Drawn by chance, not always the top bar. | Drawn by chance, not always the likeliest. | The bars go at the accessibility sizes and stand as columns on the Mac, so "top bar" pointed at nothing there |
| The title's draw | (none) | The likeliest title just echoes the question. That’s why it sounds so right. | Slots 3–5 had nothing new to notice; this sets up "plausible, not true" with no new number |
| The finished caption | The finished text looks equally sure at every step. | Its chances ran from 8% to 62%, but the finished text looks equally sure at every step. | Under bars that visibly run from 8% to 62%, "equally sure" read as contradicting the screen; the contrast is now said |
| The reveal | No step did. None of these steps chose to invent it, and none of them checks that the source is real. Each piece was just a likely next piece. | The same first two sentences, then a last sentence for each guess (§1) | One fixed paragraph answered only the "decide" idea; a student who picked the 8% pages left believing the unlikely piece is the fake one (the misconception SLATE.md warns about) |
| VoiceOver's reveal line | No step decided to make it up. Each piece was a likely next piece, and no step checks that the source is real. | No step decided to make it up, and no step checks that the source is real. + the answer to the guess | The same |
| "a likely next piece" | a likely next piece | one of the likeliest next pieces (where it sits beside picks at 8% and 21%) | "Likely" beside an 8% pick read oddly; each pick was among the three likeliest shown |
| The rewrite's caption | A model draws from these chances, so the same question can get a different made-up source. | A line, "This time the first draw was Ambervale, R. (11%), not Quillfeather, T. (12%), and every piece after it followed from that start.", then "A model draws from its chances at every step, so the same question can get a different made-up source." | "These chances" claimed the second try reused every step's chances (only step 1's are the same; §3), and the second reference showed no chance at all |
| The takeaway's heading | Likely isn’t true. | Likely isn’t the same as true. | Read by a 15-year-old (and by VoiceOver) as "it probably isn't true" |
| The takeaway's line | In Mata v. Avianca (2023), lawyers who filed court cases ChatGPT had invented were fined $5,000. (the card had the guide's longer sentence) | ChatGPT wrote the fake court cases in Mata v. Avianca (2023) the same way, one likely piece at a time. | It repeated Merc's example just above the card, at the same moment as the reveal; now a short callback that ties the case to the card's mechanism (C5) |
| The third label | Writing from memory, with no search. | The model here writes from memory, with no search. | With no subject, under "Example, written for this lesson" it could read as how the lesson's author wrote the example |
