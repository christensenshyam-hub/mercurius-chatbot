'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { createReflow, reflowText, reflowLimit } = require('../lib/airyReflow');

/** Feed `text` through a streaming reflower in chunks of `size` chars. */
function streamed(text, limit, size) {
  const r = createReflow({ limit });
  let out = '';
  for (let i = 0; i < text.length; i += size) out += r.push(text.slice(i, i + size));
  return out + r.flush();
}

describe('airyReflow', () => {
  test('splits a packed paragraph at the sentence limit', () => {
    assert.equal(reflowText('One. Two. Three. Four.', 2), 'One. Two.\n\nThree. Four.');
    // limit 1: every sentence its own paragraph (single capitals are treated
    // as initials by the abbreviation guard, so use real words)
    assert.equal(reflowText('Go now. Stop it. Look up.', 1), 'Go now.\n\nStop it.\n\nLook up.');
  });

  test('respects existing paragraph breaks and resets the counter', () => {
    const text = 'One. Two.\n\nThree. Four.';
    assert.equal(reflowText(text, 2), text);
  });

  test('limit 3 allows three-sentence paragraphs', () => {
    const text = 'One. Two. Three.\n\nFour.';
    assert.equal(reflowText(text, 3), text);
    assert.equal(reflowText('One. Two. Three. Four.', 3), 'One. Two. Three.\n\nFour.');
  });

  test('question and exclamation terminals count', () => {
    assert.equal(reflowText('Really? Yes! And then some.', 2), 'Really? Yes!\n\nAnd then some.');
  });

  test('decimals and abbreviations do not split', () => {
    assert.equal(reflowText('GPT-4 has 1.8 trillion parameters. It is big. Dr. Smith agrees. Fine.', 2),
      'GPT-4 has 1.8 trillion parameters. It is big.\n\nDr. Smith agrees. Fine.');
  });

  test('bullet lists are exempt', () => {
    const text = 'Intro.\n- one bullet. two sentences. three here.\n- another.\nOutro one. Outro two. Outro three.';
    const out = reflowText(text, 2);
    assert.ok(out.includes('- one bullet. two sentences. three here.'), 'bullet line untouched');
  });

  test('code fences are exempt', () => {
    const text = 'Look.\n\n```\nx = 1. y = 2. z = 3. w = 4.\n```\n\nDone. Really. Truly.';
    const out = reflowText(text, 2);
    assert.ok(out.includes('x = 1. y = 2. z = 3. w = 4.'), 'fence interior untouched');
    assert.ok(out.includes('Done. Really.\n\nTruly.'), 'prose after fence reflowed');
  });

  test('blocks_v1 spans ([KEY]/[EX]/[Q]) are exempt and tags survive', () => {
    const q = '[Q]\nWhich is a hallucination? Think hard. Answer well.\nA) This one. Really. Truly. Fully.\nB) That one.\nANS: A\n[/Q]';
    const text = `Teach one. Teach two.\n\n[KEY]Key one. Key two. Key three.[/KEY]\n\n[EX]Ex one. Ex two. Ex three. Ex four.[/EX]\n\n${q}`;
    const out = reflowText(text, 2);
    assert.ok(out.includes('[KEY]Key one. Key two. Key three.[/KEY]'), 'KEY interior untouched');
    assert.ok(out.includes('[EX]Ex one. Ex two. Ex three. Ex four.[/EX]'), 'EX interior untouched');
    assert.ok(out.includes(q), 'Q interior untouched (option lines + ANS intact)');
    // Chunk independence holds with block spans too.
    const oneShot = reflowText(text, 2);
    for (const size of [1, 3, 7, 50]) {
      assert.equal(streamed(text, 2, size), oneShot, `chunk size ${size}`);
    }
  });

  test('[CHECK] spans are exempt and tags survive', () => {
    const text = 'Teach one. Teach two. [CHECK]Why is this true? Think hard. Answer well.[/CHECK]';
    const out = reflowText(text, 2);
    assert.ok(out.includes('[CHECK]Why is this true? Think hard. Answer well.[/CHECK]'), 'check span untouched');
  });

  test('[LESSON_COMPLETE] survives and stays server-strippable', () => {
    // The single newline before the marker may be upgraded to a paragraph
    // break (the paragraph hit its limit) — that is contract-compatible:
    // the marker stays on its own line and the server's end-anchored strip
    // regex tolerates the extra newline.
    const out = reflowText('Done one. Done two.\n[LESSON_COMPLETE]', 2);
    assert.ok(/\n\[LESSON_COMPLETE\]$|\n\n\[LESSON_COMPLETE\]$/.test(out), `marker on its own line: ${JSON.stringify(out)}`);
    assert.ok(/(?:\n?\s*\[LESSON_COMPLETE\]\s*)+$/.test(out), 'lessonOutcome strip regex still matches');
  });

  test('CHUNK-BOUNDARY INDEPENDENCE: any chunking equals one-shot', () => {
    const text = 'First sentence here. Second one lands. Third begins now! Fourth asks why? ' +
      'Fifth continues.\n\nNew para one. New para two. New para three. ' +
      '[CHECK]Q one? Q two.[/CHECK] After check. More text. Even more.\n' +
      '- bullet a. still bullet.\n- bullet b.\n\n```\ncode. code. code. code.\n```\nTail one. Tail two. Tail three.';
    const oneShot = reflowText(text, 2);
    for (const size of [1, 2, 3, 5, 7, 11, 50, text.length]) {
      assert.equal(streamed(text, 2, size), oneShot, `chunk size ${size} must match one-shot`);
    }
  });

  test('abbreviations hold at every chunk boundary (every two-way split equals one-shot)', () => {
    const texts = [
      'He sued. See Mata v. Avianca for more. It was big.',
      'Dr. Smith agrees. Mr. Jones does not. Use e.g. this one. Or i.e. that. Fine.',
      'J. Buolamwini led it. The U.S. agreed. Inc. too. Done now.',
    ];
    for (const text of texts) {
      for (const limit of [1, 2, 3]) {
        const oneShot = reflowText(text, limit);
        for (let cut = 0; cut <= text.length; cut += 1) {
          const r = createReflow({ limit });
          const out = r.push(text.slice(0, cut)) + r.push(text.slice(cut)) + r.flush();
          assert.equal(out, oneShot, `limit ${limit}, cut at ${cut}: ${JSON.stringify(text)}`);
        }
      }
    }
    assert.equal(reflowText('He sued. See Mata v. Avianca for more. It was big.', 2), 'He sued. See Mata v. Avianca for more.\n\nIt was big.');
  });

  test('reflowLimit: 3 for curriculum/deep, 2 otherwise, debate exempt', () => {
    assert.equal(reflowLimit({ isCurriculum: true, responseMode: 'balanced' }), 3);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'deep' }), 3);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'concise' }), 2);
    assert.equal(reflowLimit({ isCurriculum: false, responseMode: 'concise', mode: 'debate' }), Infinity);
    // Infinity limit = pass-through
    const debate = '**Claim:** A. **Warrant:** B. **Impact:** C. **Rebuttal:** D.';
    assert.equal(reflowText(debate, Infinity), debate);
  });

  test('empty and marker-only inputs are stable', () => {
    assert.equal(reflowText('', 2), '');
    assert.equal(reflowText('[LESSON_COMPLETE]', 2), '[LESSON_COMPLETE]');
  });
});

// AUD-17 (audit 2026-10): "2." at the start of a line was read as a sentence
// end, so a tight numbered list split into "2.\n\nType the prompt", and the
// Discussion rubric arrived grouped 2-2-1 with a stray "both?" paragraph.
describe('airyReflow: numbered lists and score lines (AUD-17)', () => {
  const fixture = require('./fixtures/reflowAudit2026-10.json');
  const SPLIT_MARKER_RE = /(^|\n)\s{0,3}\d{1,3}[.)]\n\n/;

  /** Every chunking of `text` must equal the one-shot reflow. */
  function assertChunkIndependent(text, limit) {
    const oneShot = reflowText(text, limit);
    for (const size of [1, 2, 3, 4, 5, 7, 11, 13, 64, text.length || 1]) {
      assert.equal(streamed(text, limit, size), oneShot, `chunk size ${size}`);
    }
    return oneShot;
  }

  test('the audit repro: tight numbered lists stay whole at limits 2 and 3', () => {
    const steps = 'Steps:\n\n1. Open the app\n2. Type the prompt\n3. Read the answer\n4. Check a source';
    for (const limit of [2, 3]) {
      assert.equal(assertChunkIndependent(steps, limit), steps, `limit ${limit}`);
    }
    const two = 'Two:\n\n1. First thing\n2. Second thing';
    assert.equal(assertChunkIndependent(two, 2), two);
  });

  test('"1)" markers and indented items stay whole too', () => {
    const text = 'Try this:\n1) Open the app\n2) Type the prompt\n3) Read the answer\n   4. Check a source';
    for (const limit of [2, 3]) assert.equal(assertChunkIndependent(text, limit), text);
  });

  test('a list item keeps its own sentences together; the prose around it still reflows', () => {
    const text = 'Read this. Then this. And this.\n1. Open the app. Look around. Tap once.\n2. Type. Wait. Read.\n\nAfter one. After two. After three.';
    const out = assertChunkIndependent(text, 2);
    assert.equal(out, 'Read this. Then this.\n\nAnd this.\n1. Open the app. Look around. Tap once.\n2. Type. Wait. Read.\n\nAfter one. After two.\n\nAfter three.');
    assert.ok(!SPLIT_MARKER_RE.test(out));
  });

  test('numbers that are not list markers are still prose', () => {
    // A decimal at the start of a line, and a 4-digit year, are sentences.
    assert.equal(reflowText('1.5 million people. That is a lot. Really.', 2), '1.5 million people. That is a lot.\n\nReally.');
    assert.equal(reflowText('2020. That year. It changed.', 2), '2020. That year.\n\nIt changed.');
    // Mid-line numbers are untouched by the list rule.
    assert.equal(reflowText('Step 2. Then 3. Then 4.', 2), 'Step 2. Then 3.\n\nThen 4.');
  });

  test('real lesson exercises from the audit keep their numbered steps whole', () => {
    for (const ex of fixture.numberedLists) {
      assert.ok(SPLIT_MARKER_RE.test(ex.recorded), `${ex.source}: the old reflow split a marker`);
      const out = assertChunkIndependent(ex.raw, ex.limit);
      assert.ok(!SPLIT_MARKER_RE.test(out), `${ex.source}: ${JSON.stringify(out)}`);
      assert.ok(/\n1\. .+\n2\. .+\n3\. .+/.test(out), `${ex.source}: three whole items`);
    }
  });

  test('the real Discussion score blocks: five whole lines, one hard break each, no orphans', () => {
    for (const block of fixture.scoreBlocks) {
      const out = assertChunkIndependent(block.raw, block.limit);
      const lines = out.split('\n');
      const scoreLines = lines.filter((l) => /^\*\*[A-Za-z ]+: \d\/5\*\*/.test(l));
      assert.equal(scoreLines.length, 5, `${block.source}: ${JSON.stringify(out)}`);
      // Consecutive lines, no blank line or stray fragment between them.
      const first = lines.indexOf(scoreLines[0]);
      assert.deepEqual(lines.slice(first, first + 5), scoreLines, `${block.source}: rubric is one block`);
      // Every rubric line but the last ends in a markdown hard break, so
      // MarkdownUI (soft break = space) shows one score per line.
      for (const l of scoreLines.slice(0, 4)) assert.ok(l.endsWith('  '), `hard break: ${JSON.stringify(l)}`);
      // The Overall line is never split.
      assert.ok(lines.some((l) => /^\*\*Overall: \d+\/25\*\* — Grade: Solid\. .+[.?]$/.test(l)), 'Overall line whole');
      // Nothing changed but whitespace.
      assert.equal(out.replace(/\s+/g, ' '), block.raw.replace(/\s+/g, ' '));
    }
    const c03 = reflowText(fixture.scoreBlocks[2].raw, 2);
    assert.ok(c03.includes('partial feedback? final grades? both?  \n**Evidence: 1/5**'), 'no orphaned "both?"');
    assert.ok(!/\n\nboth\?/.test(c03));
  });

  test('score lines: "**Label:** n/5" form, and a bold heading is not a score line', () => {
    const alt = '**Logic:** 3/5 — Plausible. Needs more.\n**Originality:** 2/5 — Standard. Common.\nNext one. Then two. Then three.';
    const out = assertChunkIndependent(alt, 2);
    assert.ok(out.startsWith('**Logic:** 3/5 — Plausible. Needs more.  \n**Originality:** 2/5 — Standard. Common.  \nNext one. Then two.\n\nThen three.'), JSON.stringify(out));
    const heading = '**Problem 1: What AI grading optimizes for.**\nCurrent systems reward length. They predict scores.';
    assert.equal(assertChunkIndependent(heading, 2), '**Problem 1: What AI grading optimizes for.**\nCurrent systems reward length.\n\nThey predict scores.');
  });

  test('the hard break is idempotent and never stacks on existing trailing spaces', () => {
    for (const block of fixture.scoreBlocks) {
      const once = reflowText(block.raw, block.limit);
      assert.equal(reflowText(once, block.limit), once);
    }
    assert.equal(reflowText('**Nuance: 2/5** — ok. \n**Logic: 3/5** — fine.', 2), '**Nuance: 2/5** — ok.  \n**Logic: 3/5** — fine.');
  });

  test('chunk fuzz: random chunkings of lists, rubrics and prose equal the one-shot reflow', () => {
    const corpus = [
      ...fixture.scoreBlocks.map((b) => b.raw),
      ...fixture.numberedLists.map((b) => b.raw),
      'Steps:\n1. Open. Now.\n2) Tap. Here.\n**Claim: 4/5** — Good. Very.\n- bullet. two.\nProse one. Prose two. Prose three.\n12. Twelve. Items.',
    ];
    let seed = 17;
    const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (const text of corpus) {
      for (const limit of [2, 3]) {
        const oneShot = reflowText(text, limit);
        for (let run = 0; run < 40; run++) {
          const r = createReflow({ limit });
          let out = '';
          let i = 0;
          while (i < text.length) {
            const n = 1 + Math.floor(rand() * 9);
            out += r.push(text.slice(i, i + n));
            i += n;
          }
          out += r.flush();
          assert.equal(out, oneShot, `limit ${limit} run ${run}`);
        }
      }
    }
  });
});

// keepQuotes (the Basics track, 2026-10): a short quoted span on one line is
// never split, so a two-sentence practice line stays one chip-able line.
describe('airyReflow keepQuotes', () => {
  test('a quoted question in the middle of a sentence is not a sentence end (UX review 2026-10-22)', () => {
    const text = 'You did well. You asked "what does this mean?" and then "by when?" to get the date. That works.';
    assert.equal(reflowText(text, 2, { keepQuotes: true }), 'You did well. You asked "what does this mean?" and then "by when?" to get the date.\n\nThat works.');
    assert.equal(reflowText(text, 2), 'You did well. You asked "what does this mean?"\n\nand then "by when?" to get the date.\n\nThat works.', 'the default mode is unchanged (it breaks mid-sentence)');
    for (let size = 1; size <= 9; size++) {
      const r = createReflow({ limit: 2, keepQuotes: true });
      let out = '';
      for (let i = 0; i < text.length; i += size) out += r.push(text.slice(i, i + size));
      assert.equal(out + r.flush(), reflowText(text, 2, { keepQuotes: true }), `chunk ${size}`);
    }
    assert.equal(reflowText('One. Two.\nthree. Four.', 2, { keepQuotes: true }), 'One. Two.\n\nthree. Four.', 'a line break still ends it');
    // Merge of PR #46 (AUD-17 score lines) with #54: a terminal before the
    // line's prefix classifies makes it prose here too, never a score line.
    const notScore = '**Wait? no: 3/5** — ok. Two. Three.\nNext.';
    assert.equal(reflowText(notScore, 2, { keepQuotes: true }), '**Wait? no: 3/5** — ok. Two.\n\nThree.\nNext.');
  });

  const { MAX_HELD_QUOTE_CHARS } = require('../lib/airyReflow');
  const PRACTICE = 'Here is one idea. Try asking me: "Plan dinner for 6. One is vegetarian, one hates anything green." Then we go on. And more here.';

  test('off by default: the same text splits inside the quote, exactly as before', () => {
    assert.equal(
      reflowText(PRACTICE, 2),
      'Here is one idea. Try asking me: "Plan dinner for 6.\n\nOne is vegetarian, one hates anything green." Then we go on.\n\nAnd more here.',
    );
  });

  test('on: the quote stays whole and the break moves to the first boundary after it', () => {
    assert.equal(
      reflowText(PRACTICE, 2, { keepQuotes: true }),
      'Here is one idea. Try asking me: "Plan dinner for 6. One is vegetarian, one hates anything green."\n\nThen we go on. And more here.',
    );
    // Curly quotes too.
    assert.equal(
      reflowText('One. Try asking me: “Is this a scam? What should I do?” Two. Three.', 2, { keepQuotes: true }),
      'One. Try asking me: “Is this a scam? What should I do?”\n\nTwo. Three.',
    );
  });

  test('on: a long quoted span (a letter or an email) reflows as usual', () => {
    const long = 'x'.repeat(MAX_HELD_QUOTE_CHARS);
    const text = `Intro. "${long}. More words here. Even more." End.`;
    assert.ok(reflowText(text, 2, { keepQuotes: true }).includes(`${long}.\n\nMore words here.`));
  });

  test('on: a short quote never holds a paragraph past MAX_HELD_SENTENCES', () => {
    const { MAX_HELD_SENTENCES } = require('../lib/airyReflow');
    assert.equal(MAX_HELD_SENTENCES, 4);
    const text = '"Hi. Can we talk? It is quick. Let us pick one. Thanks. Bye."';
    assert.equal(reflowText(text, 2, { keepQuotes: true }), '"Hi. Can we talk? It is quick. Let us pick one.\n\nThanks. Bye."');
  });

  test('on: a newline ends an unbalanced quote, so it can never hold a whole reply', () => {
    const text = 'He said "wait. Then.\nOne. Two. Three.';
    assert.equal(reflowText(text, 2, { keepQuotes: true }), 'He said "wait. Then.\nOne.\n\nTwo. Three.');
  });

  test('on: lists, [Q] cards and fences are untouched', () => {
    const text = '- "A. B. C." item\n\n[Q]\nWhy "x. y. z"?\nA) a\nB) b\nC) c\nANS: A\n[/Q]';
    assert.equal(reflowText(text, 1, { keepQuotes: true }), text);
  });

  test('on: CHUNK-BOUNDARY INDEPENDENCE', () => {
    const texts = [
      PRACTICE,
      'Last time, you asked a question. Ask me a real question from your week. If nothing comes to mind, try asking me: "What\'s a good card game for 4 people, ages 8 to 80?"',
      '“Open. Still open.” Out. One. Two. "Again. And." Done.\n\nNext para "q. r." s. t.',
    ];
    for (const text of texts) {
      const once = reflowText(text, 2, { keepQuotes: true });
      for (const size of [1, 2, 3, 5, 7, 13, 64]) {
        const r = createReflow({ limit: 2, keepQuotes: true });
        let out = '';
        for (let i = 0; i < text.length; i += size) out += r.push(text.slice(i, i + size));
        assert.equal(out + r.flush(), once, `chunk ${size}`);
      }
    }
  });
});

// numberedLists (the Basics track, 2026-10): "1." opening a line is a list
// marker, so numbered lines are exempt like bullets. AUD-17 made that the
// rule for every caller, so the option is still accepted but changes nothing.
describe('airyReflow numberedLists', () => {
  const RULES = 'Here are your safety rules:\n\n1. It\'s a program. It can sound kind, but no one is typing back.\n2. Use the postcard rule. If you would not write it on a postcard, do not type it.\n3. Check what matters. Health answers get checked.';

  test('off: the old gap is closed for every caller (AUD-17), so the option changes nothing', () => {
    // Before AUD-17 the default mode read "1." as a sentence and split this
    // list mid-item ("2.\n\nUse the postcard rule"); the line-start list rule
    // now holds without the option, so both modes give the same bytes.
    assert.equal(reflowText(RULES, 2), RULES);
    assert.equal(reflowText(RULES, 2), reflowText(RULES, 2, { numberedLists: true }));
    const text = '1) Step one. Still one.\n12. Step twelve. Still twelve.\n\nAfter. Two. Three.';
    assert.equal(reflowText(text, 2), reflowText(text, 2, { numberedLists: true }));
  });

  test('on: numbered lines pass through untouched; prose after them reflows as usual', () => {
    assert.equal(reflowText(RULES, 2, { numberedLists: true }), RULES);
    const text = '1) Step one. Still one.\n12. Step twelve. Still twelve.\n\nAfter. Two. Three.';
    assert.equal(reflowText(text, 2, { numberedLists: true }), '1) Step one. Still one.\n12. Step twelve. Still twelve.\n\nAfter. Two.\n\nThree.');
    // A year or a long number opening a line is not a list marker.
    assert.equal(reflowText('2023. It was a year. And more.', 2, { numberedLists: true }), '2023. It was a year.\n\nAnd more.');
  });

  test('on: CHUNK-BOUNDARY INDEPENDENCE', () => {
    const once = reflowText(RULES, 2, { numberedLists: true, keepQuotes: true });
    for (const size of [1, 2, 3, 5, 8, 64]) {
      const r = createReflow({ limit: 2, numberedLists: true, keepQuotes: true });
      let out = '';
      for (let i = 0; i < RULES.length; i += size) out += r.push(RULES.slice(i, i + size));
      assert.equal(out + r.flush(), once, `chunk ${size}`);
    }
  });
});
