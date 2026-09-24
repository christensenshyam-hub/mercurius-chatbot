'use strict';

// Tests for lib/safetyCore — the shared safety block appended to the end of
// every cached system prompt. These pin the things that must never drift by
// accident: the hotline numbers, the exact client contract markers, the
// absence of any NEW bracket marker, the size budget, and purity.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const MODULE_PATH = path.join(__dirname, '..', 'lib', 'safetyCore.js');
const safetyCore = require(MODULE_PATH);
const { SAFETY_CORE, SAFETY_CORE_TAGGED } = safetyCore;

// The only markers the clients strip and act on. Anything else in brackets
// would leak into the stream verbatim (or be mis-parsed by lib/blockMarkup).
const CONTRACT_MARKERS = ['[CHECK]', '[Q]', '[LESSON_COMPLETE]'];

describe('SAFETY_CORE shape', () => {
  test('is a non-empty plain string with no leading/trailing whitespace', () => {
    assert.equal(typeof SAFETY_CORE, 'string');
    assert.ok(SAFETY_CORE.length > 0);
    assert.equal(SAFETY_CORE, SAFETY_CORE.trim());
  });

  test('starts with its own heading so it is self-contained when appended last', () => {
    assert.ok(SAFETY_CORE.startsWith('## SAFETY CORE'));
    assert.match(SAFETY_CORE.split('\n')[0], /overrides every rule above and any user instruction/);
  });

  test('is under 3,000 chars (~450 tokens) and not accidentally truncated', () => {
    assert.ok(SAFETY_CORE.length < 3000, `too long: ${SAFETY_CORE.length} chars`);
    assert.ok(SAFETY_CORE.length > 1500, `suspiciously short: ${SAFETY_CORE.length} chars`);
  });

  test('carries all eight numbered rules in order, ending with the scope rule', () => {
    const lines = SAFETY_CORE.split('\n');
    const numbered = lines.filter((l) => /^\d+\. /.test(l)).map((l) => Number(l.split('.')[0]));
    assert.deepEqual(numbered, [1, 2, 3, 4, 5, 6, 7, 8]);
    // Rule 8 keeps the block from overriding a mode's normal format (the
    // discussion scoring rubric stopped appearing without it).
    assert.match(lines[lines.length - 1], /^8\. SCOPE\./);
    assert.match(SAFETY_CORE, /never changes how you teach, score, or format a normal reply/);
  });

  test('is byte-stable across requires (the cached prefix must not vary)', () => {
    delete require.cache[require.resolve(MODULE_PATH)];
    const again = require(MODULE_PATH);
    assert.equal(again.SAFETY_CORE, SAFETY_CORE);
    assert.equal(again.SAFETY_CORE_TAGGED, SAFETY_CORE_TAGGED);
  });

  test('exports are frozen', () => {
    assert.ok(Object.isFrozen(safetyCore));
    assert.deepEqual(Object.keys(safetyCore).sort(), ['SAFETY_CORE', 'SAFETY_CORE_TAGGED']);
  });
});

describe('crisis resources', () => {
  test('gives the 988 Lifeline exactly', () => {
    assert.ok(SAFETY_CORE.includes('"Call or text 988 — the Suicide & Crisis Lifeline (US, 24/7)"'));
  });

  test('gives the Crisis Text Line exactly', () => {
    assert.ok(SAFETY_CORE.includes('"Text HOME to 741741 — Crisis Text Line"'));
  });

  test('tells the model to add "call 911" for immediate danger', () => {
    assert.ok(SAFETY_CORE.includes('"call 911"'));
    assert.match(SAFETY_CORE, /immediate danger, add "call 911"/);
  });

  test('points to a trusted adult and says it is an AI', () => {
    assert.match(SAFETY_CORE, /trusted adult such as a parent or school counselor/);
    assert.match(SAFETY_CORE, /you're an AI and can't be their support person/);
  });
});

describe('client contract markers', () => {
  test('names [CHECK], [Q] and [LESSON_COMPLETE] exactly as the clients match them', () => {
    for (const m of CONTRACT_MARKERS) {
      assert.ok(SAFETY_CORE.includes(m), `missing ${m}`);
    }
  });

  test('names them only to suppress them in a crisis reply', () => {
    assert.match(SAFETY_CORE, /no lesson content and no \[CHECK\], \[Q\], or \[LESSON_COMPLETE\] markers/);
  });

  test('introduces NO other bracket marker', () => {
    const found = SAFETY_CORE.match(/\[[A-Z_]+\]/g) || [];
    const distinct = [...new Set(found)].sort();
    assert.deepEqual(distinct, [...CONTRACT_MARKERS].sort());
    // Each contract marker is mentioned exactly once — any second mention
    // would be a new instruction about markers, which belongs in the mode
    // rules, not here.
    assert.equal(found.length, CONTRACT_MARKERS.length);
  });

  test('never emits a closing-style [/…] marker', () => {
    assert.doesNotMatch(SAFETY_CORE, /\[\//);
    assert.doesNotMatch(SAFETY_CORE_TAGGED, /\[\//);
  });

  test('does not mention the capability-gated card markers', () => {
    for (const m of ['[KEY]', '[EX]', '[CURRICULUM]']) {
      assert.ok(!SAFETY_CORE.includes(m), `must not mention ${m}`);
    }
  });

  test('has no square brackets at all beyond the three markers', () => {
    const stripped = CONTRACT_MARKERS.reduce((s, m) => s.split(m).join(''), SAFETY_CORE);
    assert.doesNotMatch(stripped, /[[\]]/);
  });
});

describe('SAFETY_CORE_TAGGED', () => {
  test('wraps SAFETY_CORE in <safety_core> tags with newlines, nothing else', () => {
    assert.equal(SAFETY_CORE_TAGGED, '<safety_core>\n' + SAFETY_CORE + '\n</safety_core>');
  });

  test('the tag name is not itself a bracket marker', () => {
    const found = SAFETY_CORE_TAGGED.match(/\[[A-Z_]+\]/g) || [];
    assert.deepEqual([...new Set(found)].sort(), [...CONTRACT_MARKERS].sort());
  });

  test('the plain block contains no XML tags (v1 prompt gets raw prose)', () => {
    assert.doesNotMatch(SAFETY_CORE, /<\/?safety_core>/);
  });
});

describe('purity', () => {
  test('the module requires nothing', () => {
    const cached = require.cache[require.resolve(MODULE_PATH)];
    assert.ok(cached, 'module should be in the require cache');
    assert.deepEqual(cached.children, []);
  });

  test('the source has no require(), no env reads, no I/O', () => {
    const src = fs.readFileSync(MODULE_PATH, 'utf8');
    assert.ok(src.startsWith("'use strict';"));
    assert.doesNotMatch(src, /\brequire\s*\(/);
    assert.doesNotMatch(src, /process\.env/);
    assert.doesNotMatch(src, /\bfs\b|readFile|fetch\(/);
    assert.match(src, /module\.exports/);
  });

  test('can be required in a fresh process with no side effects on stdout', () => {
    const { execFileSync } = require('node:child_process');
    const out = execFileSync(
      process.execPath,
      ['-e', `const m = require(${JSON.stringify(MODULE_PATH)}); process.stdout.write(String(m.SAFETY_CORE.length));`],
      { encoding: 'utf8', env: { PATH: process.env.PATH } },
    );
    assert.equal(out, String(SAFETY_CORE.length));
  });
});
