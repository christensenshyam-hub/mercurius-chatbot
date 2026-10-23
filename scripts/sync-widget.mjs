#!/usr/bin/env node
// public/widget.js + public/widget.css are the single source of the web
// widget, and today its only copy: the server serves it from public/. The
// club site used to carry a byte-identical copy (mayo-site/, written by this
// script), but it dropped the widget in June 2026 (mayo-ai-literacy-club
// dab692d), and the stale mayo-site/ folder was removed from this repo — the
// club site lives in the mayo-ai-literacy-club repo.
//
// COPIES lists every generated copy (none today). --check also fails on an
// UNLISTED widget.js / widget.css anywhere in the repo, so a copy can't come
// back as a hand-edited fork: list it in COPIES and run this script instead.
// Per-site settings live in each page's window.MercuriusConfig, never in the
// copied files.
//
//   node scripts/sync-widget.mjs          copy public/ → every listed copy
//   node scripts/sync-widget.mjs --check  exit 1 if a copy differs or an
//                                         unlisted one exists (CI)
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOURCES = ['public/widget.js', 'public/widget.css'];
// [source, copy] pairs, repo-relative.
const COPIES = [];
const check = process.argv.includes('--check');

// Dependencies, build output and dot-directories (.git, worktrees) never hold
// a copy of ours.
const SKIP_DIRS = new Set(['node_modules', 'build', 'DerivedData']);
function widgetFiles(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (!entry.name.startsWith('.') && !SKIP_DIRS.has(entry.name)) widgetFiles(join(dir, entry.name), out);
    } else if (entry.name === 'widget.js' || entry.name === 'widget.css') {
      out.push(relative(root, join(dir, entry.name)).split(sep).join('/'));
    }
  }
  return out;
}

const stale = [];
for (const [from, to] of COPIES) {
  const source = readFileSync(join(root, from));
  let copy = null;
  try {
    copy = readFileSync(join(root, to));
  } catch {
    // missing copy: stale
  }
  if (copy && source.equals(copy)) continue;
  if (check) {
    stale.push(to);
  } else {
    writeFileSync(join(root, to), source);
    console.log(`wrote ${to}`);
  }
}

if (check) {
  const known = new Set([...SOURCES, ...COPIES.map(([, to]) => to)]);
  const unlisted = widgetFiles(root).filter((f) => !known.has(f));
  if (stale.length) console.error(`Out of sync with public/: ${stale.join(', ')}. Run: node scripts/sync-widget.mjs`);
  if (unlisted.length) {
    console.error(`Unlisted copy of the web widget: ${unlisted.join(', ')}. public/ is the single source: add it to COPIES in scripts/sync-widget.mjs and run the script, or delete it.`);
  }
  if (stale.length || unlisted.length) process.exit(1);
  console.log(COPIES.length ? 'widget copies in sync' : 'public/widget.{js,css} is the only copy of the web widget');
}
