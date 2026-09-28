'use strict';

// Preload for spawned test servers (node --require): answers the club-site
// feed fetches from the repo's own copies, so a widget (club_v1) request gets
// real-sized meeting + blog material and the test never touches the network.

const fs = require('node:fs');
const path = require('node:path');

const SITE = path.join(__dirname, '..', '..', 'mayo-site');
const FEEDS = {
  'https://mayoailiteracy.com/blog-content.json': path.join(SITE, 'blog-content.json'),
  'https://mayoailiteracy.com/events-data.json': path.join(SITE, 'events-data.json'),
};

const realFetch = globalThis.fetch;
globalThis.fetch = async (url, opts) => {
  const file = FEEDS[String(url)];
  if (!file) return realFetch(url, opts);
  return new Response(fs.readFileSync(file), { status: 200, headers: { 'Content-Type': 'application/json' } });
};
