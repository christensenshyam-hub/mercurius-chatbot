# "The citation that wasn’t": the content

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
| Title | The citation that wasn’t |

### The hook (readable before any tap)

| Where | Text |
|---|---|
| The student's bubble (trailing, drawn as the student's own turn) | Can you give me a study showing that houseplants help students concentrate? |
| The example reply's label (inside the reply) | EXAMPLE REPLY, WRITTEN FOR THIS LESSON |
| The reply | Sure, here’s one: |
| The reference, before any slot is written | [author] ([year]). [title]. [journal], [volume, pages]. (the slot being written is underlined; the others are dimmed) |
| Label under the reply (kind: example) | Example, written for this lesson. Every name in this reference is invented. Writing from memory, with no search. |

The reference fills in as the student goes: "Quillfeather, T. ([year]). [title]. …", until it reads in full: **Quillfeather, T. (2018). Houseplants and attention in secondary-school classrooms. Journal of Classroom Ecology, 14(3), 211–229.** Every piece arrives in the same type as the rest, with no hedge (and no italics: the app's Lexend has no italic face).

### Be the model (one slot at a time)

| Where | Text |
|---|---|
| Heading | Be the model |
| Step strip (decoration; not at the accessibility sizes, nor where it doesn't fit) | Author · Year · Title · Journal · Pages (written slots carry a check; the slot being written is bold with a filled bar) |
| The step's heading | Step 1 of 5 · First author / Step 2 of 5 · Year / Step 3 of 5 · Title / Step 4 of 5 · Journal / Step 5 of 5 · Volume and pages |
| Prompt (until the guess) | Pick the piece you think gets written next. |
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
| Extra line, when the pick isn't the top bar (the walk: only the year) | Drawn by chance, not always the top bar. |
| Button (slots 1–4) | Next piece |
| Button (slot 5) | See the finished reference |

There is no score, and nothing says right or wrong.

### The finished reference

| Where | Text |
|---|---|
| Heading | The five pieces it drew |
| Five rows | Author · ✓ Quillfeather, T. · 12% / Year · ✓ 2018 · 21% / Title · ✓ Houseplants and attention in secondary-school classrooms · 62% / Journal · ✓ Journal of Classroom Ecology · 41% / Pages · ✓ 14(3), 211–229 · 8% (each with its bar) |
| Label | (the illustrative label again, beside these bars) |
| Caption | The finished text looks equally sure at every step. |

On the Mac the night-sky reply glows once as the fifth piece lands (not under Reduce Motion, Increase Contrast or Reduce Transparency).

### Predict, then reveal

| Where | Text |
|---|---|
| The question (a header) | This study doesn’t exist. At which step did the model decide to make it up? |
| Chips (one tap locks; it can't be changed) | The author / The journal / The page numbers / No step did |
| Button, once locked | Show me |
| Reveal, "You guessed" (not in spoiled mode) | e.g. The author |
| Reveal, "What happened" | No step did. None of these steps chose to invent it, and none of them checks that the source is real. Each piece was just a likely next piece. |
| Under the reveal | There may be real research on this question. This reference isn’t part of it. |

At the reveal all five rows of drawn pieces light up at once (a wash and an accent edge; under Increase Contrast a solid 2 pt edge instead of a glow).

### Write it again

| Where | Text |
|---|---|
| Button (after the reveal, once) | Write it again |
| A second example reply | The same question, asked again · EXAMPLE REPLY, WRITTEN FOR THIS LESSON · Sure, here’s one: · **Ambervale, R. (2019). Indoor plants and student focus: a classroom study. Indoor Learning Review, 9(2), 45–61.** (written one piece after another; all at once under Reduce Motion) |
| Caption | A model draws from these chances, so the same question can get a different made-up source. |

### The takeaway (shown with the reveal)

| Where | Text |
|---|---|
| Heading | Likely isn’t true. |
| Line | In Mata v. Avianca (2023), lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000. |

Then the lesson's own check continues below the card.

### Spoiled mode

The registry gives this card no spoiler terms (the hook doesn't give away a mechanism question), so a student never sees spoiled mode unless that changes. It exists, as every card's does: no step question; the reveal (without "You guessed") comes with "See the finished reference"; "Write it again" follows. DEBUG's `-InteractiveState spoiled` shows it.

### The compact card (Mac only: narrower than 440 pt)

| Where | Text |
|---|---|
| Eyebrow, title | INTERACTIVE · The citation that wasn’t |
| Line | Be the model: write a study’s reference one likely piece at a time, and see how a source that never existed gets written. |
| Button | Try it |

### What VoiceOver says

| Element | Spoken |
|---|---|
| The card's title (a header; its value is the state in one sentence) | Interactive: The citation that wasn’t. Value, e.g.: "Step 2 of 5, Year: the model drew 2018, at 21 percent, bar 2 of 3." |
| The student's bubble | A student asks: Can you give me a study showing that houseplants help students concentrate? |
| The example reply (one element) | Example reply, written for this lesson. Sure, here’s one: Quillfeather, T., 2018. Not written yet: title, journal, volume and pages. |
| The step's heading (a header) | Step 2 of 5, Year. Written: First author. |
| Each slot (a group named for the slot) holding three choices | First author. Quillfeather, T., 12 percent, illustrative, 1 of 3. Button. Hint: Pick the piece you think gets written next. |
| A choice after the draw | value "picked", "your guess", or "your guess, picked"; the pick is also "selected" |
| Pages are said in words | Volume and pages. volume 14, issue 3, pages 211 to 229, 8 percent, illustrative, 1 of 3. |
| Announced after a guess | The model drew 2018 this time. Drawn by chance, not always the top bar. (after the fifth: "… The reference is finished: Quillfeather, T., 2018. Houseplants and attention in secondary-school classrooms. Journal of Classroom Ecology, volume 14, issue 3, pages 211 to 229.") |
| Announced on Next piece | Step 3 of 5 · Title |
| Announced on See the finished reference | The finished reference: … The finished text looks equally sure at every step. |
| Each drawn-piece row | Year: 2018, 21 percent, picked. |
| The step question | a header, then four buttons; once locked, "Your guess, locked in" |
| Announced on Show me | You guessed The author. No step decided to make it up. Each piece was a likely next piece, and no step checks that the source is real. |
| The reveal (one element) | You guessed The author. No step did. None of these steps chose to invent it, … |
| Write it again | Write it again. Hint: Draws another reference from the same chances |
| Announced on Write it again | Written again: Ambervale, R., 2019. Indoor plants and student focus: a classroom study. Indoor Learning Review, volume 9, issue 2, pages 45 to 61. A model draws from these chances, so the same question can get a different made-up source. |
| The takeaway (one element) | Likely isn’t true. In Mata v. Avianca (2023), … $5,000. |

---

## 2. Every number, and where it comes from

| Number(s) on the card | Source or derivation | Checked by |
|---|---|---|
| The fifteen chances (12, 11, 9 · 24, 21, 19 · 62, 14, 8 · 41, 22, 10 · 8, 7, 7 %) | **Authored, illustrative** (slate.json `data.slots`, unchanged). Not from a real model, and labelled so beside every set of bars and in every VoiceOver line that says one. Their shape is realistic on purpose: flat for a name (no name is much likelier than another), peaked for a title that follows from the question | `CitationContentTests.slots` (each slot's three are listed top first, positive, and leave room for "+ many more") |
| "Drawn by chance, not always the top bar" (the year) | Derived: the walk's pick at the year is candidate 2, ranked 2nd of 3 by its chance; every other pick on the walk is the top bar | `ranks` (`notTopSlots(path: 0) == [.year]`) |
| The second path's four lower bars | Derived the same way (the author, title, journal and pages are 2nd bars; 9(2) and 22(1) tie at 7%, and the order shown breaks the tie) | `ranks` |
| Step 1–5 of 5, "1 of 3", "bar 2 of 3" | Counts of `CitationSlot` and of each slot's candidates | `steps`, `voiceOver` |
| 2018, 2019, 2020; 14(3), 211–229; 9(2), 45–61; 22(1), 102–118 | **Authored parts of the invented references.** They are not facts about anything | `everyNumberAccountedFor` (every number in every line is one of these, a chance, a count, or the guide's two numbers) |
| 2023, $5,000 | **The lesson guide** (`CURRICULUM_PROMPT`, U1L3 Key examples, in PR #44's `server.js`; fact-check row 13): "Mata v. Avianca (2023): lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000." | `guideNumbers` (the takeaway's only numbers are the guide line's) |

No fabrication rate, no calibration figure and no probability of the whole reference is shown (SLATE.md accuracy notes). The card never multiplies the chances.

---

## 3. Every factual claim, and its source

| # | Claim (as the card makes it) | Status | Source |
|---|---|---|---|
| C1 | A model writes a reply one piece at a time, each a likely next piece given everything before it; "real models go one small piece (token) at a time" (the card shows a few words at a time, labelled). | True; **read** 2026-10-21. The guide's U1L1 As-of note: "models still write one token at a time". | 3Blue1Brown, *But what is a GPT?* (Deep Learning ch. 5): to generate longer text, "take a random sample from the distribution it just generated, then run it all again"; that repeated prediction and sampling is what happens in ChatGPT. <https://www.3blue1brown.com/lessons/gpt> |
| C2 | Models usually **draw** from these chances rather than always taking the top piece ("Drawn by chance, not always the top bar"; "A model draws from these chances, so the same question can get a different made-up source"). | True for chat models at their usual settings; a temperature of 0 (greedy decoding) would always take the top piece. **New fact row** (BUILD_PLAN.md §4.2: "Models usually sample from next-token chances rather than always taking the top one"), to be added to `curriculum-factcheck.md` and verified by someone other than its author. Not a statistic, so no guide line is needed. It also corrects `ut1_q2`'s explanation ("predicts the most likely next token"), which the fact-check already flags as a simplification. | 3Blue1Brown (above, **read** 2026-10-21): the next piece is a random sample from the distribution; a temperature T in the softmax sets how much the largest values dominate, and at T = 0 "all the weight goes to the maximum value". · Cho et al. 2024, *Transformer Explainer* (arXiv 2408.04619): the abstract (**abstract** read 2026-10-21) describes "observing next-token predictions in real time" and adjusting hyperparameters; its temperature and sampling controls are in the tool itself, not re-checked here. <https://arxiv.org/abs/2408.04619> |
| C3 | No step decides to make the reference up, and none of these steps checks that a source is real; each piece was just a likely next piece. | True of next-token writing from memory (the card's scenario: "Writing from memory, with no search"). It is the guide's own teach point: "next-token prediction optimizes for plausibility, not truth". The card says "none of **these** steps checks", not "nothing inside the model could stop it": see the teacher note. | Guide U1L3 Teach line. · **Teacher note only (not on the card):** Anthropic, *On the Biology of a Large Language Model* (2025; re-read 2026-10-21) describes default circuits that push the model to decline, which "known entity" features suppress so it can answer; "at least some hallucinations can be attributed to a 'misfire' of this inhibitory circuit". A mechanism behind *whether* a model answers, not a decision to lie. <https://transformer-circuits.pub/2025/attribution-graphs/biology.html> |
| C4 | "Writing from memory, with no search." | A scenario label, true of the example. It's there because chatbots now can search (guide row 12), and a student may know that. | Guide U1L2 As-of note; fact-check row 12. |
| C5 | In Mata v. Avianca (2023), lawyers filed a brief citing court cases ChatGPT had invented, and a federal judge fined them and their firm $5,000. | True; the guide's sentence, word for word but for "In" (row 13, High). Spot-checked 2026-10-21 (**secondary**): Wikipedia says Judge Castel "ordered the plaintiff's attorneys to pay a $5,000 fine" (its body and infobox disagree on May vs. June 22, 2023; the order is dated June 22); the opinion's headnotes (678 F. Supp. 3d 443), seen only in search results, hold the firm jointly and severally liable. The guide's year (2023) and amount hold either way. | Judge Castel, S.D.N.Y., 2023-06-22 (Steptoe SDNY blog, row 13's source; it refused a fetch this session). <https://www.steptoe.com/en/news-publications/sdny-blog/judge-castel-sanctions-lawyers-who-submitted-fake-cases-generated-by-chatgpt.html> · <https://en.wikipedia.org/wiki/Mata_v._Avianca,_Inc.> |
| C6 | "There may be real research on this question. This reference isn’t part of it." | True: there is real research on plants in classrooms (e.g. a 2020 *Building and Environment* paper of three field experiments, one in a secondary school, found up in the name search below). The card cites none of it on purpose; it only refuses to call the topic unstudied. | Van den Bogerd et al., "Greening the classroom: three field experiments on the effects of indoor nature on students' attention, well-being, and perceived environmental quality", *Building and Environment* 171 (2020); **abstract** seen 2026-10-21 (VU Amsterdam research portal). <https://research.vu.nl/en/publications/greening-the-classroom-three-field-experiments-on-the-effects-of-/> |
| C7 | The example reply, its reference and every name in it are invented for the lesson. | True: see §4. | — |

**What the card avoids saying, on purpose:**
- that a low chance marks the made-up part (the flat author bars are not "where it went wrong"; the peaked title is just as invented), and it never multiplies the chances into a probability for the whole reference;
- that the model chose, wanted, knew or lied (intent words appear only in the step question, which the reveal refutes);
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
- **Exercise clash:** low. The exercise asks the student to flag claims in a paragraph and say how to check them; the card shows how a fake gets written, and never how to check one.

---

## 6. The VoiceOver walk-through (to do once on a device)

1. Swipe to the card: "Interactive: The citation that wasn’t, heading", with the state ("Step 1 of 5, First author: Pick the piece you think gets written next.").
2. The student's bubble, then the example reply ("… Not written yet: first author, year, title, journal, volume and pages."), then the label.
3. "Be the model, heading". "Step 1 of 5, First author, heading".
4. The three choices, each "First author. … percent, illustrative, 1 of 3, button". Double-tap one: hear "The model drew Quillfeather, T. this time …".
5. "Next piece" → "Step 2 of 5 · Year". Pick 2019: hear "The model drew 2018 this time. Drawn by chance, not always the top bar."
6. Through the fifth slot; "See the finished reference": hear the whole reference and "The finished text looks equally sure at every step."
7. The five rows, then the question (a heading) and its four chips. Pick one; "Show me": hear "You guessed …. No step decided to make it up …".
8. "Write it again": hear the second reference and the caption. Then the takeaway, then the lesson's check, which still answers by double-tap.

## 7. The Mac's keys

- Tab reaches each candidate; ←/→ (and ↑/↓ while the lesson's check isn't waiting) move between a slot's candidates while one has focus; Space or Return picks.
- After a pick from the keyboard, focus moves to "Next piece"; after it, to the next slot's first candidate; after the fifth, to the first step chip, then "Show me", then "Write it again". A click picks without keeping the keyboard.
- While a card control has focus it holds Return, so the lesson's check never locks in from it. A–D and 1–4 still answer the check, and a pick there takes the keyboard back.
- Below 440 pt the card starts compact; "Try it" (Tab, Space or Return) opens it, and the keyboard goes to the first candidate.

---

## 8. Teacher checklist (BUILD_PLAN.md §4.5)

Walk the card on an iPhone and on the Mac, inside a real Lesson 1.3 run.

1. [ ] The aha lands in about 75–90 s, without the tutor's help: no step "decided"; likely pieces add up to a source that never existed.
2. [ ] Every label is visible and understood: "Example, written for this lesson", "Every name … is invented", "illustrative, not from a real model", "a few words at a time … (token)", "Writing from memory, with no search".
3. [ ] 9th-grade language; nothing reads as live AI or as Merc's own answer.
4. [ ] The tutor's reply above the card didn't answer the step question in that run (it has no spoiler terms; note it here if it did).
5. [ ] **Exercise clash:** do the lesson's exercise right after the card; the card didn't answer it.
6. [ ] **Ethics for minors:** no real person is named except in the guide's Mata v. Avianca line; no real journal or researcher is called fake.
7. [ ] **Accessibility:** a VoiceOver-only pass (§6); AX5 on an iPhone SE; keyboard-only on the Mac (§7); Reduce Motion; Increase Contrast.
8. [ ] **Names:** an ISSN Portal and a Google Scholar search, by hand, of the three journals and three titles (§4); any match is replaced.
9. [ ] **Fact row:** C2's new row ("models usually sample…") is in `curriculum-factcheck.md`, verified by someone other than its author.

**Sign-off:** _not yet signed_. (Name, date, device and OS, and the run's lesson transcript id when signed. Then, and with the founder's OK, a last commit sets `enabled: true`.)

---

## 9. Verification (2026-10-21)

See the PR notes and `shots/` (kept out of git). Summary in the build log of this branch's commit.
