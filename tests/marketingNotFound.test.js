'use strict';

// trymercurius.com's own "page not found". Netlify serves marketing/404.html,
// with a 404 status, for any path that matches no file or rule, at that path
// (/a/b/c included), so a relative link or asset in it would break there.
// marketing/_redirects also answers the folder's README with that page: the
// README is developer docs, but everything in marketing/ is published.

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const SITE = path.join(ROOT, 'marketing');
const page = fs.readFileSync(path.join(SITE, '404.html'), 'utf8');
const chrome = fs.readFileSync(path.join(ROOT, 'scripts', 'build-site-chrome.mjs'), 'utf8');
const main = (/<main id="main">([\s\S]*?)<\/main>/.exec(page) || [])[1] || '';

test('404.html gets the shared head, header and footer from build-site-chrome.mjs', () => {
  const pages = (/const PAGES = \[([\s\S]*?)\];/.exec(chrome) || [])[1] || '';
  assert.match(pages, /'404\.html'/, 'add 404.html to PAGES so --check keeps its chrome in step');
  assert.match(page, /<header class="site-header">\s*<div class="container header-inner">/);
  assert.match(page, /<footer class="site-footer">\s*<div class="container footer-inner">/);
});

test('every link and asset on the 404 page works from any path', () => {
  const urls = [...page.matchAll(/\s(?:href|src)="([^"]*)"/g)].map((m) => m[1]);
  assert.ok(urls.length > 10);
  for (const u of urls) assert.match(u, /^(?:\/|https:\/\/|#)/, `"${u}" is relative, so it breaks at /a/b/c`);
});

test('the 404 page offers the home page and /get', () => {
  const hrefs = [...main.matchAll(/<a\b[^>]*\bhref="([^"]+)"/g)].map((m) => m[1]);
  assert.ok(hrefs.includes('/'), 'a link to the home page');
  assert.ok(hrefs.includes('/get'), 'a link to /get');
  assert.match(main, /<h1\b/);
});

test('the 404 page names no URL of its own and is not indexed', () => {
  assert.match(page, /<meta name="robots" content="noindex" \/>/);
  assert.doesNotMatch(page, /rel="canonical"/);
  assert.doesNotMatch(page, /property="og:url"/);
  assert.doesNotMatch(fs.readFileSync(path.join(SITE, 'sitemap.xml'), 'utf8'), /404/);
});

// One rule per line: <from> <to> <status> (Netlify's format, at
// https://docs.netlify.com/routing/redirects/, allows more options; this
// file uses only these three). A "!" after the status forces the rule even
// where a file exists at <from>; rule paths are case-sensitive.
const rules = fs.readFileSync(path.join(SITE, '_redirects'), 'utf8').split('\n')
  .map((line, i) => ({ line: i + 1, text: line.trim() }))
  .filter((r) => r.text && !r.text.startsWith('#'))
  .map((r) => ({ ...r, f: r.text.split(/\s+/) }));

test('_redirects: every rule is "<from> <to> <status>" and every local target exists', () => {
  assert.ok(rules.length > 10);
  for (const { line, text, f } of rules) {
    assert.equal(f.length, 3, `line ${line}: "${text}"`);
    const [from, to, status] = f;
    assert.match(from, /^\/[^\s*]*$/, `line ${line}: <from> is a site path`);
    assert.match(to, /^(?:\/|https:\/\/)/, `line ${line}: <to> is a site path or an https URL`);
    assert.match(status, /^(?:200|301|302|404)!?$/, `line ${line}: status`);
    if (to.startsWith('/')) assert.ok(fs.existsSync(path.join(SITE, to)), `line ${line}: ${to} is not a file in marketing/`);
  }
});

test('_redirects: the README (any common capitalization) gets the 404 page, forced over the file', () => {
  const docs = fs.readdirSync(SITE).filter((f) => /\.md$/i.test(f));
  assert.ok(docs.includes('README.md'), 'marketing/README.md is the folder\'s developer docs');
  for (const doc of docs) {
    const base = doc.replace(/\.md$/i, '');
    const forms = new Set([doc, doc.toLowerCase(), `${base[0].toUpperCase()}${base.slice(1).toLowerCase()}.md`, doc.toUpperCase()]);
    for (const name of forms) {
      const rule = rules.find((r) => r.f[0] === `/${name}`);
      assert.ok(rule, `no rule for /${name}: Netlify would serve marketing/${doc} there`);
      assert.deepEqual(rule.f.slice(1), ['/404.html', '404!'], `line ${rule.line}: "${rule.text}"`);
    }
  }
});
