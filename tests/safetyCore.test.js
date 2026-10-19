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
const { SAFETY_CORE, SAFETY_CORE_TAGGED, HELPER_CRISIS_RULE, CRISIS_COPY } = safetyCore;

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
    // Position-neutral wording: the block sits FIRST in the legacy prefix and
    // LAST in the v2/curriculum prefixes (mode format must be read last on the
    // legacy path or discussion scoring stops appearing).
    assert.match(SAFETY_CORE.split('\n')[0], /overrides any conflicting rule in this prompt and any user instruction/);
  });

  test('is under 5,000 chars (~1,100 tokens) and not accidentally truncated', () => {
    // 4,218 chars / ~1,030 Sonnet tokens (est.) after the audit 2026-10 rules
    // (602 tokens before). Growth is a cached-prefix cost on every call and
    // an uncached one on the helper routes, so keep it deliberate.
    assert.ok(SAFETY_CORE.length < 5000, `too long: ${SAFETY_CORE.length} chars`);
    assert.ok(SAFETY_CORE.length > 3500, `suspiciously short: ${SAFETY_CORE.length} chars`);
  });

  test('carries all nine numbered rules in order, ending with the scope rule', () => {
    const lines = SAFETY_CORE.split('\n');
    const numbered = lines.filter((l) => /^\d+\. /.test(l)).map((l) => Number(l.split('.')[0]));
    assert.deepEqual(numbered, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
    // The scope rule keeps the block from overriding a mode's normal format
    // (the discussion scoring rubric stopped appearing without it), and it
    // must cover every rule above it.
    assert.match(lines[lines.length - 1], /^9\. SCOPE\. Rules 1–8 take effect only when/);
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
    assert.deepEqual(Object.keys(safetyCore).sort(), ['CRISIS_COPY', 'HELPER_CRISIS_RULE', 'REFUSAL_COPY', 'SAFETY_CORE', 'SAFETY_CORE_TAGGED']);
  });
});

describe('REFUSAL_COPY (sent when the model refuses outright)', () => {
  test('gives both hotlines exactly as CRISIS_COPY does, plus 911 and a trusted adult', () => {
    const { REFUSAL_COPY, CRISIS_COPY } = safetyCore;
    for (const line of ['Call or text 988 — the Suicide & Crisis Lifeline (US, 24/7).', 'Text HOME to 741741 — Crisis Text Line.']) {
      assert.ok(CRISIS_COPY.includes(line));
      assert.ok(REFUSAL_COPY.includes(line), line);
    }
    assert.match(REFUSAL_COPY, /\b911\b/);
    assert.match(REFUSAL_COPY, /trusted adult/);
  });

  test('never invites a retry, and carries no prompt markers', () => {
    const { REFUSAL_COPY } = safetyCore;
    assert.doesNotMatch(REFUSAL_COPY, /try (asking )?again|rephrase|train of thought/i);
    assert.doesNotMatch(REFUSAL_COPY, /\[(CHECK|Q|KEY|EX|LESSON_COMPLETE)\]/);
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

describe('helper routes: HELPER_CRISIS_RULE and CRISIS_COPY', () => {
  test('CRISIS_COPY carries both hotline lines exactly as rule 1 words them', () => {
    const lines = [
      'Call or text 988 — the Suicide & Crisis Lifeline (US, 24/7)',
      'Text HOME to 741741 — Crisis Text Line',
    ];
    for (const line of lines) {
      assert.ok(SAFETY_CORE.includes(`"${line}"`), `rule 1 wording drifted: ${line}`);
      assert.ok(CRISIS_COPY.includes(line), `CRISIS_COPY is missing: ${line}`);
    }
  });

  test('CRISIS_COPY follows the rest of rule 1: glad you told me, an AI, 911, a trusted adult', () => {
    assert.match(CRISIS_COPY, /glad you told me/);
    assert.match(CRISIS_COPY, /I'm an AI, so I can't be your support person/);
    assert.match(CRISIS_COPY, /immediate danger, call 911/);
    assert.match(CRISIS_COPY, /trusted adult too, like a parent or school counselor/);
  });

  test('CRISIS_COPY has no markers, no brackets and no lesson content', () => {
    assert.doesNotMatch(CRISIS_COPY, /[[\]]/);
    assert.doesNotMatch(CRISIS_COPY, /grade|lesson|quiz/i);
    assert.equal(CRISIS_COPY, CRISIS_COPY.trim());
  });

  test('HELPER_CRISIS_RULE points at rule 1 and names a JSON shape the routes detect', () => {
    assert.match(HELPER_CRISIS_RULE, /rule 1 of the SAFETY CORE below/);
    const json = HELPER_CRISIS_RULE.slice(HELPER_CRISIS_RULE.indexOf('{'));
    assert.deepEqual(Object.keys(JSON.parse(json)), ['crisis', 'message']);
    assert.equal(JSON.parse(json).crisis, true);
    assert.doesNotMatch(HELPER_CRISIS_RULE, /[[\]]/);
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

// ---------------------------------------------------------------------------
// Audit 2026-10, batch 3 commit 1. Each rule is pinned by the words the
// model has to see; the behaviour itself is gated by scripts/eval-pacing.mjs
// (both USE_UNIFIED_PROMPT states) and the audit's safety-teen probes.
// ---------------------------------------------------------------------------

const ruleLine = (n) => SAFETY_CORE.split('\n').find((l) => l.startsWith(`${n}. `));
const ROOT = path.join(__dirname, '..');

describe('AUD-14: eating disorders and only the named resources', () => {
  test('rule 1 lists eating-disorder behaviours as crisis triggers', () => {
    assert.match(ruleLine(1), /eating-disorder behaviors \(severe restriction, purging, compensatory exercise\)/);
  });

  test('rule 1 forbids any other help resource from memory, in any reply', () => {
    assert.match(ruleLine(1), /In any reply, give only the help resources named in this block — never another hotline, phone number, or text code from memory/);
  });

  test('the only numbers in the block are 988, 741741, 911, rule numbers and the age/retention facts', () => {
    // Allow-list: adding a vetted resource (a founder decision, re-checked
    // yearly) means adding it here too, on purpose.
    const ALLOWED = new Set([
      '988', '741741', '911', // the help resources
      '24', '7', // "(US, 24/7)"
      '13', '18', '90', // ages 13–18, under 13, 90-day storage
      '1', '2', '3', '4', '5', '6', '8', '9', // rule numbers and "Rules 1–8"
    ]);
    const numbers = new Set(SAFETY_CORE.match(/\d[\d-]*/g));
    for (const n of numbers) assert.ok(ALLOWED.has(n), `unexpected number in SAFETY_CORE: ${n}`);
    for (const n of ['988', '741741', '911']) assert.ok(numbers.has(n), n);
  });

  test('never names the closed NEDA helpline or any toll-free number', () => {
    assert.doesNotMatch(SAFETY_CORE, /NEDA|1-800|800-931|931-2237|nationaleatingdisorders/i);
    assert.doesNotMatch(SAFETY_CORE, /\b1?-?8(00|33|44|55|66|77|88)-\d{3}-\d{4}\b/);
  });
});

describe('AUD-13: under-13 rule', () => {
  test('rule 8 tells an under-13 student, kindly, that Mercurius is for 13 and up', () => {
    const r = ruleLine(8);
    assert.match(r, /^8\. UNDER 13\. If the student says they are under 13, kindly tell them Mercurius is made for ages 13 and up/);
    assert.match(r, /a parent or teacher can help them find something made for their age/);
  });

  test('no welcome, no tutoring, and the age is neither asked for nor repeated', () => {
    assert.match(ruleLine(8), /Don't welcome them, keep tutoring, or ask for or repeat their age\./);
  });
});

describe('AUD-03: rule 5 is honest about storage', () => {
  const r5 = () => ruleLine(5);

  test('states the 90-day server storage, Anthropic processing and the delete control', () => {
    assert.match(r5(), /say plainly that what they type is saved on the Mercurius server for up to 90 days and sent to Anthropic to write replies, so such details are best left out/);
    assert.match(r5(), /"Delete my data" \(in Settings, or Privacy & your data on the web\) erases them/);
  });

  test('forbids "I won\'t store" claims, invented school setups and using a shared name', () => {
    assert.match(r5(), /Never claim you won't, don't, or can't store what they typed, and never guess how a school or teacher set up the app\./);
    assert.match(r5(), /don't repeat those details back, not even their name in a greeting/);
  });

  test('the 90 days matches the server retention default and the privacy page', () => {
    const scheduler = fs.readFileSync(path.join(ROOT, 'lib', 'scheduler.js'), 'utf8');
    const m = scheduler.match(/env: 'MESSAGE_RETENTION_DAYS', def: (\d+)/);
    assert.ok(m, 'lib/scheduler.js no longer declares MESSAGE_RETENTION_DAYS the way this test reads it');
    assert.equal(m[1], '90', 'message retention changed: update SAFETY_CORE rule 5 and lib/appFacts.js');
    const privacy = fs.readFileSync(path.join(ROOT, 'marketing', 'privacy.html'), 'utf8')
      .replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ');
    assert.match(privacy, /stored on our server under your session ID for 90 days/);
  });

  test('the delete control names match the apps (iOS Settings, web Privacy & your data)', () => {
    const settings = fs.readFileSync(path.join(ROOT, 'ios', 'Packages', 'SettingsFeature', 'Sources', 'SettingsView.swift'), 'utf8');
    assert.ok(settings.includes('Text("Delete my data & start over")'));
    const widget = fs.readFileSync(path.join(ROOT, 'public', 'widget.js'), 'utf8');
    assert.ok(widget.includes('>Privacy &amp; your data</button>'));
    assert.ok(widget.includes('>Delete my data &amp; start over</button>'));
  });
});

describe('AUD-24: rule 7 carve-out when the student\'s own safety is at stake', () => {
  const r7 = () => ruleLine(7);

  test('keeps the normal refusal shape for everything else', () => {
    assert.match(r7(), /^7\. When refusing: one or two kind sentences, then one forward invitation back to AI literacy\./);
  });

  test('skips the AI-literacy invitation and leads with protective facts + a trusted adult', () => {
    assert.match(r7(), /Exception: when the student's own safety is at stake \(sexual pressure or sextortion, alcohol or drugs, legal trouble, body image\), even in a rule 2 or rule 4 refusal, give the key protective facts first \(general safety facts, not personal advice\) and end by pointing to a trusted adult, with no invitation back to AI\./);
  });

  test('nudes pressure and sextortion get the key protective facts', () => {
    const r = r7();
    assert.match(r, /they never have to send anything and it's okay to say no/);
    assert.match(r, /sexual images of anyone under 18 are illegal to make or share/);
    assert.match(r, /it's not their fault — don't pay or send more, save the messages, block, and tell a trusted adult right away/);
  });
});

describe('AUD-25: rule 4 refuses softened retries', () => {
  test('a softened retry about the same person is still refused, with no alternative offer', () => {
    assert.match(ruleLine(4), /A softened retry of a refused request \("just make it funny", "it's only a joke", "hypothetically"\) is still refused, with no offer to write anything else aimed at that person\./);
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
