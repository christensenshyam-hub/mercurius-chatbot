'use strict';

// lib/basicsGuide — the Basics track's teaching guide (2026-10).
//
//   1. The guide covers exactly the 18 lessons of the final curriculum
//      (basics.json ids and titles, pinned below), each with a check of
//      three options and a right answer, and the four safety lessons are
//      the ones its COMPLETION rule names.
//   2. Content rules a reviewer asked for: the postcard rule is the only
//      privacy picture, the Air Canada story's final wording, Mac and web
//      copy steps, no phone number but 911, no menu paths, no new bracket
//      markers (only the client contract markers), practice lines ≤ 12 words.
//   3. The static prefix server.js builds from it: byte-stable, cacheable,
//      app facts then the safety core LAST, never any Deep-dive text.
//   4. The dynamic runtime block: date, device, "Explain more".

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const guide = require('../lib/basicsGuide');
const { BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, BASICS_EXPAND_NOTE, platformFromCapabilities, basicsRuntimeBlock } = guide;
const systemBlocks = require('../lib/systemBlocks');
const { SAFETY_CORE } = require('../lib/safetyCore');
const { APP_FACTS } = require('../lib/appFacts');

// basics.json (the final curriculum, 2026-10-21): every lesson id and title.
const LESSONS = [
  ['b1_l1', 'What is an AI chatbot?'],
  ['b1_l2', 'What chatbots are good at'],
  ['b1_l3', 'What chatbots get wrong'],
  ['b2_l1', 'Asking a real question'],
  ['b2_l2', 'Following up'],
  ['b2_l3', 'What never to share'],
  ['b2_l4', 'Fake calls that sound like family'],
  ['b3_l1', 'Be specific'],
  ['b3_l2', 'Tell it your situation'],
  ['b3_l3', 'Ask for the downsides'],
  ['b4_l1', 'Write an email or letter'],
  ['b4_l2', 'Understand a confusing letter'],
  ['b4_l3', 'Meals, plans and lists'],
  ['b4_l4', 'Learn something new, with a photo'],
  ['b5_l1', 'Checking answers that matter'],
  ['b5_l2', 'Health, money and legal: ask a person'],
  ['b5_l3', 'Other scams that use AI'],
  ['b5_l4', 'On your own'],
];
const SAFETY_LESSONS = ['b2_l3', 'b2_l4', 'b5_l2', 'b5_l3'];

/** The guide's entry for one lesson: its header line through the next one. */
function entry(id) {
  const [, u, l] = /^b(\d)_l(\d)$/.exec(id);
  const start = BASICS_PROMPT.indexOf(`Unit ${u}, Lesson ${l}: `);
  assert.ok(start >= 0, `${id} has an entry`);
  const next = BASICS_PROMPT.slice(start + 1).search(/\n(?:Unit \d, Lesson \d: |### )/);
  return next < 0 ? BASICS_PROMPT.slice(start) : BASICS_PROMPT.slice(start, start + 1 + next);
}

describe('the 18 lessons', () => {
  test('each id and title appears exactly once, in order, as "Unit N, Lesson M: <title> (bN_lM)"', () => {
    let last = -1;
    for (const [id, title] of LESSONS) {
      const [, u, l] = /^b(\d)_l(\d)$/.exec(id);
      const header = `Unit ${u}, Lesson ${l}: ${title} (${id})`;
      assert.equal(BASICS_PROMPT.split(header).length - 1, 1, header);
      const at = BASICS_PROMPT.indexOf(header);
      assert.ok(at > last, `${id} comes after the lesson before it`);
      last = at;
    }
    assert.equal((BASICS_PROMPT.match(/^Unit \d, Lesson \d: /gm) || []).length, 18, 'no other lesson entries');
  });

  test('every lesson has a check with three options and a right answer, a try-this-today line, and a recap from lesson 2 on', () => {
    for (const [id] of LESSONS) {
      const e = entry(id);
      const m = /^- Check \(right answer: ([ABC])\): (.+)$/m.exec(e);
      assert.ok(m, `${id}: a check line`);
      const body = m[2];
      const [ia, ib, ic] = ['A) ', 'B) ', 'C) '].map((k) => body.indexOf(k));
      assert.ok(ia > 0 && ib > ia && ic > ib, `${id}: options A, B, C in order`);
      assert.match(body.slice(0, ia), /\?\s*$/, `${id}: the question ends with "?" before the options`);
      assert.match(e, /^- Try this today: /m, `${id}: try this today`);
      if (id === 'b1_l1') assert.doesNotMatch(e, /^- Recap:/m, 'the first lesson has a welcome, not a recap');
      else assert.match(e, /^- Recap: "Last time, you .+\."$/m, `${id}: a one-line recap`);
    }
  });

  test('the four safety lessons are marked and named in the COMPLETION rule', () => {
    for (const [id] of LESSONS) {
      const marked = /\(b\d_l\d\) SAFETY LESSON$/m.test(entry(id).split('\n')[0]);
      assert.equal(marked, SAFETY_LESSONS.includes(id), `${id}: SAFETY LESSON marker`);
    }
    assert.match(BASICS_PROMPT, /SAFETY LESSONS \(Unit 2 Lessons 3 and 4, Unit 5 Lessons 2 and 3\) the answer must also be right/);
  });

  test('the privacy lesson lists passwords, bank or card numbers and ID numbers as never-share, in its first reply', () => {
    const e = entry('b2_l3');
    assert.match(e, /In this first reply, list what never to share/);
    for (const re of [/passwords and PINs/, /bank or card numbers/, /Social Security, Medicare or other ID numbers/, /medical records/]) assert.match(e, re);
  });

  test('the fake-call lesson teaches hang up and call back on a number you already know', () => {
    const e = entry('b2_l4');
    assert.match(e, /Hang up and call back\. Call the person from your contacts, or on a number you already know\./);
    assert.match(e, /Hanging up won't hurt them/, 'the lesson does not assume the caller is a grandson');
    assert.match(e, /Even if their name or number shows on your screen, callers can fake that\./);
  });

  test('every quoted practice line is 12 words or fewer', () => {
    const lines = [...BASICS_PROMPT.matchAll(/^- (?:Practice|Practice line|Follow-up)[^:]*: .*$/gm)].map((m) => m[0]);
    assert.ok(lines.length >= 18, `found ${lines.length} practice lines`);
    for (const line of lines) {
      const quoted = /"([^"]+)"/.exec(line);
      if (!quoted) continue;
      const words = quoted[1].split(/\s+/).filter(Boolean).length;
      assert.ok(words <= 12, `${words} words: ${quoted[1]}`);
    }
  });
});

describe('content rules', () => {
  test('the practice line and follow-up shapes the clients can turn into chips', () => {
    assert.match(BASICS_PROMPT, /^Try asking me: "<the lesson's practice message>"$/m);
    assert.match(BASICS_PROMPT, /^Now try: "<the follow-up>"$/m);
  });

  test('the postcard rule is the only privacy picture', () => {
    assert.match(BASICS_PROMPT, /One picture for privacy: the postcard rule\. Never also compare a chatbot to a stranger, and never use the postcard rule's name for anything but what not to share\./);
    assert.doesNotMatch(BASICS_PROMPT, /stranger you just met/i);
  });

  test('Air Canada: the final two-sentence wording, and no "tribunal" in the story', () => {
    assert.match(entry('b1_l3'), /"An airline's website chatbot told a customer the wrong refund rule\. The airline was ordered to pay him the difference\."/);
    assert.doesNotMatch(BASICS_PROMPT, /small-claims|Canadian/);
  });

  test('copy steps for the phone, the Mac and the web', () => {
    const e = entry('b4_l1');
    assert.match(e, /press and hold my message, tap Copy/);
    assert.match(e, /"Right-click my message and choose Copy\./);
    assert.match(e, /If it says web browser: "Select the words of my message and copy them\./);
  });

  test('no phone number but 911 (other help lines wait for the safety core\'s vetted list)', () => {
    const numbers = BASICS_PROMPT.match(/\b\d{3}[-.\s]\d{3,4}(?:[-.\s]\d{4})?\b|\b1-8\d\d\b|\(\d{3}\)/g) || [];
    assert.deepEqual(numbers, []);
    for (const n of ['988', '741741', '1-800', '877', '833', '222-1222', '633-4227']) {
      assert.ok(!BASICS_PROMPT.includes(n), `${n} is not in the guide`);
    }
    assert.match(BASICS_PROMPT, /Give no other phone number, hotline or web address, even one you remember\. Crisis lines come only from the SAFETY CORE\./);
  });

  test('tool-neutral: names the four assistants and their makers, ranks none, gives no menu path', () => {
    assert.match(BASICS_PROMPT, /These skills work in ChatGPT, Claude, Gemini and Copilot\./);
    assert.match(BASICS_PROMPT, /Never rank them, never say which is best, and never say "use X instead"\./);
    assert.match(BASICS_PROMPT, /Say "look for the settings or privacy option" instead\./);
  });

  test('introduces no new bracket markers: only the client contract markers and the two lesson tags', () => {
    const allowed = new Set(['[KEY]', '[/KEY]', '[EX]', '[/EX]', '[Q]', '[/Q]', '[CHECK]', '[/CHECK]', '[LESSON_COMPLETE]']);
    for (const text of [BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, BASICS_EXPAND_NOTE]) {
      for (const [tok] of text.matchAll(/\[\/?[A-Z_]+\]/g)) assert.ok(allowed.has(tok), `unexpected marker ${tok}`);
      for (const [tag] of text.matchAll(/\[[A-Z_]+:[^\]]*\]/g)) {
        assert.ok(/^\[BASICS: Unit N, Lesson M\]$|^\[CURRICULUM: Basics Unit N, Lesson M\]$/.test(tag), `unexpected tag ${tag}`);
      }
    }
  });

  test('compile-time constants: no template residue, frozen module', () => {
    for (const text of [BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, BASICS_EXPAND_NOTE]) {
      assert.equal(typeof text, 'string');
      assert.ok(!text.includes('${'), 'no unexpanded template');
      assert.equal(text, text.trim(), 'no outer whitespace');
    }
    assert.ok(Object.isFrozen(guide));
  });

  test('the blocks appendix asks for [Q] cards and never [CHECK]', () => {
    assert.match(BASICS_BLOCKS_APPENDIX, /^\[Q\]\n<the question, one line>\nA\) <option>\nB\) <option>\nC\) <option>\nANS: <letter of the right option>\n\[\/Q\]$/m);
    assert.match(BASICS_BLOCKS_APPENDIX, /In Basics, never use \[CHECK\]\./);
  });
});

describe('the static prefix server.js sends', () => {
  const prose = systemBlocks.composeStaticWithAppFacts([BASICS_PROMPT, null, SAFETY_CORE]);
  const blocks = systemBlocks.composeStaticWithAppFacts([BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, SAFETY_CORE]);

  test('app facts then the safety core LAST, each once; cacheable; byte-stable', () => {
    for (const text of [prose, blocks]) {
      assert.ok(text.endsWith(`\n\n${APP_FACTS}\n\n${SAFETY_CORE}`));
      assert.equal(text.split(SAFETY_CORE).length - 1, 1);
      assert.ok(systemBlocks.isCacheable(text));
      assert.ok(text.startsWith(BASICS_PROMPT));
    }
    assert.equal(systemBlocks.composeStaticWithAppFacts([BASICS_PROMPT, BASICS_BLOCKS_APPENDIX, SAFETY_CORE]), blocks);
    assert.ok(blocks.includes(BASICS_BLOCKS_APPENDIX) && !prose.includes(BASICS_BLOCKS_APPENDIX));
  });

  test('carries none of the Deep-dive guide (server.js CURRICULUM_PROMPT)', () => {
    const server = fs.readFileSync(path.join(__dirname, '..', 'server.js'), 'utf8');
    const start = server.indexOf('const CURRICULUM_PROMPT = `') + 'const CURRICULUM_PROMPT = `'.length;
    const deep = server.slice(start, server.indexOf('`;', start));
    assert.ok(deep.length > 10000, 'found the Deep-dive guide');
    const firstLine = deep.split('\n')[0];
    assert.ok(!blocks.includes(firstLine), 'no Deep-dive opening line');
    assert.ok(!deep.includes('teaching BASICS'), 'and the Deep-dive guide carries no Basics text');
    assert.doesNotMatch(blocks, /demanding|A–D|Grade A/);
  });
});

describe('the runtime block', () => {
  test('platformFromCapabilities: optional platform tokens; the web widget counts as web; unknown is null', () => {
    assert.equal(platformFromCapabilities(['blocks_v1', 'platform_ios']), 'ios');
    assert.equal(platformFromCapabilities(['platform_mac', 'blocks_v1']), 'mac');
    assert.equal(platformFromCapabilities(['platform_web']), 'web');
    assert.equal(platformFromCapabilities(['club_v1']), 'web');
    assert.equal(platformFromCapabilities(['blocks_v1']), null);
    assert.equal(platformFromCapabilities(undefined), null);
    assert.equal(platformFromCapabilities('platform_mac'), null, 'a string is not a list');
  });

  test('date and device, byte-stable for one client on one day; "Explain more" adds its note', () => {
    const a = basicsRuntimeBlock({ currentDate: '2026-10-21', platform: 'mac', responseMode: 'concise' });
    const b = basicsRuntimeBlock({ currentDate: '2026-10-21', platform: 'mac', responseMode: 'balanced' });
    assert.equal(a, '## BASICS RUNTIME NOTE\nToday\'s date: 2026-10-21.\nDevice: Mac.');
    assert.equal(a, b, 'a typed turn and a [Q] tap send the same bytes');
    const deep = basicsRuntimeBlock({ currentDate: '2026-10-21', platform: 'mac', responseMode: 'deep' });
    assert.equal(deep, `${a}\n\n${BASICS_EXPAND_NOTE}`);
    assert.equal(basicsRuntimeBlock({ currentDate: '2026-10-21' }), '## BASICS RUNTIME NOTE\nToday\'s date: 2026-10-21.');
    assert.equal(basicsRuntimeBlock({ platform: 'nope' }), '## BASICS RUNTIME NOTE');
    assert.equal(basicsRuntimeBlock(), '## BASICS RUNTIME NOTE');
  });
});
