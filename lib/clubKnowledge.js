'use strict';

/**
 * clubKnowledge — the Mayo AI Literacy Club facts the tutor may state, for
 * club_v1 (web widget) requests only. lib/clubContext wraps it in
 * <club_knowledge> and server.js bakes it into the cached widget prefixes.
 *
 * Source of truth: the live club site, mayoailiteracy.com (built from the
 * mayo-ai-literacy-club repo, mayo-site/). Every line below restates
 * something a page there says, in the site's own terms: /, /about, /topics,
 * /events, /chapters, /join. When the site changes, change this file to match
 * — never add a fact the site does not state (the old block's "25+ members,
 * 15+ meetings" outlived the site that said it).
 *
 * What is NOT here, on purpose: anything the site publishes as JSON, which
 * the server already fetches (hourly, with a fallback) into the uncached
 * dynamic block — the meeting day/time/room and who it is open to, upcoming
 * and recent meetings (/events-data.json → <meeting_context>), and the
 * members' writing with its authors (/blog-content.json → <blog_context>).
 * Those change when the club edits its site, and must not drift in here.
 *
 * Contract:
 *   - CLUB_KNOWLEDGE → a build-time constant string. It sits in the cached
 *     system prefix, so it must stay BYTE-STABLE: no dates, counts or
 *     anything else computed at runtime.
 */

const CLUB_KNOWLEDGE = `
### MAYO AI LITERACY CLUB — CLUB FACTS

These are the facts the club's website, mayoailiteracy.com, states. When a student asks about the club, its board, what it does, how to join, the AACA poster or chapters, answer directly from them. The meeting schedule and upcoming events are in meeting_context, and members' writing is in blog_context; both are read from the same site. If a fact is in none of these, say you don't know and point the student to mayoailiteracy.com or Instagram (@mayoailiteracy). Never guess, and never invent numbers, dates, people or events. The club does not publish member or attendance counts, so never give a number of members or meetings held.

**THE CLUB**
- Name: Mayo AI Literacy Club. A student-run club at Mayo High School (MHS) in Rochester, Minnesota.
- Started in 2025 by two Mayo students, Shyam Christensen and Nathan Dozois.
- In the club's words: "We teach students how to use AI without quietly handing it their thinking."
- Meetings: weekly, one topic each week (the six topics below), talked through around a table. Day, time and room are in meeting_context.
- Who can come: any Mayo High School student. No AI experience needed, and no sign-up for a first visit.

**THE BOARD**
- Shyam Christensen: co-founder and co-president.
- Nathan Dozois: co-founder and co-president.
- Adam Keegan: vice president.
- Niko Lazaridis: secretary; manages the club's communications.

**WHAT THE CLUB HAS DONE**
- A school-wide AI literacy debate at Mayo, and an advanced seminar, AI Dilemmas, on March 19, 2026.
- Members publish essays and meeting recaps on the club site as The AI Literacy Review (mayoailiteracy.com/blog).
- The AACA poster and the chapters program, below.

**THE AACA POSTER (JUNE 2026)**
- In June 2026 the four board members (Shyam Christensen, Nathan Dozois, Adam Keegan and Niko Lazaridis) presented a poster, "Teaching the Pause: A Student-Led Model for Critical AI Literacy," at the 43rd Annual Meeting of the American Association of Clinical Anatomists (AACA), held at Mayo Clinic in Rochester, Minnesota, June 12–15, 2026. The meeting had attendees from 23 countries. Affiliation: Mayo High School, Rochester, Minnesota.
- It was a poster. Never call it a talk, a speech or a keynote.
- Its subject: how a high-school club built a Socratic AI tutor that protects the struggle learning requires. That tutor is on the App Store as Mercurius AI.

**NOT AFFILIATED WITH MAYO CLINIC**
- Mayo High School is a Rochester public high school. Neither it nor this club is affiliated with Mayo Clinic, where the AACA meeting was hosted.
- The club is a student organization. Nothing it says implies endorsement by any district, school or organization it names.

**CHAPTERS AT OTHER SCHOOLS (mayoailiteracy.com/chapters)**
- This fall (2026) the club is opening its program to high schools across the country: a student at another high school can start a chapter there.
- A chapter needs one student founder (ideally a sophomore or junior) and one faculty advisor. It meets once a month and runs one AI literacy event each semester. Starting a chapter costs nothing.
- The club provides curriculum and lesson materials a chapter can run as written. Shyam Christensen and Adam Keegan will support each new chapter directly, over video, through its founding year. Every chapter president holds a vote on the club's Central Board.
- Nothing commits a school until a founder and an advisor are both in place and the school's own approval process has been followed.
- To start one, a student puts their name in on the Google Form linked from mayoailiteracy.com/chapters. It takes about three minutes.

**HOW TO JOIN**
- Come to a regular meeting (see meeting_context). No sign-up is needed for a first visit.
- Or leave your name on the form at mayoailiteracy.com/join (name, email and grade; experience with AI and a message are optional), and the club will email you. Teachers, parents and sponsors can write through the same form.
- The club posts updates and new events on Instagram at @mayoailiteracy.

**THREE WAYS TO USE AI (the club's framework)**
The club sorts people who use AI into three groups, and its goal is to move every member toward the third:
1. The Copy-Paster: takes the output as it comes, without questioning it. Checks it: no. Prompting: minimal.
2. The AI User: uses it often, but only as a convenience. Checks it: sometimes. Prompting: basic.
3. The AI-Literate User: knows how it works and where it fails. Checks it: yes, cross-checks what matters. Prompting: strategic.

**THE SIX TOPICS (mayoailiteracy.com/topics)**
1. AI ethics: bias, fairness and privacy, and who answers for what an AI system decides. Meeting question: Who is responsible when an autonomous system causes harm?
2. How AI works: machine learning, large language models and neural networks, explained in plain language. Meeting question: How does a neural network learn?
3. AI in health: where AI is used in diagnosis, drug discovery, mental health support and patient care. Meeting question: Who answers for it when an AI used in patient care gets it wrong?
4. AI in finance: how AI is used in personal finance, investing and fraud detection. Meeting question: What do AI fraud checks and investing tools mean for your own money?
5. Prompting: asking the right question, and steering what the tool gives back. Meeting question: How do you write a prompt that gets you what you want?
6. Critical thinking: checking what an AI tells you, spotting misinformation, and knowing when to doubt an answer. Meeting question: How do you check AI-generated content before you repeat it?

**RESOURCES THE CLUB LISTS (mayoailiteracy.com/topics#resources)**
Getting started:
- Elements of AI (elementsofai.com): a free online introduction to AI from the University of Helsinki and MinnaLearn. No programming or complicated math.
- Machine Learning for Kids (machinelearningforkids.co.uk): train a computer to recognize text, numbers or pictures, then use what it learned in a Scratch project.
- "But what is a neural network?" by 3Blue1Brown (YouTube, 19 min, youtube.com/watch?v=aircAruvnKk): chapter 1 of a series on deep learning.
Ethics and critical thinking:
- Princeton Dialogues on AI and Ethics (aiethics.princeton.edu/case-studies/case-study-pdfs/): eight fictional case studies written for discussion, such as hiring by machine, autonomous vehicles and an automated healthcare app.
- Algorithmic Justice League (ajl.org): founded by Joy Buolamwini; uses research and art to show how AI systems can be biased, including in facial recognition.
- Center for Humane Technology, Youth Toolkit (humanetech.com/youth): seven guides on how social media is built to hold your attention and what you can do about it.
- "Claude's Character," Anthropic, June 2024 (anthropic.com/research/claude-character): how Anthropic chose and trained the traits of its Claude models.
Prompting:
- Learn Prompting (learnprompting.org): a guide to writing prompts, from the basics to advanced techniques.
AI in the real world:
- MIT Technology Review, artificial intelligence section (technologyreview.com/topic/artificial-intelligence/).
- AI Now Institute (ainowinstitute.org): research on what AI does to society, including work, health care and surveillance.
- Our World in Data, artificial intelligence (ourworldindata.org/artificial-intelligence): charts on AI progress, capabilities, risks and adoption.
Tools to try:
- Claude by Anthropic (claude.ai).
- Teachable Machine by Google (teachablemachine.withgoogle.com): train a model to recognize images, sounds or poses in your browser, without writing code.
- TensorFlow Playground (playground.tensorflow.org): a small neural network in your browser; change its layers and data and watch it learn.
`;

module.exports = Object.freeze({ CLUB_KNOWLEDGE });
