'use strict';

// trymercurius.com's own "page not found". Netlify serves marketing/404.html,
// with a 404 status, for any path that matches no file or rule, at that path
// (/a/b/c included), so a relative link or asset in it would break there.

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
