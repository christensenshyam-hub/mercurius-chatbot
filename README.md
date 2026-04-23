# Mercurius Ⅰ — AI Literacy Tutoring Chatbot

[![iOS](https://github.com/christensenshyam-hub/mercurius-chatbot/actions/workflows/ios.yml/badge.svg)](https://github.com/christensenshyam-hub/mercurius-chatbot/actions/workflows/ios.yml)
[![Server](https://github.com/christensenshyam-hub/mercurius-chatbot/actions/workflows/server.yml/badge.svg)](https://github.com/christensenshyam-hub/mercurius-chatbot/actions/workflows/server.yml)

A full-stack chatbot tutor designed to help high school students think critically about AI systems — including the one they're talking to. Built with Express, the Anthropic Claude API, and a self-contained vanilla JS/CSS widget that embeds on any website. A native iOS companion app lives under `ios/`.

---

## Pedagogical Philosophy

Most educational AI tools are optimized for efficiency: give the student the answer quickly. Mercurius Ⅰ does the opposite.

Its design is rooted in three principles:

**1. Critical thinking over answer delivery.**
Mercurius Ⅰ uses the Socratic method by default — it asks questions back before answering, forcing students to activate prior knowledge. The goal is not for students to learn *from* AI, but to learn *about* AI while using it.

**2. Radical transparency about AI limitations.**
Every interaction is an opportunity to model epistemic humility. Mercurius Ⅰ explicitly signals its uncertainty, narrates its reasoning process, and regularly reminds students that fluency is not the same as accuracy. The confidence meter makes this visible at a glance.

**3. Resistance to cognitive outsourcing.**
Students who ask Mercurius Ⅰ to write their essay or solve their problem are redirected — not rudely, but firmly. The tutor's job is to identify what's hard and work on that, not to remove friction that serves learning.

These aren't just product features. They reflect a position: that AI deployed in educational settings without metacognitive scaffolding trains students to be passive consumers of machine output. Mercurius Ⅰ is designed to push back against that tendency.

---

## Getting an Anthropic API Key

1. Go to [console.anthropic.com](https://console.anthropic.com) and create an account.
2. Navigate to **API Keys** in the left sidebar.
3. Click **Create Key**, give it a name (e.g. "mercurius-dev"), and copy the key — it will only be shown once.
4. Store it securely. You will add it to your `.env` file in the next step.

Anthropic offers a free tier with rate limits sufficient for development and small-scale classroom use.

---

## Local Development Setup

### Prerequisites

- Node.js 18 or later
- npm 9 or later
- An Anthropic API key (see above)

### Steps

```bash
# 1. Navigate to the project directory
cd /path/to/mercurius-chatbot

# 2. Install dependencies
npm install

# 3. Create your environment file
cp .env.example .env

# 4. Edit .env and add your API key
#    Open .env in any editor and set:
#    ANTHROPIC_API_KEY=sk-ant-...
#    ALLOWED_ORIGIN=http://localhost:3000
#    PORT=3000

# 5. Start the development server (with auto-reload)
npm run dev

# Or start without auto-reload:
npm start
```

6. Open [http://localhost:3000](http://localhost:3000) in your browser.
7. Click the gold button in the bottom-right corner to open the chat widget.

### Environment Variables

| Variable           | Required | Default               | Description                                      |
|--------------------|----------|-----------------------|--------------------------------------------------|
| `ANTHROPIC_API_KEY`| Yes      | —                     | Your Anthropic API key                           |
| `ALLOWED_ORIGIN`   | No       | All origins (dev)     | CORS origin(s), comma-separated for multiple     |
| `PORT`             | No       | `3000`                | Port the server listens on                       |

---

## Deploying to Railway

Railway is a straightforward platform for deploying Node.js applications with minimal configuration.

### Step-by-step

1. **Create a Railway account** at [railway.app](https://railway.app) if you don't have one.

2. **Push your code to GitHub** (Railway deploys from a git repository):
   ```bash
   git init
   git add .
   git commit -m "Initial commit — Mercurius I"
   # Create a new repo on GitHub, then:
   git remote add origin https://github.com/YOUR_USERNAME/mercurius-chatbot.git
   git push -u origin main
   ```

3. **Create a new Railway project:**
   - Click **New Project** in the Railway dashboard.
   - Select **Deploy from GitHub repo**.
   - Authorize Railway and select your repository.

4. **Add environment variables:**
   - In your Railway project, go to the **Variables** tab.
   - Add the following:
     - `ANTHROPIC_API_KEY` = your API key
     - `ALLOWED_ORIGIN` = your production domain (e.g. `https://myschool.com`)
     - `PORT` = `3000` (Railway will also set this automatically)

5. **Deploy:**
   - Railway automatically detects the `npm start` script and deploys.
   - Wait for the build to complete (usually under 2 minutes).
   - Railway assigns a public URL like `https://mercurius-chatbot-production.up.railway.app`.

6. **Update your widget embed** to point at the Railway URL (see Embedding section below).

### Notes on Railway

- Railway's free tier provides 500 hours/month of runtime — enough for a classroom project.
- Railway automatically restarts the server if it crashes.
- To redeploy, simply push to the `main` branch on GitHub.

---

## Embedding on Any Website

Once the server is deployed, embed the widget on any webpage with two lines:

```html
<!-- Add this anywhere in your HTML, just before </body> -->
<script>
  window.MercuriusConfig = {
    apiEndpoint: 'https://your-railway-url.up.railway.app/api/chat'
  };
</script>
<link rel="stylesheet" href="https://your-railway-url.up.railway.app/widget.css">
<script src="https://your-railway-url.up.railway.app/widget.js"></script>
```

Replace `https://your-railway-url.up.railway.app` with your actual deployment URL.

The widget is fully self-contained: it injects its own DOM, generates its own session ID, and makes API calls directly to your backend. It will not conflict with existing styles on your page because all CSS classes are namespaced with `merc-`.

**Important:** Make sure `ALLOWED_ORIGIN` on your server includes the domain of the page embedding the widget, or browsers will block the API calls due to CORS policy.

---

## Customizing Colors

All colors are controlled through CSS custom properties defined in `widget.css`. Override them anywhere on your page after loading `widget.css`:

```css
:root {
  --merc-navy:       #0f172a;   /* Header, toggle button, user message background */
  --merc-gold:       #c97d10;   /* Primary accent — headings, borders, tags */
  --merc-gold-light: #e8960f;   /* Hover states, lighter accent use */
  --merc-slate:      #f1f5f9;   /* Bot message background, input background */
  --merc-white:      #ffffff;   /* Panel background */
  --merc-text:       #1e293b;   /* Primary text color */
  --merc-muted:      #64748b;   /* Secondary text, timestamps */
  --merc-radius:     16px;      /* Panel corner rounding */
  --merc-shadow:     0 20px 60px rgba(0,0,0,0.18); /* Panel drop shadow */
}
```

Example — switching to a green academic theme:
```css
:root {
  --merc-navy: #1a2e1a;
  --merc-gold: #3a7d44;
  --merc-gold-light: #4a9d56;
}
```

---

## Special UI Features — What They Are and Why They Exist

### Confidence Meter

**What it is:** A small colored bar below each bot message that shows an estimated confidence percentage. Green = high confidence (≥70%), yellow = moderate (45–69%), red = low (<45%), gray = unverified.

**Why it exists:** One of the most dangerous properties of large language models is that they express uncertain and incorrect claims with the same fluent, confident tone as accurate ones. Students who don't understand this tend to treat AI output as authoritative. The confidence meter makes the AI's self-reported uncertainty visible — and importantly, it teaches students that even "high confidence" AI responses can be wrong, because the meter reflects the AI's stated uncertainty, not ground truth accuracy.

---

### Unpack This (&#128269;)

**What it is:** A ghost button below each bot message. Clicking it sends a hidden prompt asking Mercurius Ⅰ to narrate its own reasoning: what assumptions it made, how it arrived at the answer, and what it might be getting wrong.

**Why it exists:** Metacognition about AI reasoning is a core literacy skill. Students need to understand that AI doesn't "think" — it predicts likely-sounding text based on patterns in training data. By making the reasoning process visible, this feature helps students evaluate whether the logic behind an answer is sound, not just whether the answer sounds reasonable.

---

### Flag (&#128681;)

**What it is:** A ghost button that sends a hidden prompt asking Mercurius Ⅰ to identify what perspectives, groups, or contexts its previous response might have overlooked or disadvantaged.

**Why it exists:** AI systems trained on large internet corpora inherit the demographic biases of who writes on the internet — which skews toward English-speaking, Western, educated, and relatively affluent perspectives. Students from underrepresented communities are often invisibilized by AI responses that present one cultural frame as universal. The Flag feature builds the habit of asking "whose perspective is centered here?" — a critical media literacy skill that extends well beyond AI.

---

### Reflection Cards

**What they are:** After every 5 user messages, a gold-bordered card appears in the conversation with a rotating reflection prompt. There are 8 prompts that cycle in order, each designed to interrupt passive consumption of AI output.

**Why they exist:** Research on metacognitive learning strategies consistently shows that periodic self-reflection during a learning activity improves retention and transfer. In a conversational AI context, students can easily fall into a passive question-answer rhythm without consolidating what they've learned. Reflection cards interrupt this rhythm and force active processing. They also model the kind of critical self-monitoring that students should apply to all AI interactions — not just in this tool.

---

### Summary Panel (&#128203;)

**What it is:** A collapsible panel accessed via the clipboard icon in the header. On first click, it sends the conversation to the API and requests a structured summary: key ideas covered, questions worth thinking more about, and one thing to verify independently. Subsequent clicks toggle the panel's visibility without re-fetching (unless the conversation has grown significantly).

**Why it exists:** Formative self-assessment is a well-evidenced learning strategy. At the end of a tutoring session, students benefit from seeing the conversation organized into higher-order categories: what they learned, what's still open, and what they should verify elsewhere. The "one thing to verify yourself" prompt is deliberate — it reinforces the core message that AI output should never be accepted as the final word, and it gives students a concrete next action.

---

## Project Structure

```
mercurius-chatbot/
  public/
    index.html     — Demo page
    widget.css     — All widget styles (namespaced with merc-)
    widget.js      — Self-contained widget (no dependencies)
  server.js        — Express backend + Anthropic API proxy
  package.json     — Dependencies and npm scripts
  .env.example     — Environment variable template
  README.md        — This file
```

---

## API Reference

### POST /api/chat

Accepts a conversation and returns the next assistant message.

**Request body:**
```json
{
  "messages": [
    { "role": "user",      "content": "What is machine learning?" },
    { "role": "assistant", "content": "Great question! Before I answer..." }
  ],
  "sessionId": "merc_abc123_def456_1234567890abcd"
}
```

**Success response (200):**
```json
{
  "reply": "Interesting question. Before I answer — what do you think..."
}
```

**Error response (4xx/5xx):**
```json
{
  "error": "rate_limited",
  "reply": "Whoa, slow down! You've sent a lot of messages..."
}
```

**Rate limit:** 10 requests per minute per `sessionId`. Returns 429 when exceeded.

### GET /api/health

Returns server status.

```json
{
  "status": "ok",
  "service": "Mercurius Ⅰ",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

---

## Native iOS App

`ios/` contains a full native Swift/SwiftUI companion app that talks to the same backend. It isn't a re-packaging of the web widget — it's an architecturally independent build designed to ship through the App Store.

### Architecture

Modular Swift Package Manager layout under `ios/Packages/`:

| Module | Responsibility |
|---|---|
| `DesignSystem` | Brand colors, typography (Dynamic-Type-aware), logo, reusable buttons |
| `NetworkingKit` | `APIClient`, session identity, SSE streaming, typed `APIError`, keychain wrapper |
| `PersistenceKit` | SwiftData-backed chat history + in-memory fallback |
| `ChatFeature` | Chat view model, message list, mode selector, quiz + report-card tools |
| `CurriculumFeature` | 5 units × 4 lessons, progress store with forward-compatible migrations |
| `ClubFeature` | Schedule / upcoming meetings / blog, pulled live from `mayoailiteracy.com` |
| `SettingsFeature` | Theme preference, session reset |
| `AppFeature` | Composition root — `AppEnvironment`, `RootView`, `AppShellView` (TabView) |
| `ArchitectureTests` | Dependency-graph validator against a pinned `manifest.json` fixture |

Dependencies flow strictly downward. `ArchitectureTests` enforces the layering at test time — a PR that adds a cross-feature import gets caught.

The Xcode project itself is generated from `ios/project.yml` via [xcodegen](https://github.com/yonaskolb/XcodeGen), so nothing is committed that can't be rebuilt from source.

### Building + running

Prerequisites: **Xcode 16+**, **xcodegen** (`brew install xcodegen`).

```bash
cd ios
xcodegen generate
open Mercurius.xcodeproj
```

Run on the **iPhone 16** simulator (iOS 17+). No API key configuration is needed inside the app — it points at `mercurius-chatbot-production.up.railway.app` by default.

### Test suite

Four layers of coverage, all driven by the `Mercurius` scheme:

| Layer | Tool | Count |
|---|---|---|
| Swift Testing (`@Test`) — SPM packages | `swift test --parallel` from `ios/Packages` | 204 across 41 suites |
| XCTest unit + snapshot (MercuriusTests) | `xcodebuild test` | 24 |
| XCUITest end-to-end (MercuriusUITests) | `xcodebuild test` | 10 |
| Performance (MercuriusUITests) | `xcodebuild test` — local only, skipped in CI | 3 |

Every PR runs the full matrix on GitHub Actions (`.github/workflows/ios.yml`). The badge above reflects the latest run.

```bash
# SPM tests (fast, runs on host macOS)
cd ios/Packages && swift test --parallel

# Everything iOS-sim-side
cd ios && xcodebuild test \
  -project Mercurius.xcodeproj \
  -scheme Mercurius \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Coverage baseline regenerates via `ios/scripts/coverage.sh refresh-baseline`; current numbers live in `ios/docs/COVERAGE.md`.

### Distinctive iOS features

- **Full Dynamic Type support**, including accessibility sizes (canary snapshot tests catch layout regressions).
- **SSE streaming via `URLSessionDataDelegate`** — works around a known iOS 17 buffering bug in `URLSession.bytes(for:)` over HTTP/2 SSE.
- **End-to-end HTTP tests via `StubURLProtocol`** — every error code (401, 429, 500, offline, timeout), every happy path, and mid-stream chunks split across packet boundaries.
- **Snapshot tests for every ChatFeature view state** (bubbles, typing indicator, failure, quiz, report card) at light + dark + XXL Dynamic Type.
- **Performance baselines** for cold launch, chat scroll, and memory footprint (via a `-SeedDemoChat` launch arg that pre-populates the chat store).
- **Privacy manifest** declaring no tracking, no tracking domains, and a single required-reason API (`UserDefaults`, `CA92.1`).

### App Store readiness

`ios/docs/APP_STORE.md` is the full submission checklist with every remaining human-action gate called out explicitly — reserve the bundle identifier, set `DEVELOPMENT_TEAM`, publish a privacy-policy URL, capture screenshots, then run the archive + validate one-liner.

---

## License

MIT. Use freely in educational contexts.

---

*Mercurius Ⅰ — "Mercury was the Roman messenger god — a fitting name for something that moves information around. The Ⅰ is because this is the first version, and there will always be room to improve."*
