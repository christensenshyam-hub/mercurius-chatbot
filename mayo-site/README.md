# Mayo AI Literacy Club — club site

The 2026 rewrite of [mayoailiteracy.com](https://mayoailiteracy.com).
Plain HTML, CSS, and vanilla JS — no framework, no build step. A sibling
of the Mercurius marketing site (`../marketing/`): same type system and
layout language, with the club's own forest-green + gold palette.

## Structure

```
mayo-site/
├── index.html        # Home — hero, stats, member voices, featured post
├── about.html        # Mission + founding story + board + the 3 Groups
├── topics.html       # What we cover + the curated resource library
├── events.html       # Meeting schedule + upcoming + past (from JSON)
├── blog.html         # Post listing (from JSON)
├── blog-post.html    # Single-post renderer (?id=<post-id>)
├── mercurius.html    # Mercurius Ⅰ showcase — iOS app + browser widget
├── join.html         # Join box + Netlify contact form
├── 404.html          # Branded not-found page
├── _redirects        # Netlify redirects (old URLs → new homes)
├── styles.css        # Single stylesheet; brand tokens at the top
├── script.js         # Nav toggle, fade-ins, shared JSON fetch
├── blog-content.json # ★ THE blog — site renders it, the app reads it
├── events-data.json  # ★ THE schedule — site renders it, the app reads it
├── logo.png          # Club logo (512px, also the favicon/og image)
├── widget.{js,css}, manifest.json, sw.js, icons/
│                     # Mercurius web widget + PWA (carried over as-is)
├── blog-anthropic-pentagon.html  # Bespoke article page (self-contained)
└── assets/           # Board photos (optimized), sponsor logo
```

## ★ The two JSON files are load-bearing

`blog-content.json` and `events-data.json` are fetched hourly by the
Mercurius backend on Railway (`server.js` → `BLOG_URL` / `EVENTS_URL`)
and fed to the tutor as live context. **Do not rename, move, or break
these paths.** The site renders from the same files, so there is exactly
one place to edit:

- **Publish a blog post** → add an object to the TOP of
  `blog-content.json` (`id`, `title`, `date`, `author`, `category`,
  `summary`, `content` — paragraphs separated by blank lines, `## `
  headings, `**bold**`, `*italic*`), push. The site AND the in-app
  tutor pick it up. (~1hr server cache.)
- **Change the schedule / add an event** → edit `events-data.json`
  (`schedule`, `upcoming[]`, `past[]` — a past event with `recapUrl`
  gets a "Read recap" link), push.

## Everything else you might edit

| What | Where |
|---|---|
| Stats (members, meetings…) | `index.html` → "STATS" comment |
| Member quotes (ticker) | `index.html` → `QUOTES` array |
| Board members + photos | `about.html` + `assets/board-*.jpg` |
| Topics / resources | `topics.html` |
| App Store badge (launch day!) | `mercurius.html` → "LAUNCH DAY" comment |
| Sponsor | `index.html` → "SUPPORTERS" section |
| Brand colors / fonts | `styles.css` → `:root` tokens |

## Local preview

```bash
cd mayo-site && python3 -m http.server 8000
```

Use the `.html` URLs locally (e.g. `/about.html`) — extensionless pretty
URLs (`/about`) are a Netlify behavior.

## Deploy

Netlify site with **publish directory `mayo-site`**, no build command,
auto-deploys on push to `main` (a second Netlify site on this same repo,
alongside the one publishing `marketing/`). After the FIRST deploy:

1. **Forms**: enable form detection (Site configuration → Forms) and add
   a notification email — the Join form is a Netlify Form named
   `contact`; without this, submissions land in the dashboard unnoticed.
2. **Domain cutover**: move `mayoailiteracy.com` from the old Netlify
   site to this one, then immediately verify:
   `curl -s https://mayoailiteracy.com/blog-content.json | head` and
   `curl -s https://mayoailiteracy.com/events-data.json | head`
   (the app's backend depends on both).

## Carried over from the old site, on purpose

- The Mercurius **web widget + PWA** (`widget.js`, `sw.js`,
  `manifest.json`, `/icons`) — Chromebook/Android users use this. The
  service worker caches `/mercurius.html`, `/widget.js`, `/widget.css`,
  `/manifest.json`; all four paths still exist here.
- `blog-anthropic-pentagon.html` — a bespoke, self-contained article
  page; the blog listing links to it via the `CUSTOM_URLS` map.
- The old `/board`, `/groups`, `/resources` URLs 301 to their new homes
  (see `_redirects`).
