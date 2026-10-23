# Switching the site's CTAs back to the App Store

While app 2.3 is only on TestFlight, every "get the app" button on
trymercurius.com points at `https://trymercurius.com/get` as a plain
"Get the app (beta)" button (AUD-06, October 2026 audit). The App Store
still sells 2.0.0: rated 9+, with no age check, no Anthropic notice and no
delete button. Apple's badge is only for links to the App Store, so it is
off the site until then.

## 0. While the CTAs point at /get: keep the beta open

These buttons are only useful while the TestFlight public link accepts
testers. On 2026-10-19 it did not ("This beta isn't accepting any new
testers right now"), so the commit that made this switch must not merge
until this prints `0`:

```bash
curl -sL https://testflight.apple.com/join/3ujBtDsa | grep -cE "accepting any new testers|beta is full"
```

Apple writes "isn't" as `isn&#39;t` in the page source, so a grep for
"isn't accepting" prints `0` even when the beta is closed. Also open
trymercurius.com/get on an iPhone and check it offers to join the beta.

To reopen it: App Store Connect → the app → TestFlight → the external
group → turn the public link on, raise the tester limit if it is full, and
make sure a 2.3 build that passed Beta App Review is in the group.

Run the check again after any change to the external group, and before
**about 2026-12-26**, when build 16 (uploaded 2026-09-27) expires after
TestFlight's 90 days. If 2.3 isn't on the App Store by then, upload and
assign a newer build first; otherwise `/get` and every button below lead
to a beta with nothing to install. If the beta has to stay closed, revert
the CTA commit (the privacy and support fixes are separate commits and
don't depend on it).

## Switching back

Do this switch-back **only once 2.3 (or later) is live on the App Store**.
Check first:

```bash
curl -s 'https://itunes.apple.com/lookup?id=6773192313&country=us' \
  | python3 -m json.tool | grep -E '"version"|contentAdvisoryRating'
```

`version` must be 2.3.0 or later.

Every changed spot carries the comment
`AUD-06: switch back to the App Store link when 2.3 is approved`, so this
finds them all:

```bash
grep -rn "AUD-06" marketing scripts docs/marketing-demo.md
```

## 1. The /get redirect (`marketing/_redirects`)

Flip the three lines `/get`, `/Get` and `/GET` from the TestFlight URL to
`https://apps.apple.com/app/id6773192313`, keeping `302`. The comment
above them already says this. `/beta` stays on TestFlight.

## 2. The Smart App Banner (9 pages, line 7)

Pages: `index.html`, `features.html`, `modes.html`, `how-it-works.html`,
`audience.html`, `trust.html`, `support.html`, `privacy.html`,
`terms.html`.

Now (a 3-line comment, then the tag commented out):

```html
  <!-- AUD-06: switch back to the App Store link when 2.3 is approved.
       Then restore this Smart App Banner too. Safari shows it as a banner
       that opens the App Store listing, which offers 2.0.0 until then. -->
  <!-- <meta name="apple-itunes-app" content="app-id=6773192313" /> -->
```

Back to:

```html
  <meta name="apple-itunes-app" content="app-id=6773192313" />
```

## 3. The header pill (9 pages)

Line 51–52 on every page except `index.html` (68–69) and `privacy.html`
(91–92).

Now:

```html
        <!-- AUD-06: switch back to the App Store link when 2.3 is approved -->
        <a class="cta-pill" href="https://trymercurius.com/get" target="_blank" rel="noopener noreferrer">Get the app (beta)</a>
```

Back to:

```html
        <a class="cta-pill" href="https://apps.apple.com/app/id6773192313" target="_blank" rel="noopener noreferrer">Start Learning</a>
```

## 4. Homepage hero (`marketing/index.html`, lines 92–93)

Now:

```html
            <!-- AUD-06: switch back to the App Store link when 2.3 is approved -->
            <a class="btn btn-primary" href="https://trymercurius.com/get" target="_blank" rel="noopener noreferrer">Get the app (beta)</a>
```

Back to:

```html
            <a href="https://apps.apple.com/app/id6773192313" target="_blank" rel="noopener noreferrer" aria-label="Download Mercurius on the App Store">
              <img src="/assets/app-store-badge.svg" alt="Download on the App Store"
                   width="144" height="48" style="display: block;" />
            </a>
```

## 5. End of the lesson replay (generated, don't edit `index.html` by hand)

The `#demo` section is written by `scripts/build-demo-replay.mjs`.

In **`scripts/build-demo-replay.mjs`**:

- Replace the `GET_URL` constant and its 3-line comment (around line 43)
  with:

  ```js
  const APP_STORE_URL = 'https://apps.apple.com/app/id6773192313';
  ```

- In the `demo-end` block (around line 333), replace the comment line, the
  button line and the fine-print line with:

  ```js
    `        <a class="demo-badge" href="${APP_STORE_URL}" target="_blank" rel="noopener noreferrer" aria-label="Download Mercurius on the App Store">`,
    '          <img src="/assets/app-store-badge.svg" alt="Download on the App Store" width="144" height="48" />',
    '        </a>',
    '        <p class="demo-end-fine">Free on the App Store. Requires iPhone, iOS 17 or later.</p>',
  ```

In **`scripts/check-demo.mjs`** (around line 326), replace the AUD-06
comment and the check with:

```js
      check('end: App Store link + self-hosted badge', facts.href === 'https://apps.apple.com/app/id6773192313' && facts.badge === '/assets/app-store-badge.svg');
```

(The extra `label:` field in the `facts` object can stay.)

In **`docs/marketing-demo.md`**, delete the "Until 2.3 is approved
(AUD-06)" sub-bullet under "End with the real next step".

Then regenerate: `node scripts/build-demo-replay.mjs`.

## 6. Homepage final CTA (`marketing/index.html`, lines 391–395)

Now:

```html
        <!-- AUD-06: switch back to the App Store link when 2.3 is approved -->
        <a class="btn btn-primary btn-large" href="https://trymercurius.com/get" target="_blank" rel="noopener noreferrer">Get the app (beta)</a>
        <p class="fineprint">
          Free beta on Apple's TestFlight. Requires iPhone, iOS 17 or later.
        </p>
```

Back to:

```html
        <a href="https://apps.apple.com/app/id6773192313" target="_blank" rel="noopener noreferrer" aria-label="Download Mercurius on the App Store" style="display: inline-block;">
          <img src="/assets/app-store-badge.svg" alt="Download on the App Store"
               width="168" height="56" style="display: block;" />
        </a>
        <p class="fineprint">
          Free on the App Store. Requires iPhone, iOS 17 or later.
        </p>
```

## 7. Small notes elsewhere

- `marketing/README.md`: drop "(unused while the CTAs point at /get …)"
  from the `app-store-badge.svg` line.
- Leave these alone; they stay true after the switch:
  - `privacy.html` "Your controls" and `support.html` "Can I delete my
    data?" link to `trymercurius.com/get` for installing the current
    version (once `/get` points at the App Store, that is 2.3).
  - `privacy.html` says the age check starts with app version 2.3 and that
    earlier versions don't ask.
  - The /get links in `docs/PILOT_PLAYBOOK.md` and the poster.

## 8. Check

```bash
grep -rn "AUD-06" marketing scripts docs/marketing-demo.md        # nothing left
grep -rn "trymercurius.com/get" marketing/*.html                  # only privacy.html "Your controls" and support.html "Can I delete my data?"
grep -rln "apps.apple.com/app/id6773192313" marketing/*.html      # all 9 pages
node scripts/build-demo-replay.mjs --check
(cd marketing && python3 -m http.server 8160) &                   # then:
node scripts/check-demo.mjs                                       # 124 passed
curl -s -o /dev/null -w '%{redirect_url}\n' https://trymercurius.com/get   # after deploy: apps.apple.com
```
