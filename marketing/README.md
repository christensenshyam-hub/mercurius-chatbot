# Mercurius AI — marketing site

The promotional site for [Mercurius AI](https://trymercurius.com), deployed
by Netlify from this folder. Plain HTML, CSS, and a few lines of vanilla
JS — no framework, no build step, no dependencies.

## Structure

```
marketing/
├── index.html          # Home: hero, lesson replay (#demo), links to the five short reads
├── features.html, modes.html, how-it-works.html, audience.html, trust.html
├── privacy.html, terms.html, support.html   # linked from the app and App Store
├── _redirects          # /get, /beta, /feedback shortcuts + clean-URL rewrites
├── robots.txt, sitemap.xml
├── styles.css          # Single stylesheet; brand tokens at top
├── script.js           # Mode-pill tabs + dynamic year
├── demo.js             # Lesson replay step-through (homepage only)
├── assets/
│   ├── mercurius-logo.png / .webp  # Full logo + wordmark (1024×1024); hero
│   ├── og-card.png          # 1200×630 link-preview image (og:image)
│   ├── favicon-48.png, apple-touch-icon.png
│   ├── app-store-badge.svg  # Apple's official US badge, self-hosted (unused while the CTAs point at /get: docs/STORE_CTA_SWITCHBACK.md)
│   └── mercurius-icon.png   # Old cropped icon (470×415), no longer referenced
└── README.md
```

Canonical URLs are the extensionless form (`https://trymercurius.com/privacy`).
Netlify rewrites the `.html` links in the pages to that form on deploy, and
`_redirects` maps each short path back to its file. The privacy page states
what the production server keeps and for how long — change it in the same
PR as any retention or data-flow change on the server.

## Lesson replay (homepage `#demo`)

Directly under the hero: a replay of a real Mercurius lesson (Unit 1,
Lesson 1, "What happens when you type a prompt"), recorded October 7, 2026.
No live AI calls. Spec: `docs/marketing-demo.md`.

- **Source:** `docs/evals/pacing-demo-capture-lesson1.json`, run 2
  (`perRun[1]`), turns 1–3 of `curriculum-blocks-1`. The student taps were
  scripted by the eval harness; Mercurius's replies are the model's real
  output and are never edited. Turns 4+ are left out on purpose.
- **Generated, not hand-written:** everything between `<!-- DEMO:START -->`
  and `<!-- DEMO:END -->` in `index.html` comes from
  `scripts/build-demo-replay.mjs`. It renders only the markup the app renders
  (paragraphs, `**bold**`, `*italic*`, `---`, `[EX]`, `[KEY]`, `[Q]`), refuses
  to run on markup it doesn't know, checks the hidden opener against the iOS
  curriculum starter and each student turn against the previous check's
  options, and stamps the capture's sha256 into the section. Never edit the
  section by hand.

  ```bash
  node scripts/build-demo-replay.mjs           # regenerate the section
  node scripts/build-demo-replay.mjs --check   # verify the page matches the capture
  ```

- **Behaviour:** without JS the whole replay is plain HTML (answered checks
  show the recorded pick). `demo.js` turns it into a step-through: grade the
  visitor's pick locally from the card's `data-answer`, say what the student
  picked in the recorded session, then "Continue" reveals that pick and the
  real reply. "Show the whole lesson" and "Start over" are in the panel
  header. Styles are the "Lesson replay" block at the end of `styles.css`
  (iOS `BrandColor`/`BrandRadius` values, darkened where needed for AA).
- **Debug hook:** `?demo-step=turn1|answered1|turn2|answered2|turn3|answered3|end|whole`
  opens the replay at that point. Earlier checks are answered with the
  recorded pick, or with the right answer where none was recorded (turn 3's
  check, in `end`). Read-only, no network; used for screenshots.
- **Check:** with the site served on 8160
  (`cd marketing && python3 -m http.server 8160`):

  ```bash
  node scripts/check-demo.mjs   # or pass another URL; needs Google Chrome
  ```

  It drives headless Chrome over the DevTools protocol and fails (exit 1)
  if the section drifts from the capture, the no-JS replay is incomplete,
  the step order, keyboard path, grading, recorded-pick notes, focus moves,
  live-region announcements, "Show the whole lesson" or "Start over" break,
  the page overflows at 360/390px, demo.js adds layout shift, or any
  Mercurius reply's text differs from the JSON. It loads the page dozens of
  times; a full run (124 checks) takes about 20 seconds on a MacBook.
- **Screenshots for review:** shoot the three states with the hook, e.g.
  `index.html` (start), `index.html?demo-step=answered2` (mid) and
  `index.html?demo-step=end` (end), at 360, 390, 768, 1280 and 1440px. Keep
  them in `.shots/` at the repo root; it's gitignored. Crop each full-page
  shot to the `#demo` section and lay start / mid / end side by side
  (one sheet for 768–1440px, one for 360/390px) to review the states
  together.
- **Changing the replay:** don't edit the section or reword a reply. To use
  a different run or more turns, change `RUN_INDEX`/`TURNS` at the top of
  `scripts/build-demo-replay.mjs` and the matching `perRun[…]`/`TURNS` in
  `check-demo.mjs`, regenerate, re-run both checks, and update the spec
  (`docs/marketing-demo.md`) in the same PR.

## Local preview

Any static server works. Two one-liners:

```bash
# Python (built into macOS)
cd marketing && python3 -m http.server 8000

# Or with Node
npx http-server marketing -p 8000
```

Then open `http://localhost:8000`.

## Deploy options

The site is fully static — pick whichever host you already use.

- **Netlify / Vercel / Cloudflare Pages** — drop `marketing/` as the
  publish directory. No build command needed.
- **GitHub Pages** — point it at the `marketing/` folder (or copy
  contents into `docs/`).
- **Existing Express server** — add one line to `server.js`:
  ```js
  app.use('/site', express.static(require('path').join(__dirname, 'marketing')));
  ```
  Reachable at `/site` then. Keep the API path separate from the
  marketing path so a marketing redeploy never touches the chat
  surface.

## Brand tokens

Defined as CSS custom properties at the top of `styles.css`. Update
once, everything follows:

| Token | Hex | Use |
| --- | --- | --- |
| `--navy` | `#0B1330` | Headings, primary text |
| `--blue` | `#2F7BFF` | Gradient stop 1, accents |
| `--violet` | `#7B4DFF` | Gradient stop 2, eyebrows |
| `--lavender` | `#E8E5FF` | Soft section backgrounds |
| `--bg` | `#F2F4F8` | Page background |
| `--ink` | `#1A202C` | Body text |

Blue → violet gradients live behind the primary CTA, the eyebrows,
the headline accents, and the step numbers. Don't add a third color
to the gradient — it stops feeling premium fast.

## Typography

- **Display** — Playfair Display 700 (headlines, brand mark)
- **Body / UI** — Inter 400/500/600/700 (everything else)

Both loaded from Google Fonts with `display=swap`, so first paint
uses system fonts and the web font swaps in without layout shift.

## Accessibility

- Skip link at the very top.
- Semantic landmarks (`<header>`, `<main>`, `<footer>`, `<nav>`).
- Heading hierarchy: one `<h1>` (hero), `<h2>` per section, `<h3>`
  inside cards.
- Mode tabs follow the WAI-ARIA tablist pattern with arrow-key
  navigation in `script.js`.
- All decorative images have `alt=""` + `aria-hidden`. The brand
  mark has the meaningful label on the wrapping link.
- `prefers-reduced-motion` disables the hero float + smooth scroll,
  and makes the lesson replay's reveal fade instant.
- Lesson replay: each check is a `radiogroup` of real buttons (arrows,
  Home/End, Enter/Space), options are at least 44px tall, focus is
  always visible, newly shown turns are announced in a polite live
  region with focus moved to their first message, and cards carry
  screen-reader labels ("Key idea:", "Example:", "Check:").

## Performance

- One HTML, one CSS, one JS file per page (the homepage adds `demo.js`,
  ~4KB gzipped, `defer`). Total transfer < 50KB before fonts and the
  hero image.
- The hero is served as WebP (≈50KB) through `<picture>`, with the
  210KB PNG as the fallback. Every `<img>` carries width and height
  so nothing shifts while it loads.
- `loading="eager"` + `fetchpriority="high"` on the hero image so
  it doesn't lose the LCP race.
- No third-party scripts. No analytics by default — add a single
  `<script>` tag when you're ready.

## What's intentionally NOT here

These are common marketing-site bloat patterns we left out so the
brand stays premium. Add them only with real content:

- ❌ Fake testimonial blocks (no real students yet)
- ❌ Logos of institutions (no partnerships yet)
- ❌ Pricing table (free in beta)
- ❌ "Trusted by N students" counter (don't fabricate stats)
- ❌ Heavy animation libraries
- ❌ Cookie banners (no third-party cookies set)

Each can be added cleanly when the content actually exists.
