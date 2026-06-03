# Mercurius — App Store listing pack

Everything to paste into **App Store Connect → your app → 1.0.0 version**. Fill
the `[BRACKETS]` (support email, Terms URL) before submitting.

---

## 1. Metadata (copy-paste)

**App Name** (≤30): `Mercurius: AI Literacy Tutor`

**Subtitle** (≤30): `Learn to think with AI`

**Promotional Text** (≤170, editable anytime without review):
```
New: share a photo and Mercurius can see it. An AI tutor that guides your thinking with questions, helps you check AI claims, and builds real AI literacy.
```

**Keywords** (≤100, comma-separated, no trademarks):
```
AI literacy,AI tutor,learn AI,critical thinking,Socratic,prompting,AI ethics,study,students
```

**Description** (≤4000):
```
Mercurius is an AI literacy tutor that helps you understand and use AI — clearly, critically, and responsibly. It's built on a simple idea: AI should help you think, not think for you.

Instead of handing you answers, Mercurius guides you. Ask a question and it responds Socratically — with questions of its own that build your understanding — until you've genuinely grasped the idea. Only then does it unlock direct explanations.

WHAT YOU CAN DO
• Learn how AI actually works — models, prompting, bias, hallucinations, and how to tell good output from bad.
• Practice four ways of thinking: Socratic (guided questions), Discussion, Debate (argue multiple sides), and Direct.
• Share a photo — Mercurius can now see images you send and discuss them with you.
• Check your understanding with auto-generated quizzes and a session report card.
• Follow a curriculum of bite-sized AI literacy lessons.

WHO IT'S FOR
Students, curious learners, and anyone who wants to use AI well rather than passively. Trustworthy enough for educators, approachable enough for a first-time user.

HOW IT'S DIFFERENT
Mercurius isn't a homework-completion engine or a generic chatbot wrapper. Its comprehension gate, verification focus, and Socratic style are built to make you a sharper, more independent thinker — the opposite of outsourcing your reasoning.

"Guided, not given."

Mercurius is in active development — we'd love your feedback.
```

**What's New** (version 1.0 release notes):
```
Welcome to Mercurius 1.0 — an AI literacy tutor that helps you think WITH AI, not outsource to it.

This release: Socratic, Discussion, Debate, and Direct modes; auto-generated quizzes and a session report card; an AI literacy curriculum; and — new — the ability to share a photo and have Mercurius see and discuss it.
```

**URLs**
- Support URL: `https://trymercurius.com` (or a dedicated /support page)
- Marketing URL: `https://trymercurius.com`
- Privacy Policy URL: `https://trymercurius.com/privacy`

**Copyright**: `2026 [your name / org]`

---

## 2. App Review notes (paste into "App Review Information → Notes")

```
Mercurius is an AI literacy tutor for students. No account or login is required — open the app and start chatting; an anonymous session id is generated on-device.

The app talks to our backend at https://mercurius-chatbot-production.up.railway.app, which calls the Anthropic Claude API to generate tutoring responses. A network connection is required.

TO TEST:
1. Open the app, tap a starter prompt or type a question (e.g. "What is machine learning?"). Mercurius guides you Socratically.
2. Photo feature: tap the photo button to the left of the message box, choose an image, and ask about it — the tutor can see and discuss it.

SAFETY / USER-GENERATED CONTENT (Guideline 1.2):
- The AI is constrained by a system prompt to AI-literacy tutoring and relies on Anthropic's built-in safety filtering.
- Users can report any AI response: long-press the message → "Report response", which sends it to us for review.
- There is no user-to-user content.
- Support contact: [YOUR SUPPORT EMAIL]
```

**Sign-in required:** No. **Demo account:** not needed (anonymous sessions).

---

## 3. App Privacy (the nutrition label questionnaire)

Matches `PrivacyInfo.xcprivacy`. Declare:

| Data type | Collected? | Linked to identity? | Used for tracking? | Purpose |
|---|---|---|---|---|
| User Content (chat messages, shared photos) | Yes | **No** | **No** | App Functionality |
| Identifiers (random on-device session id) | Yes | **No** | **No** | App Functionality |
| Everything else (name, email, location, contacts, financial, browsing) | **No** | — | — | — |

- **Tracking:** No. (No third-party analytics/ad SDKs.)
- Attach the Privacy Policy URL above.

---

## 4. Age Rating

Answer the questionnaire honestly. Because the app surfaces **unrestricted AI-
generated text**, expect a **12+ (or 17+)** rating — not 4+. If the questionnaire
shows AI-chatbot / "unrestricted web content" questions (added 2024+), answer
them truthfully. **Do NOT** opt into the **Kids Category** (it triggers COPPA +
strict rules that don't fit an AI chatbot).

---

## 5. Terms of Use / EULA

- Apple's **standard EULA** applies by default and is sufficient. Optionally
  provide a custom Terms of Use URL.
- The app now links to **Settings → About → Terms of Use** →
  `https://trymercurius.com/terms`. **Publish that page before submitting** (a
  short, standard Terms-of-Use template is fine), or repoint the link to your
  privacy page if you'd rather not.

---

## 6. Screenshots

**Required device sizes** (capture on the matching Simulator, then ⌘S — saves at
exact resolution):

| Class | Device (Simulator) | Portrait px |
|---|---|---|
| iPhone 6.9" | iPhone 16 Pro Max | 1320 × 2868 |
| iPad 13"  | iPad Pro 13-inch (M4) | 2064 × 2752 |

iPad screenshots are **required** because the app supports iPad
(`TARGETED_DEVICE_FAMILY 1,2`). Provide 3–5 per class (up to 10).

**Shot list** (order matters — the first 2–3 show in search results):

1. **Chat, mid-Socratic-exchange** — the tutor asking a guiding question.
   Caption: *"A tutor that asks — so you actually learn."*
2. **Photo in chat** — a shared image + Mercurius discussing it.
   Caption: *"Share a photo. It sees and explains."*
3. **Mode selector** — Socratic / Discussion / Debate / Direct.
   Caption: *"Four ways to think with AI."*
4. **Quiz or Report Card** — the learning check.
   Caption: *"See what you actually learned."*
5. **Curriculum or the comprehension-gate unlock.**
   Caption: *"Earn your way to direct answers."*

Tip: add the caption text as an overlay band (most App Store shots do); keep the
brand navy/violet. Keep real, non-staged content in the bubbles.

---

## 7. Submit sequence (recap)

1. Verify build on a real device (photo/HEIC path).
2. Fill all of the above + attach the build.
3. Submit for Review → choose **Phased Release (7 days)**.
4. If rejected, it's almost certainly Guideline 1.2 (AI content) — point them to
   the in-app "Report response" + the review notes above.
