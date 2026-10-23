'use strict';

// AUD-18 (audit 2026-10): the model put the right answer of a lesson's
// multiple-choice check at B about 79% of the time. lib/quizShuffle.js puts
// the options of each [Q] block in a stable server order and rewrites ANS.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createQuizShuffler, shuffleQuizzes, shuffleQuizSpan, analyzeInterior, optionOrder, MAX_SPAN_CHARS,
} = require('../lib/quizShuffle');
const { parseQuizInterior, validateBlocks } = require('../lib/blockMarkup');
const { blocks: REAL_BLOCKS } = require('./fixtures/quizBlocksAudit2026-10.json');

const Q_RE = /\[Q\]\n?([\s\S]*?)\[\/Q\]/g;

/** The server's parse of every [Q] in a reply. */
function quizzes(text) {
  return [...String(text).matchAll(Q_RE)].map((m) => parseQuizInterior(m[1]));
}

/** iOS BlockParser.parseQuiz, line for line (ChatFeature/MessageBlocks.swift). */
function iosParseQuiz(interior) {
  const stem = [];
  const options = [];
  let answerIndex = null;
  for (const raw of interior.split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    if (line.length > 2 && /[A-D]/.test(line[0]) && line.slice(1).startsWith(') ')) {
      options.push(line.slice(2).trim());
      continue;
    }
    if (line.startsWith('ANS:')) {
      const letter = line.slice(4).trim();
      if (letter.length === 1 && /[A-D]/.test(letter)) answerIndex = letter.charCodeAt(0) - 65;
      continue;
    }
    if (options.length === 0 && answerIndex === null) stem.push(line);
  }
  return { stem: stem.join(' '), options, answerIndex };
}

const answerText = (q) => q.options[q.answerIndex];

function streamed(text, sizes) {
  const s = createQuizShuffler();
  let out = '';
  let i = 0;
  let k = 0;
  while (i < text.length) {
    const n = sizes[k % sizes.length];
    out += s.push(text.slice(i, i + n));
    i += n;
    k += 1;
  }
  return out + s.flush();
}

const SAMPLE = 'Good — tokens first.\n\n[KEY]Models read numbers, not words.[/KEY]\n\n[Q]\nWhat is a token in an LLM?\n' +
  'A) A single word, always — the model splits on spaces\n' +
  'B) A chunk of text converted to a number — could be a word, part of a word, or punctuation\n' +
  "C) A copy of the original sentence stored in the model's memory\nANS: B\n[/Q]";

describe('quizShuffle: the order (AUD-18)', () => {
  test('reorders the options, rewrites ANS to the same answer, changes nothing else', () => {
    const out = shuffleQuizzes(SAMPLE);
    assert.notEqual(out, SAMPLE, 'this stem is not in the identity order');
    const [before] = quizzes(SAMPLE);
    const [after] = quizzes(out);
    assert.equal(after.wellFormed, true);
    assert.equal(answerText(after), answerText(before), 'ANS names the same option text');
    assert.notEqual(after.answerIndex, before.answerIndex, 'the right answer moved off B');
    assert.deepEqual([...after.options].sort(), [...before.options].sort(), 'same options');
    assert.equal(after.stem, before.stem);
    // Text outside the block, the line layout and the letters are untouched.
    assert.equal(out.slice(0, out.indexOf('[Q]')), SAMPLE.slice(0, SAMPLE.indexOf('[Q]')));
    assert.equal(out.split('\n').length, SAMPLE.split('\n').length);
    assert.deepEqual(out.split('\n').map((l) => l.slice(0, 3)).filter((p) => /^[A-D]\) $/.test(p)), ['A) ', 'B) ', 'C) ']);
    assert.ok(validateBlocks(out).ok, validateBlocks(out).problems.join('; '));
  });

  test('deterministic: the same stem and options always come out in the same order, whatever order the model used', () => {
    const out = shuffleQuizzes(SAMPLE);
    assert.equal(shuffleQuizzes(SAMPLE), out);
    // The same check with the model's options in another order.
    const lines = SAMPLE.split('\n');
    const a = lines.findIndex((l) => l.startsWith('A) '));
    const permuted = [...lines];
    permuted[a] = 'A) ' + lines[a + 2].slice(3);
    permuted[a + 1] = 'B) ' + lines[a].slice(3);
    permuted[a + 2] = 'C) ' + lines[a + 1].slice(3);
    permuted[a + 3] = 'ANS: C';
    assert.equal(answerText(quizzes(permuted.join('\n'))[0]), answerText(quizzes(SAMPLE)[0]));
    assert.equal(shuffleQuizzes(permuted.join('\n')), out);
  });

  test('idempotent: reordering a reordered block (a word-for-word re-ask from history) changes nothing', () => {
    const once = shuffleQuizzes(SAMPLE);
    assert.equal(shuffleQuizzes(once), once);
    for (const { block } of REAL_BLOCKS) {
      const o = shuffleQuizSpan(block);
      assert.equal(shuffleQuizSpan(o), o);
    }
  });

  test('real audit checks (all answered B, all longest-is-right): same answer text, parsed alike by the server and iOS', () => {
    const letters = [];
    for (const { source, block } of REAL_BLOCKS) {
      const out = shuffleQuizSpan(block);
      const interior = out.slice(3, -4);
      const server = parseQuizInterior(interior.replace(/^\n/, ''));
      const ios = iosParseQuiz(interior);
      const before = parseQuizInterior(block.slice(3, -4).replace(/^\n/, ''));
      assert.equal(server.wellFormed, true, source);
      assert.equal(answerText(server), answerText(before), source);
      assert.deepEqual(ios.options, server.options, `${source}: iOS sees the same options`);
      assert.equal(ios.answerIndex, server.answerIndex, `${source}: iOS grades the same answer`);
      assert.equal(ios.stem, server.stem, source);
      letters.push(String.fromCharCode(65 + server.answerIndex));
    }
    // Pinned so a change to the order is a deliberate, reviewed change.
    assert.deepEqual(letters, ['A', 'A', 'A', 'B', 'C', 'C']);
  });

  test('spread: with the answer always written at B, it lands on every letter about equally often', () => {
    const counts = { A: 0, B: 0, C: 0, D: 0 };
    const counts4 = { A: 0, B: 0, C: 0, D: 0 };
    for (let i = 0; i < 600; i += 1) {
      const stem = `Practice question ${i}: which statement about model ${i % 7} is accurate?`;
      const three = `[Q]\n${stem}\nA) Wrong idea ${i}\nB) Right idea ${i}\nC) Other wrong idea ${i}\nANS: B\n[/Q]`;
      const four = `[Q]\n${stem}\nA) Wrong ${i}\nB) Right ${i}\nC) Other ${i}\nD) Fourth ${i}\nANS: B\n[/Q]`;
      const q3 = quizzes(shuffleQuizzes(three))[0];
      const q4 = quizzes(shuffleQuizzes(four))[0];
      assert.equal(answerText(q3), `Right idea ${i}`);
      assert.equal(answerText(q4), `Right ${i}`);
      counts[String.fromCharCode(65 + q3.answerIndex)] += 1;
      counts4[String.fromCharCode(65 + q4.answerIndex)] += 1;
    }
    for (const l of ['A', 'B', 'C']) assert.ok(counts[l] > 160 && counts[l] < 240, `3-option ${l}: ${JSON.stringify(counts)}`);
    assert.equal(counts.D, 0);
    for (const l of ['A', 'B', 'C', 'D']) assert.ok(counts4[l] > 110 && counts4[l] < 190, `4-option ${l}: ${JSON.stringify(counts4)}`);
  });

  test('2- and 4-option checks are reordered too', () => {
    const two = '[Q]\nIs a confident answer always right?\nA) Yes, confidence tracks accuracy\nB) No, fluency is not accuracy\nANS: B\n[/Q]';
    const out = shuffleQuizzes(two);
    assert.equal(answerText(quizzes(out)[0]), 'No, fluency is not accuracy');
    assert.equal(optionOrder('x', ['a', 'b', 'c', 'd']).slice().sort().join(''), '0123');
  });
});

describe('quizShuffle: what passes through untouched', () => {
  const untouched = {
    'no ANS line': '[Q]\nPick one\nA) one\nB) two\n[/Q]',
    'ANS out of range': '[Q]\nPick one\nA) one\nB) two\nANS: C\n[/Q]',
    'one option': '[Q]\nPick one\nA) one\nANS: A\n[/Q]',
    'letters out of order': '[Q]\nPick one\nA) one\nC) two\nB) three\nANS: B\n[/Q]',
    'letters skip': '[Q]\nPick one\nA) one\nB) two\nD) three\nANS: B\n[/Q]',
    'option after ANS': '[Q]\nPick one\nA) one\nB) two\nANS: A\nC) three\n[/Q]',
    'two ANS lines': '[Q]\nPick one\nA) one\nB) two\nANS: A\nANS: B\n[/Q]',
    'prose between options': '[Q]\nPick one\nA) one\nmore about one\nB) two\nANS: A\n[/Q]',
    'prose after ANS': '[Q]\nPick one\nA) one\nB) two\nANS: A\nWhy? Think.\n[/Q]',
    'no stem': '[Q]\nA) one\nB) two\nANS: A\n[/Q]',
    'duplicate options': '[Q]\nPick one\nA) same\nB) same\nC) other\nANS: C\n[/Q]',
    'tab after the letter (iOS would not see an option)': '[Q]\nPick one\nA)\tone\nB)\ttwo\nANS: A\n[/Q]',
    'a marker inside': '[Q]\nPick one [KEY]x[/KEY]\nA) one\nB) two\nANS: A\n[/Q]',
    'a nested [Q]': '[Q]\nPick one\n[Q]\nA) one\nB) two\nANS: A\n[/Q]',
    'lowercase ans': '[Q]\nPick one\nA) one\nB) two\nans: A\n[/Q]',
    '"All of the above"': '[Q]\nWhich are risks?\nA) Bias\nB) Hallucination\nC) All of the above\nANS: C\n[/Q]',
    '"None of these"': '[Q]\nWhich is safe?\nA) Sharing a password\nB) Pasting private data\nC) None of these\nANS: C\n[/Q]',
    '"Both A and B"': '[Q]\nWhich are true?\nA) Models predict tokens\nB) Models can be wrong\nC) Both A and B\nANS: C\n[/Q]',
    'a stem that names letters': '[Q]\nIs option A or option B the better prompt?\nA) "Summarize this"\nB) "Summarize this for a 9th grader in 3 bullets"\nANS: B\n[/Q]',
    'an option that cites another': '[Q]\nPick the best fix\nA) Add sources\nB) Ask twice\nC) Same as A) but also ask twice\nANS: C\n[/Q]',
  };
  for (const [name, block] of Object.entries(untouched)) {
    test(`${name}: byte for byte`, () => {
      const text = `Before.\n\n${block}\n\nAfter.`;
      assert.equal(shuffleQuizzes(text), text);
      assert.equal(streamed(text, [1]), text);
      assert.equal(streamed(text, [5, 2, 9]), text);
    });
  }

  test('an unclosed [Q] and a partial "[Q" tail are released as written at the end', () => {
    for (const text of ['Teach.\n\n[Q]\nPick one\nA) one\nB) two\nANS: A', 'Teach. [', 'Teach. [Q', 'Look [at] this [Quote]']) {
      assert.equal(shuffleQuizzes(text), text);
      assert.equal(streamed(text, [1]), text);
    }
  });

  test('a [Q] that does not close within MAX_SPAN_CHARS passes through, and a later block is still reordered', () => {
    const runaway = `[Q]\n${'very long stem '.repeat(Math.ceil(MAX_SPAN_CHARS / 15))}\n[/Q]`;
    const text = `${runaway}\n\n${SAMPLE}`;
    const expected = `${runaway}\n\n${shuffleQuizzes(SAMPLE)}`;
    assert.equal(shuffleQuizzes(text), expected);
    for (const sizes of [[1], [7], [MAX_SPAN_CHARS - 1], [3, MAX_SPAN_CHARS]]) {
      assert.equal(streamed(text, sizes), expected, `sizes ${sizes}`);
    }
  });

  test('analyzeInterior accepts blank lines and indentation between the parts', () => {
    const q = analyzeInterior('\n  Pick one\n\n  A) one\n  B) two\n\n  ANS: B  \n');
    assert.ok(q);
    assert.equal(q.answerIndex, 1);
    const out = shuffleQuizSpan('[Q]\n  Pick one\n\n  A) one\n  B) two\n\n  ANS: B  \n[/Q]');
    assert.ok(/\n {2}A\) (?:one|two)\n {2}B\) (?:one|two)\n\n {2}ANS: [AB] {2}\n\[\/Q\]$/.test(out), JSON.stringify(out));
    assert.equal(answerText(quizzes(out)[0]), 'two');
  });
});

describe('quizShuffle: chunk boundaries', () => {
  const REPLY = `Nice — you caught the key move. One more idea.\n\n${REAL_BLOCKS[0].block}\n\nTake your time [no rush].\n\n${REAL_BLOCKS[4].block}`;

  test('every two-way split of a reply equals the one-shot result', () => {
    const oneShot = shuffleQuizzes(REPLY);
    assert.notEqual(oneShot, REPLY);
    for (let cut = 0; cut <= REPLY.length; cut += 1) {
      const s = createQuizShuffler();
      const out = s.push(REPLY.slice(0, cut)) + s.push(REPLY.slice(cut)) + s.flush();
      assert.equal(out, oneShot, `cut at ${cut}`);
    }
  });

  test('random chunkings (fuzz) equal the one-shot result, and nothing of a block leaks before its [/Q]', () => {
    const oneShot = shuffleQuizzes(REPLY);
    let seed = 1234;
    const rand = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (let run = 0; run < 300; run += 1) {
      const s = createQuizShuffler();
      let out = '';
      let i = 0;
      while (i < REPLY.length) {
        const n = 1 + Math.floor(rand() * 40);
        const piece = s.push(REPLY.slice(i, i + n));
        i += n;
        out += piece;
        // A partial block is never emitted: every "[Q]" that is out has its "[/Q]".
        const opens = out.split('[Q]').length - 1;
        const closes = out.split('[/Q]').length - 1;
        assert.equal(opens, closes, `run ${run}: block emitted before its close`);
      }
      out += s.flush();
      assert.equal(out, oneShot, `run ${run}`);
    }
  });
});
