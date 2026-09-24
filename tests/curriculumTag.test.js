'use strict';

// Tests for lib/curriculumTag — the helpers around the hidden lesson opener
// the iOS client re-sends as a wire prefix.
//
//   1. parseCurriculumTag — the canonical Curriculum.swift shapes (plain,
//      "- Review", "- Final Review"), the tolerant variants (spacing, zero
//      padding, alternate separators, trailing text), and the non-matches
//      (mid-text, leading whitespace, wrong casing, malformed, non-strings).
//   2. lessonIdFromMessages — every u1_l1 … u8_l5 id, FIRST-user-message
//      precedence, assistant tags ignored.
//   3. isCurriculumThread — the loose any-user-message server rule.
//   4. stripCurriculumTag — one leading tag, trimmed start, otherwise as-is.
//   5. normalizeReplayedHistory — the real wire shape across two consecutive
//      turns: index 0 keeps its tag, later re-tags are stripped, the shared
//      prefix is byte-identical between turns, input never mutated,
//      multimodal content passes through.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  CURRICULUM_TAG_PREFIX,
  hasCurriculumPrefix,
  parseCurriculumTag,
  lessonId,
  lessonIdFromMessages,
  isCurriculumThread,
  stripCurriculumTag,
  normalizeReplayedHistory,
} = require('../lib/curriculumTag');

// The exact opener the iOS client puts at wire index 0 (Curriculum.swift
// starter + ChatViewModel.withCompletionContract suffix).
const CONTRACT = " When I have clearly demonstrated proficiency at this lesson's objective, end your reply with [LESSON_COMPLETE] on its own final line.";
const OPENER_U1L3 = '[CURRICULUM: Unit 1, Lesson 3] Teach me about AI hallucination and why LLMs can sound confident even when wrong.' + CONTRACT;
const OPENER_U1L4_REVIEW = '[CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive exercise that tests everything from Unit 1.' + CONTRACT;

const user = (content) => ({ role: 'user', content });
const assistant = (content) => ({ role: 'assistant', content });

// ---------------------------------------------------------------------------
// parseCurriculumTag
// ---------------------------------------------------------------------------
describe('parseCurriculumTag', () => {
  test('canonical iOS opener shapes', () => {
    assert.deepEqual(parseCurriculumTag(OPENER_U1L3), {
      unit: 1, lesson: 3, raw: '[CURRICULUM: Unit 1, Lesson 3]',
    });
    assert.deepEqual(parseCurriculumTag(OPENER_U1L4_REVIEW), {
      unit: 1, lesson: 4, raw: '[CURRICULUM: Unit 1, Lesson 4 - Review]',
    });
    assert.deepEqual(parseCurriculumTag('[CURRICULUM: Unit 5, Lesson 4 - Final Review] Have me build my own AI ethics framework.'), {
      unit: 5, lesson: 4, raw: '[CURRICULUM: Unit 5, Lesson 4 - Final Review]',
    });
    assert.deepEqual(parseCurriculumTag('[CURRICULUM: Unit 6, Lesson 5 - Review] Give me a realistic viral media claim.'), {
      unit: 6, lesson: 5, raw: '[CURRICULUM: Unit 6, Lesson 5 - Review]',
    });
  });

  test('bare tag with nothing after it', () => {
    assert.deepEqual(parseCurriculumTag('[CURRICULUM: Unit 8, Lesson 5]'), {
      unit: 8, lesson: 5, raw: '[CURRICULUM: Unit 8, Lesson 5]',
    });
  });

  test('tolerant variants: spacing, zero padding, separators', () => {
    const cases = [
      ['[CURRICULUM:Unit 1,Lesson 3]', 1, 3],
      ['[CURRICULUM:   Unit   1 ,   Lesson   3   ]', 1, 3],
      ['[CURRICULUM: Unit 01 · Lesson 3]', 1, 3],
      ['[CURRICULUM: Unit 01 · Lesson 03]', 1, 3],
      ['[CURRICULUM: Unit 1 Lesson 3]', 1, 3],
      ['[CURRICULUM: Unit 1 - Lesson 3]', 1, 3],
      ['[CURRICULUM: Unit 1 – Lesson 3]', 1, 3],
      ['[CURRICULUM: Unit 1 / Lesson 3]', 1, 3],
      ['[CURRICULUM: Unit1, Lesson3]', 1, 3],
      ['[CURRICULUM: Unit 7, Lesson 2 (resumed)]', 7, 2],
    ];
    for (const [text, unit, lesson] of cases) {
      const got = parseCurriculumTag(text);
      assert.ok(got, `expected a parse for ${JSON.stringify(text)}`);
      assert.equal(got.unit, unit, text);
      assert.equal(got.lesson, lesson, text);
      assert.equal(got.raw, text, 'raw is the literal tag text');
    }
  });

  test('raw is exactly the bracket, not the trailing text', () => {
    const got = parseCurriculumTag('[CURRICULUM: Unit 2, Lesson 2]   What is COMPAS?');
    assert.equal(got.raw, '[CURRICULUM: Unit 2, Lesson 2]');
    assert.equal(typeof got.unit, 'number');
    assert.equal(typeof got.lesson, 'number');
  });

  test('re-tagged student turn (tag + space + student text) parses too', () => {
    const got = parseCurriculumTag('[CURRICULUM: Unit 1, Lesson 4 - Review] I think tokenization splits words into pieces.');
    assert.deepEqual(got, { unit: 1, lesson: 4, raw: '[CURRICULUM: Unit 1, Lesson 4 - Review]' });
  });

  test('non-matches: tag not at the very start', () => {
    assert.equal(parseCurriculumTag('Hello [CURRICULUM: Unit 1, Lesson 3]'), null);
    assert.equal(parseCurriculumTag(' [CURRICULUM: Unit 1, Lesson 3]'), null, 'leading space');
    assert.equal(parseCurriculumTag('\n[CURRICULUM: Unit 1, Lesson 3]'), null, 'leading newline');
    assert.equal(parseCurriculumTag('Teach me. [CURRICULUM: Unit 1, Lesson 3] please'), null);
  });

  test('non-matches: wrong casing is not a tag', () => {
    assert.equal(parseCurriculumTag('[curriculum: Unit 1, Lesson 3]'), null);
    assert.equal(parseCurriculumTag('[Curriculum: Unit 1, Lesson 3]'), null);
    assert.equal(parseCurriculumTag('[CURRICULUM: unit 1, lesson 3]'), null);
    assert.equal(parseCurriculumTag('[CURRICULUM: UNIT 1, LESSON 3]'), null);
  });

  test('non-matches: malformed tags', () => {
    assert.equal(parseCurriculumTag('[CURRICULUM: Unit 1]'), null, 'no lesson');
    assert.equal(parseCurriculumTag('[CURRICULUM: Lesson 3]'), null, 'no unit');
    assert.equal(parseCurriculumTag('[CURRICULUM: Unit 1, Lesson 3'), null, 'no closing bracket');
    assert.equal(parseCurriculumTag('[CURRICULUM: Unit one, Lesson three]'), null, 'words not digits');
    assert.equal(parseCurriculumTag('[CURRICULUM: Unit 0, Lesson 1]'), null, 'unit 0');
    assert.equal(parseCurriculumTag('[CURRICULUM: Unit 1, Lesson 0]'), null, 'lesson 0');
    assert.equal(parseCurriculumTag('[CURRICULUM]'), null);
    assert.equal(parseCurriculumTag('[CURRICULUM: ]'), null);
    assert.equal(parseCurriculumTag('[LESSON_COMPLETE]'), null);
  });

  test('non-matches: empty and non-string inputs', () => {
    assert.equal(parseCurriculumTag(''), null);
    assert.equal(parseCurriculumTag(undefined), null);
    assert.equal(parseCurriculumTag(null), null);
    assert.equal(parseCurriculumTag(42), null);
    assert.equal(parseCurriculumTag(['[CURRICULUM: Unit 1, Lesson 3]']), null);
    assert.equal(parseCurriculumTag({ content: '[CURRICULUM: Unit 1, Lesson 3]' }), null);
  });
});

// ---------------------------------------------------------------------------
// hasCurriculumPrefix / CURRICULUM_TAG_PREFIX
// ---------------------------------------------------------------------------
describe('hasCurriculumPrefix', () => {
  test('is the literal server startsWith rule', () => {
    assert.equal(CURRICULUM_TAG_PREFIX, '[CURRICULUM:');
    assert.equal(hasCurriculumPrefix(OPENER_U1L3), true);
    assert.equal(hasCurriculumPrefix('[CURRICULUM: anything at all'), true, 'loose: no parse needed');
    assert.equal(hasCurriculumPrefix('[curriculum: Unit 1, Lesson 3]'), false);
    assert.equal(hasCurriculumPrefix(' [CURRICULUM: Unit 1, Lesson 3]'), false);
    assert.equal(hasCurriculumPrefix(''), false);
    assert.equal(hasCurriculumPrefix(undefined), false);
    assert.equal(hasCurriculumPrefix(null), false);
    assert.equal(hasCurriculumPrefix([{ type: 'text', text: '[CURRICULUM: Unit 1, Lesson 3]' }]), false);
  });
});

// ---------------------------------------------------------------------------
// lessonId / lessonIdFromMessages
// ---------------------------------------------------------------------------
describe('lessonIdFromMessages', () => {
  test('lessonId follows the Curriculum.swift convention', () => {
    assert.equal(lessonId(1, 1), 'u1_l1');
    assert.equal(lessonId(8, 5), 'u8_l5');
  });

  test('every id across units 1-8 and lessons 1-5', () => {
    for (let u = 1; u <= 8; u++) {
      for (let l = 1; l <= 5; l++) {
        const review = l === 4 || l === 5 ? ' - Review' : '';
        const msgs = [
          user(`[CURRICULUM: Unit ${u}, Lesson ${l}${review}] Teach me.${CONTRACT}`),
          assistant('Sure.'),
          user('ok'),
        ];
        assert.equal(lessonIdFromMessages(msgs), `u${u}_l${l}`);
      }
    }
  });

  test('zero-padded and alternate separators yield the same id', () => {
    assert.equal(lessonIdFromMessages([user('[CURRICULUM: Unit 03 · Lesson 02] hi')]), 'u3_l2');
  });

  test('FIRST tagged user message wins', () => {
    const msgs = [
      user(OPENER_U1L3),
      assistant('…'),
      user('[CURRICULUM: Unit 2, Lesson 1] leaked from another lesson'),
    ];
    assert.equal(lessonIdFromMessages(msgs), 'u1_l3');
  });

  test('a tag on the last user turn only (legacy re-tag) still resolves', () => {
    const msgs = [user('what is a token?'), assistant('…'), user('[CURRICULUM: Unit 4, Lesson 2] my answer')];
    assert.equal(lessonIdFromMessages(msgs), 'u4_l2');
  });

  test('assistant messages carrying the tag are ignored', () => {
    const msgs = [assistant('[CURRICULUM: Unit 1, Lesson 1] echo'), user('hi')];
    assert.equal(lessonIdFromMessages(msgs), null);
  });

  test('loose-but-unparsable tag gives null (lesson, unknown id)', () => {
    const msgs = [user('[CURRICULUM: something odd] hi')];
    assert.equal(lessonIdFromMessages(msgs), null);
    assert.equal(isCurriculumThread(msgs), true);
  });

  test('null for untagged, multimodal, empty, and undefined inputs', () => {
    assert.equal(lessonIdFromMessages([user('hello'), assistant('hi')]), null);
    assert.equal(lessonIdFromMessages([user([{ type: 'text', text: '[CURRICULUM: Unit 1, Lesson 1] hi' }])]), null);
    assert.equal(lessonIdFromMessages([]), null);
    assert.equal(lessonIdFromMessages(undefined), null);
    assert.equal(lessonIdFromMessages(null), null);
    assert.equal(lessonIdFromMessages('not an array'), null);
    assert.equal(lessonIdFromMessages([null, undefined, {}, { role: 'user' }]), null);
  });
});

// ---------------------------------------------------------------------------
// isCurriculumThread
// ---------------------------------------------------------------------------
describe('isCurriculumThread', () => {
  test('true when the opener is at index 0', () => {
    assert.equal(isCurriculumThread([user(OPENER_U1L3), assistant('…'), user('ok')]), true);
  });

  test('true when only the last user turn carries the tag', () => {
    assert.equal(isCurriculumThread([user('hi'), assistant('…'), user('[CURRICULUM: Unit 1, Lesson 3] ok')]), true);
  });

  test('true for a loose (unparsable) tag — the server rule is a prefix check', () => {
    assert.equal(isCurriculumThread([user('[CURRICULUM: ???')]), true);
  });

  test('false for ordinary chat', () => {
    assert.equal(isCurriculumThread([user('What is a token?'), assistant('…'), user('thanks')]), false);
  });

  test('false when only an assistant message carries the tag', () => {
    assert.equal(isCurriculumThread([user('hi'), assistant('[CURRICULUM: Unit 1, Lesson 3] echo')]), false);
  });

  test('false for a tag mid-text, wrong casing, or leading whitespace', () => {
    assert.equal(isCurriculumThread([user('see [CURRICULUM: Unit 1, Lesson 3]')]), false);
    assert.equal(isCurriculumThread([user('[curriculum: Unit 1, Lesson 3]')]), false);
    assert.equal(isCurriculumThread([user(' [CURRICULUM: Unit 1, Lesson 3]')]), false);
  });

  test('false for multimodal content even when a text block starts with the tag', () => {
    assert.equal(isCurriculumThread([user([{ type: 'text', text: '[CURRICULUM: Unit 1, Lesson 3] hi' }])]), false);
  });

  test('false for empty, undefined, and malformed inputs', () => {
    assert.equal(isCurriculumThread([]), false);
    assert.equal(isCurriculumThread(undefined), false);
    assert.equal(isCurriculumThread(null), false);
    assert.equal(isCurriculumThread('nope'), false);
    assert.equal(isCurriculumThread([null, undefined, {}, { role: 'user' }, { role: 'user', content: 7 }]), false);
  });
});

// ---------------------------------------------------------------------------
// stripCurriculumTag
// ---------------------------------------------------------------------------
describe('stripCurriculumTag', () => {
  test('removes a leading tag and the space after it', () => {
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3] I think it hallucinated.'), 'I think it hallucinated.');
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 4 - Review] my answer'), 'my answer');
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 5, Lesson 4 - Final Review]    padded'), 'padded');
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3]\n\nnewline-separated'), 'newline-separated');
  });

  test('strips the loose form too (anything through the first bracket)', () => {
    assert.equal(stripCurriculumTag('[CURRICULUM: odd] text'), 'text');
  });

  test('keeps the rest of the message byte-for-byte (trailing whitespace, later brackets)', () => {
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3] keep [LESSON_COMPLETE] and this  '), 'keep [LESSON_COMPLETE] and this  ');
    assert.equal(stripCurriculumTag(OPENER_U1L3), OPENER_U1L3.slice('[CURRICULUM: Unit 1, Lesson 3] '.length));
  });

  test('bare tag or tag + whitespace strips to the empty string (image-only turn)', () => {
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3]'), '');
    assert.equal(stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3] '), '');
  });

  test('strips exactly one tag', () => {
    assert.equal(
      stripCurriculumTag('[CURRICULUM: Unit 1, Lesson 3] [CURRICULUM: Unit 1, Lesson 3] hi'),
      '[CURRICULUM: Unit 1, Lesson 3] hi',
    );
  });

  test('untouched when there is no leading tag', () => {
    for (const s of [
      'plain text',
      'see [CURRICULUM: Unit 1, Lesson 3] mid-text',
      ' [CURRICULUM: Unit 1, Lesson 3] leading space',
      '[curriculum: Unit 1, Lesson 3] wrong case',
      '[CURRICULUM: Unit 1, Lesson 3 no closing bracket',
      '  keeps its own leading whitespace',
      '',
    ]) {
      assert.equal(stripCurriculumTag(s), s, JSON.stringify(s));
    }
  });

  test('non-string inputs are returned as-is', () => {
    const arr = [{ type: 'text', text: '[CURRICULUM: Unit 1, Lesson 3] hi' }];
    assert.equal(stripCurriculumTag(arr), arr);
    assert.equal(stripCurriculumTag(undefined), undefined);
    assert.equal(stripCurriculumTag(null), null);
    assert.equal(stripCurriculumTag(3), 3);
  });
});

// ---------------------------------------------------------------------------
// normalizeReplayedHistory
// ---------------------------------------------------------------------------
describe('normalizeReplayedHistory', () => {
  const TAG = '[CURRICULUM: Unit 1, Lesson 3]';

  // The iOS wire shape: opener at 0, then the visible thread, with the LAST
  // user turn re-tagged `tag + " " + content` (wire-only).
  function wireTurn(visibleThread) {
    const history = visibleThread.map((m) => ({ ...m }));
    const lastUser = history.map((m) => m.role).lastIndexOf('user');
    if (lastUser !== -1 && !history[lastUser].content.startsWith('[CURRICULUM')) {
      history[lastUser] = user(TAG + ' ' + history[lastUser].content);
    }
    return [user(OPENER_U1L3), ...history];
  }

  test('keeps the opener at index 0 and strips the re-tag off the last user turn', () => {
    const wire = wireTurn([assistant('Hook + first concept.'), user('It predicts the next token.')]);
    assert.equal(wire[2].content, TAG + ' It predicts the next token.', 'fixture reproduces the wire shape');

    const out = normalizeReplayedHistory(wire);
    assert.deepEqual(out, [
      user(OPENER_U1L3),
      assistant('Hook + first concept.'),
      user('It predicts the next token.'),
    ]);
    assert.notEqual(out, wire, 'a new array');
    assert.equal(out[0], wire[0], 'index 0 passes through by reference');
    assert.equal(out[1], wire[1], 'assistant passes through by reference');
    assert.notEqual(out[2], wire[2], 'stripped turn is a new object');
  });

  test('the shared prefix is byte-identical across consecutive turns (cache stability)', () => {
    const thread1 = [assistant('Hook.'), user('next token')];
    const thread2 = [...thread1, assistant('Good. Now …'), user('a hallucination')];
    const thread3 = [...thread2, assistant('Right. [LESSON_COMPLETE]'), user('thanks!')];

    const n1 = normalizeReplayedHistory(wireTurn(thread1));
    const n2 = normalizeReplayedHistory(wireTurn(thread2));
    const n3 = normalizeReplayedHistory(wireTurn(thread3));

    // Without normalization the wires differ at the previous last-user index.
    assert.notDeepEqual(wireTurn(thread1), wireTurn(thread2).slice(0, 3));
    // With it, each turn's wire is a strict extension of the previous one's.
    assert.deepEqual(n2.slice(0, n1.length), n1);
    assert.deepEqual(n3.slice(0, n2.length), n2);
    assert.equal(JSON.stringify(n3).startsWith(JSON.stringify(n2).slice(0, -1)), true, 'serialized prefix is stable');
    for (let i = 1; i < n3.length; i++) {
      assert.equal(n3[i].content.startsWith('[CURRICULUM'), false, `index ${i} carries no tag`);
    }
    assert.equal(n3[0].content, OPENER_U1L3, 'opener keeps its tag');
  });

  test('never mutates the input', () => {
    const wire = wireTurn([assistant('…'), user('answer')]);
    const snapshot = JSON.stringify(wire);
    normalizeReplayedHistory(wire);
    assert.equal(JSON.stringify(wire), snapshot);
  });

  test('index 0 keeps its tag even when it is a re-tagged student turn (single-message wire)', () => {
    const only = [user(TAG + ' just me')];
    assert.deepEqual(normalizeReplayedHistory(only), only);
    assert.equal(normalizeReplayedHistory(only)[0], only[0]);
  });

  test('no tag at index 0 → nothing is stripped (a later tag is a genuine opener)', () => {
    // The club widget starts a lesson inside an existing chat thread: the
    // opener sits at index > 0 and MUST survive — CURRICULUM_PROMPT follows
    // the most recent tag.
    const wire = [user('plain opener'), assistant('…'), user(TAG + ' reply')];
    assert.deepEqual(normalizeReplayedHistory(wire), wire);
    assert.notEqual(normalizeReplayedHistory(wire), wire, 'still a new array');

    const odd = [assistant('leading assistant'), user(TAG + ' reply')];
    assert.deepEqual(normalizeReplayedHistory(odd), odd);
  });

  test('strips every later turn carrying the SAME tag as the opener, not just the last', () => {
    const wire = [user(OPENER_U1L3), assistant('a'), user(TAG + ' one'), assistant('b'), user(TAG + ' two')];
    assert.deepEqual(
      normalizeReplayedHistory(wire).map((m) => m.content),
      [OPENER_U1L3, 'a', 'one', 'b', 'two'],
    );
  });

  test('a DIFFERENT tag on a later turn survives (chained lessons in one thread)', () => {
    const LESSON2 = '[CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive review.';
    const wire = [
      user(OPENER_U1L3), assistant('Lesson 3 …'), user(TAG + ' my answer'),
      assistant('Done. [LESSON_COMPLETE]'), user(LESSON2), assistant('Review beat 1'),
      user('[CURRICULUM: Unit 1, Lesson 4 - Review] my review answer'),
    ];
    const out = normalizeReplayedHistory(wire).map((m) => m.content);
    assert.equal(out[2], 'my answer', 'the opener’s own re-tag is stripped');
    assert.equal(out[4], LESSON2, 'the Lesson 4 opener keeps its tag');
    assert.equal(out[6], '[CURRICULUM: Unit 1, Lesson 4 - Review] my review answer', 'a later turn tagged for Lesson 4 is untouched');
  });

  test('assistant messages that happen to start with the tag are untouched', () => {
    const wire = [user(OPENER_U1L3), assistant(TAG + ' echoed by the model'), user(TAG + ' hi')];
    const out = normalizeReplayedHistory(wire);
    assert.equal(out[1], wire[1]);
    assert.equal(out[1].content, TAG + ' echoed by the model');
  });

  test('multimodal (array) content passes through unchanged by reference', () => {
    const blocks = [
      { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'AAAA' } },
      { type: 'text', text: TAG + ' what is this?' },
    ];
    const wire = [user(OPENER_U1L3), assistant('…'), user(blocks)];
    const out = normalizeReplayedHistory(wire);
    assert.equal(out[2], wire[2]);
    assert.equal(out[2].content, blocks);
    assert.equal(out[2].content[1].text, TAG + ' what is this?', 'text blocks inside arrays are not touched');
  });

  test('preserves other fields on stripped messages', () => {
    const wire = [user(OPENER_U1L3), { role: 'user', content: TAG + ' hi', id: 'abc', ts: 123 }];
    assert.deepEqual(normalizeReplayedHistory(wire)[1], { role: 'user', content: 'hi', id: 'abc', ts: 123 });
  });

  test('a re-tagged image-only turn strips to the empty string', () => {
    const wire = [user(OPENER_U1L3), assistant('…'), user(TAG + ' ')];
    assert.equal(normalizeReplayedHistory(wire)[2].content, '');
  });

  test('empty, undefined, and malformed inputs', () => {
    assert.deepEqual(normalizeReplayedHistory([]), []);
    assert.deepEqual(normalizeReplayedHistory(undefined), []);
    assert.deepEqual(normalizeReplayedHistory(null), []);
    assert.deepEqual(normalizeReplayedHistory('nope'), []);
    const sparse = [user(OPENER_U1L3), null, undefined, {}, { role: 'user' }, { role: 'user', content: 7 }];
    assert.deepEqual(normalizeReplayedHistory(sparse), sparse, 'odd elements pass through untouched');
  });

  test('already-normalized history is a fixed point', () => {
    const once = normalizeReplayedHistory(wireTurn([assistant('…'), user('x'), assistant('…'), user('y')]));
    const twice = normalizeReplayedHistory(once);
    assert.deepEqual(twice, once);
    for (let i = 0; i < once.length; i++) assert.equal(twice[i], once[i], `index ${i} same reference`);
  });
});
