'use strict';

// lib/clubKnowledge: the club facts a club_v1 (widget) request carries in its
// cached prefix must be the ones the live club site (mayoailiteracy.com)
// states, and nothing it has dropped. The site itself is not fetched here;
// these pin the facts restated from it on 2026-10-06 (redesign bf17ab1).

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');

const { CLUB_KNOWLEDGE } = require('../lib/clubKnowledge');
const { staticClubBlock, CLUB_V1 } = require('../lib/clubContext');

describe('club knowledge matches the live club site', () => {
  test('name, school, and who can come', () => {
    assert.match(CLUB_KNOWLEDGE, /Name: Mayo AI Literacy Club\. A student-run club at Mayo High School \(MHS\) in Rochester, Minnesota\./);
    assert.match(CLUB_KNOWLEDGE, /any Mayo High School student\. No AI experience needed, and no sign-up for a first visit\./);
  });

  test('the board, with the site’s titles', () => {
    for (const line of [
      '- Shyam Christensen: co-founder and co-president.',
      '- Nathan Dozois: co-founder and co-president.',
      '- Adam Keegan: vice president.',
      "- Niko Lazaridis: secretary; manages the club's communications.",
    ]) assert.ok(CLUB_KNOWLEDGE.includes(line), line);
    assert.doesNotMatch(CLUB_KNOWLEDGE, /President & Co-Founder|Executive Board/);
  });

  test('AACA June 2026 was a poster, never a talk', () => {
    assert.ok(CLUB_KNOWLEDGE.includes('presented a poster, "Teaching the Pause: A Student-Led Model for Critical AI Literacy," at the 43rd Annual Meeting of the American Association of Clinical Anatomists (AACA)'));
    assert.match(CLUB_KNOWLEDGE, /June 12–15, 2026/);
    assert.match(CLUB_KNOWLEDGE, /It was a poster\. Never call it a talk/);
  });

  test('chapters program and the Mayo Clinic non-affiliation', () => {
    assert.match(CLUB_KNOWLEDGE, /CHAPTERS AT OTHER SCHOOLS \(mayoailiteracy\.com\/chapters\)/);
    assert.match(CLUB_KNOWLEDGE, /Google Form linked from mayoailiteracy\.com\/chapters/);
    assert.match(CLUB_KNOWLEDGE, /Neither it nor this club is affiliated with Mayo Clinic, where the AACA meeting was hosted\./);
  });

  test('nothing the site no longer says', () => {
    for (const stale of [
      /25\+|15\+/,                                  // "25+ members, 15+ meetings held"
      /\d+\+?\s+(?:members|meetings)\b/i,
      /6 topics covered|1 seminar completed/,
      /join\.html/,                                  // the site links /join
      /FULL KNOWLEDGE BASE|inside and out/,
      /Curiosity is the only prerequisite/,          // old mission quote
      /advantage won't come from having AI/,         // old "key quote"
      /required viewing/,
      /How Claude Thinks/,                           // now "Claude's Character"
      /General AI|Prompt Engineering —/,             // old topic names
    ]) assert.doesNotMatch(CLUB_KNOWLEDGE, stale);
  });

  test('the schedule and the blog come from the feeds, not from here', () => {
    // meeting_context (events-data.json) and blog_context (blog-content.json)
    // carry them, so a site edit never leaves a stale copy in the prefix.
    assert.doesNotMatch(CLUB_KNOWLEDGE, /8:20|Library Classroom|Thursday/);
    assert.doesNotMatch(CLUB_KNOWLEDGE, /Michael Teng|BLOG AUTHORS/);
    assert.match(CLUB_KNOWLEDGE, /The meeting schedule and upcoming events are in meeting_context/);
  });

  test('a build-time constant: the cached club block is byte-stable', () => {
    const block = () => staticClubBlock({ capabilities: [CLUB_V1], clubKnowledge: CLUB_KNOWLEDGE });
    assert.equal(block(), block());
    // A fresh module instance (another replica, a restart) yields the same bytes.
    const file = require.resolve('../lib/clubKnowledge');
    delete require.cache[file];
    const fresh = require(path.join(__dirname, '..', 'lib', 'clubKnowledge')).CLUB_KNOWLEDGE;
    assert.equal(fresh, CLUB_KNOWLEDGE);
    assert.ok(Object.isFrozen(require('../lib/clubKnowledge')));
  });
});
