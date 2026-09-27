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
├── mercurius.html    # Mercurius AI showcase — the iOS app (no web widget)
├── join.html         # Join box + Netlify contact form
├── 404.html          # Branded not-found page
├── _redirects        # Netlify redirects (old URLs → new homes)
├── styles.css        # Single stylesheet; brand tokens at the top
├── script.js         # Nav toggle, fade-ins, shared JSON fetch
├── blog-content.json # ★ THE blog — site renders it, the app reads it
├── events-data.json  # ★ THE schedule — site renders it, the app reads it
├── logo.png          # Club logo (512px), the og:image for link previews
├── robots.txt, sitemap.xml
├── widget.{js,css}, manifest.json, sw.js, icons/
│                     # Old web widget + PWA files — not live, see below
├── blog-anthropic-pentagon.html  # Bespoke article page (self-contained)
└── assets/           # club-logo-128.png (header logo + favicon), board
                      # photos (312px), sponsor logo, Mercurius logo,
                      # app-store-badge.svg (Apple's badge, self-hosted)
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
| App Store badge | `assets/app-store-badge.svg`, used by `index.html` and `mercurius.html` |
| Sponsor | `index.html` → "SUPPORTERS" section |
| Brand colors / fonts | `styles.css` → `:root` tokens |

## Local preview

```bash
cd mayo-site && python3 -m http.server 8000
```

Use the `.html` URLs locally (e.g. `/about.html`) — extensionless pretty
URLs (`/about`) are a Netlify behavior.

## Deploy

mayoailiteracy.com is **not** deployed from this folder. It is served by
Netlify from the separate `mayo-ai-literacy-club` repo, whose site lives in
its own `mayo-site/` folder and whose root `netlify.toml` carries the
security headers and the CSP (`img-src 'self' data:`, `connect-src
'self'`). This folder is the working copy: edit here, then copy the
changed files over, commit and push there.

Copy only the site pages and assets. **Do not copy** `widget.js`,
`widget.css`, `manifest.json` or `sw.js`: the live site removed the web
widget in June 2026, and its `sw.js` is a self-unregistering kill switch
that must stay. Nothing on these pages loads a third-party image or calls
another origin, so the live CSP needs no change.

After a copy, check:
`curl -s https://mayoailiteracy.com/blog-content.json | head` and
`curl -s https://mayoailiteracy.com/events-data.json | head`
(the app's backend depends on both).

## Carried over from the old site, on purpose

- `blog-anthropic-pentagon.html` — a bespoke, self-contained article
  page; the blog listing links to it via the `CUSTOM_URLS` map. Keep its
  images as files under `assets/`, never pasted in as `data:` URIs (an
  editor export once made it 2.7 MB).
- The old `/board`, `/groups`, `/resources` URLs 301 to their new homes
  (see `_redirects`).
