# Mercurius AI — marketing site

The promotional site for [Mercurius AI](https://trymercurius.com), deployed
by Netlify from this folder. Plain HTML, CSS, and a few lines of vanilla
JS — no framework, no build step, no dependencies.

## Structure

```
marketing/
├── index.html          # Home: hero + links to the five short reads
├── features.html, modes.html, how-it-works.html, audience.html, trust.html
├── privacy.html, terms.html, support.html   # linked from the app and App Store
├── _redirects          # /get, /beta, /feedback shortcuts + clean-URL rewrites
├── robots.txt, sitemap.xml
├── styles.css          # Single stylesheet; brand tokens at top
├── script.js           # Mode-pill tabs + dynamic year
├── assets/
│   ├── mercurius-logo.png / .webp  # Full logo + wordmark (1024×1024); hero
│   ├── og-card.png          # 1200×630 link-preview image (og:image)
│   ├── favicon-48.png, apple-touch-icon.png
│   ├── app-store-badge.svg  # Apple's official US badge, self-hosted
│   └── mercurius-icon.png   # Old cropped icon (470×415), no longer referenced
└── README.md
```

Canonical URLs are the extensionless form (`https://trymercurius.com/privacy`).
Netlify rewrites the `.html` links in the pages to that form on deploy, and
`_redirects` maps each short path back to its file. The privacy page states
what the production server keeps and for how long — change it in the same
PR as any retention or data-flow change on the server.

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
- `prefers-reduced-motion` disables the hero float + smooth scroll.

## Performance

- One HTML, one CSS, one JS file per page. Total transfer < 50KB
  before fonts and the hero image.
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
