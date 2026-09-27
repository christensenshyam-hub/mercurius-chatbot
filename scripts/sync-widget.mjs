#!/usr/bin/env node
// public/widget.js + public/widget.css are the single source of the web
// widget. This writes byte-identical copies to mayo-site/ (the club site's
// working copy); per-site settings live in each page's window.MercuriusConfig,
// never in the copied files.
//
//   node scripts/sync-widget.mjs          copy public/ → mayo-site/
//   node scripts/sync-widget.mjs --check  exit 1 if a copy differs (CI)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const PAIRS = [
  ['public/widget.js', 'mayo-site/widget.js'],
  ['public/widget.css', 'mayo-site/widget.css'],
];
const check = process.argv.includes('--check');

const stale = [];
for (const [from, to] of PAIRS) {
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

if (check && stale.length) {
  console.error(`Out of sync with public/: ${stale.join(', ')}. Run: node scripts/sync-widget.mjs`);
  process.exit(1);
}
if (check) console.log('widget copies in sync');
