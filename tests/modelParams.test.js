'use strict';

// Unit tests for lib/modelParams — which request fields each model takes.
// The route-level proof (every route, both models, captured params) is
// tests/tutorModel.test.js.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const mp = require('../lib/modelParams');

const S46 = 'claude-sonnet-4-6';
const S55 = 'claude-sonnet-5-5';
const HAIKU = 'claude-haiku-4-5';
const NON_PROBLEM = ['turn', 'grader', 'helper', 'prewarm'];
// 4.7+/5.x ids this change has no verified request rules for.
const UNVERIFIED_MODERN = ['claude-sonnet-5', 'claude-opus-4-7', 'claude-opus-5-5', 'claude-haiku-5-5'];
const SUMMARIZED = { type: 'adaptive', display: 'summarized' };

describe('resolveTutorModel', () => {
  test('unset or blank → claude-sonnet-4-6, today\'s model', () => {
    for (const raw of [undefined, null, '', '   ']) assert.equal(mp.resolveTutorModel(raw), S46, String(raw));
    assert.equal(mp.DEFAULT_TUTOR_MODEL, S46);
  });

  test('a set value is used as written (trimmed)', () => {
    assert.equal(mp.resolveTutorModel(S55), S55);
    assert.equal(mp.resolveTutorModel(`  ${S55}\n`), S55);
  });
});

describe('resolveTutorEffort', () => {
  test('unset or blank → low, valid', () => {
    for (const raw of [undefined, '', ' ']) assert.deepEqual(mp.resolveTutorEffort(raw), { effort: 'low', valid: true });
  });

  test('low, medium and high are accepted (case-insensitive)', () => {
    assert.deepEqual(mp.resolveTutorEffort('medium'), { effort: 'medium', valid: true });
    assert.deepEqual(mp.resolveTutorEffort('HIGH'), { effort: 'high', valid: true });
    assert.deepEqual(mp.TUTOR_EFFORTS, ['low', 'medium', 'high']);
  });

  test('xhigh and max (between_tools rejects them) and junk fall back to low, flagged invalid', () => {
    for (const raw of ['xhigh', 'max', 'turbo', '1']) assert.deepEqual(mp.resolveTutorEffort(raw), { effort: 'low', valid: false }, raw);
  });
});

describe('model classification', () => {
  test('sampling: Sonnet 4.6, Haiku 4.5 and legacy ids take temperature; 4.7+ and 5.x do not', () => {
    for (const id of [S46, HAIKU, 'claude-haiku-4-5-20251001', 'claude-opus-4-6', 'claude-3-5-haiku-latest', 'claude-sonnet-4-5', 'm', '']) {
      assert.equal(mp.acceptsSampling(id), true, id);
    }
    for (const id of [S55, `${S55}-20261001`, 'claude-sonnet-5', 'claude-opus-4-7', 'claude-opus-4-8', 'claude-opus-5-5', 'claude-haiku-5-5', 'claude-fable-5-1', '  Claude-Sonnet-5-5 ']) {
      assert.equal(mp.acceptsSampling(id), false, id);
    }
  });

  test('between_tools only on claude-sonnet-5-5 (and its dated ids)', () => {
    assert.equal(mp.usesBetweenTools(S55), true);
    assert.equal(mp.usesBetweenTools(`${S55}-20261001`), true);
    for (const id of [S46, HAIKU, 'claude-sonnet-5', 'claude-sonnet-5-55', 'claude-opus-5-5', 'claude-haiku-5-5']) {
      assert.equal(mp.usesBetweenTools(id), false, id);
    }
  });

  test('verified tutor models: claude-sonnet-4-6 and claude-sonnet-5-5 (and its dated ids) only', () => {
    for (const id of [S46, S55, `${S55}-20261001`, `  ${S55} `]) assert.equal(mp.isVerifiedTutorModel(id), true, id);
    for (const id of [...UNVERIFIED_MODERN, HAIKU, 'claude-opus-4-6', 'claude-sonnet-4-6-20260101', 'claude-sonnet-5-55', '', undefined]) {
      assert.equal(mp.isVerifiedTutorModel(id), false, String(id));
    }
  });

  test('thinks: a problem turn on a thinking model, every call on an unverified 4.7+/5.x model, nothing else', () => {
    assert.equal(mp.thinks(S46, 'problem'), true);
    assert.equal(mp.thinks(S55, 'problem'), true);
    assert.equal(mp.thinks(HAIKU, 'problem'), false);
    for (const intent of NON_PROBLEM) {
      for (const id of [S46, S55, HAIKU]) assert.equal(mp.thinks(id, intent), false, `${id} ${intent}`);
      for (const id of UNVERIFIED_MODERN) assert.equal(mp.thinks(id, intent), true, `${id} ${intent}`);
    }
    assert.throws(() => mp.thinks(S55, 'chat'), /unknown intent/);
  });

  test('problem-turn thinking: exactly today\'s Sonnet/Opus 4.6 ids, plus every 4.7+/5.x model', () => {
    assert.equal(mp.thinksOnProblems(S46), true);
    assert.equal(mp.thinksOnProblems('claude-opus-4-6'), true);
    assert.equal(mp.thinksOnProblems('claude-sonnet-4-6-20260101'), false, 'today\'s regex had no dated suffix');
    assert.equal(mp.thinksOnProblems(HAIKU), false, 'Haiku 4.5 has no adaptive thinking');
    assert.equal(mp.thinksOnProblems(S55), true);
    assert.equal(mp.thinksOnProblems('claude-opus-4-7'), true);
  });
});

describe('requestFields on claude-sonnet-4-6: today\'s requests, unchanged', () => {
  test('a turn sends its temperature and nothing else', () => {
    assert.deepEqual(mp.requestFields(S46, 'turn', { temperature: 0.4, effort: 'high' }), { temperature: 0.4 });
  });

  test('the grader keeps temperature 0.2', () => {
    assert.deepEqual(mp.requestFields(S46, 'grader', { temperature: 0.2 }), { temperature: 0.2 });
  });

  test('helpers and the prewarm send no sampling or thinking field', () => {
    assert.deepEqual(mp.requestFields(S46, 'helper', { effort: 'medium' }), {});
    assert.deepEqual(mp.requestFields(S46, 'prewarm'), {});
  });

  test('a problem turn: adaptive thinking at low effort, no temperature, thinking first in key order', () => {
    const fields = mp.requestFields(S46, 'problem', { temperature: 0.4, effort: 'high' });
    assert.deepEqual(fields, { thinking: { type: 'adaptive' }, output_config: { effort: 'low' } });
    assert.deepEqual(Object.keys(fields), ['thinking', 'output_config']);
    assert.deepEqual(Object.keys(fields.thinking), ['type'], 'no display: 4.6 summarizes by default');
    assert.deepEqual(mp.requestFields('claude-opus-4-6', 'problem').thinking, { type: 'adaptive' });
  });

  test('max_tokens: a problem turn gets base + 2048, at least 3000; others the base', () => {
    assert.equal(mp.maxTokensFor(S46, 'problem', 250), 3000);
    assert.equal(mp.maxTokensFor(S46, 'problem', 1400), 3448);
    for (const intent of NON_PROBLEM) assert.equal(mp.maxTokensFor(S46, intent, 250), 250, intent);
  });
});

describe('requestFields on claude-sonnet-5-5', () => {
  test('never a sampling field, for any intent or temperature', () => {
    for (const intent of mp.INTENTS) {
      const fields = mp.requestFields(S55, intent, { temperature: 0.4, effort: 'low' });
      for (const k of ['temperature', 'top_p', 'top_k']) assert.equal(k in fields, false, `${intent}: ${k}`);
    }
  });

  test('a problem turn: adaptive thinking at low effort (as on 4.6), summarized, with the same headroom', () => {
    // display 'summarized' is 4.6's default; on 5.5 the default is 'omitted',
    // which streams nothing while it thinks and would trip the idle watchdog.
    const fields = mp.requestFields(S55, 'problem', { temperature: 0.4, effort: 'high' });
    assert.deepEqual(fields, { thinking: SUMMARIZED, output_config: { effort: 'low' } });
    assert.deepEqual(Object.keys(fields.thinking), ['type', 'display']);
    assert.equal(mp.maxTokensFor(S55, 'problem', 250), 3000);
  });

  test('every other call: between_tools (no other field inside) at TUTOR_EFFORT, no extra headroom', () => {
    for (const intent of NON_PROBLEM) {
      for (const effort of mp.TUTOR_EFFORTS) {
        const fields = mp.requestFields(S55, intent, { temperature: 0.2, effort });
        assert.deepEqual(fields, { thinking: { type: 'between_tools' }, output_config: { effort } }, `${intent} ${effort}`);
        assert.deepEqual(Object.keys(fields.thinking), ['type']);
      }
      assert.equal(mp.maxTokensFor(S55, intent, 400), 400, intent);
    }
  });

  test('effort defaults to low, and a level between_tools rejects is never sent', () => {
    assert.deepEqual(mp.requestFields(S55, 'turn').output_config, { effort: 'low' });
    assert.deepEqual(mp.requestFields(S55, 'turn', { effort: 'xhigh' }).output_config, { effort: 'low' });
    assert.deepEqual(mp.requestFields(S55, 'turn', { effort: 'max' }).output_config, { effort: 'low' });
  });
});

describe('requestFields on other models', () => {
  test('Haiku 4.5 (the helper model, or a client-named model): temperature, and a problem turn does not think', () => {
    assert.deepEqual(mp.requestFields(HAIKU, 'turn', { temperature: 0.6 }), { temperature: 0.6 });
    assert.deepEqual(mp.requestFields(HAIKU, 'problem', { temperature: 0.6 }), { temperature: 0.6 });
    assert.equal(mp.maxTokensFor(HAIKU, 'problem', 250), 250);
  });

  test('an unverified 4.7+/5.x model: explicit adaptive thinking (summarized) at TUTOR_EFFORT, never left to the model\'s default', () => {
    // Leaving `thinking` out runs adaptive thinking on Sonnet 5, Opus 5/5.5
    // and Haiku 5.5, inside reply budgets sized for no thinking; between_tools
    // is a 400 on all of them. So every call thinks explicitly, with headroom.
    for (const id of UNVERIFIED_MODERN) {
      for (const intent of NON_PROBLEM) {
        const fields = mp.requestFields(id, intent, { temperature: 0.4, effort: 'medium' });
        assert.deepEqual(fields, { thinking: SUMMARIZED, output_config: { effort: 'medium' } }, `${id} ${intent}`);
        assert.deepEqual(Object.keys(fields), ['thinking', 'output_config']);
      }
      assert.deepEqual(mp.requestFields(id, 'problem', { effort: 'high' }), { thinking: SUMMARIZED, output_config: { effort: 'low' } }, id);
      assert.deepEqual(mp.requestFields(id, 'turn', { effort: 'xhigh' }).output_config, { effort: 'low' }, 'TUTOR_EFFORTS only');
    }
  });

  test('an unverified 4.7+/5.x model: the thinking headroom on every call but the prewarm', () => {
    for (const id of UNVERIFIED_MODERN) {
      assert.equal(mp.maxTokensFor(id, 'turn', 250), 3000, id);
      assert.equal(mp.maxTokensFor(id, 'turn', 2048), 4096, id);
      assert.equal(mp.maxTokensFor(id, 'grader', 400), 3000, id);
      assert.equal(mp.maxTokensFor(id, 'helper', 700), 3000, id);
      assert.equal(mp.maxTokensFor(id, 'helper', 1400), 3448, id);
      assert.equal(mp.maxTokensFor(id, 'problem', 250), 3000, id);
      assert.equal(mp.maxTokensFor(id, 'prewarm', 1), 1, `${id}: the prewarm's reply is never read`);
    }
  });

  test('an unknown intent throws (a typo at a call site fails its tests)', () => {
    assert.throws(() => mp.requestFields(S46, 'chat'), /unknown intent/);
    assert.throws(() => mp.maxTokensFor(S46, 'lesson', 100), /unknown intent/);
  });
});
