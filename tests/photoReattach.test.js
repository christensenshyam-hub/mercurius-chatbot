'use strict';

// lib/photoReattach (AUD-10), pure: how a photo turn is keyed, which
// historical turn gets which photo, and how the turn is rebuilt. The route
// behaviour (linking, sessions, expiry, erasure, caching) is in
// tests/photoReattachRoute.test.js.

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const {
  canonicalText,
  replyKey,
  keysForTurn,
  plan,
  apply,
  textView,
  DEFAULT_MAX_TURNS,
  MAX_IMAGES,
  CANON_CHARS,
  REPLY_CHARS,
  REATTACHED_PHOTO_NOTE,
} = require('../lib/photoReattach');
const { normalizeReplayedHistory } = require('../lib/curriculumTag');
const { truncateUnits } = require('../lib/schemas');
const { withHistoryBreakpoint } = require('../lib/systemBlocks');
const { looksLikeProblemWork } = require('../lib/homeworkGuard');

const SHARED = '[Shared an image]';
const u = (content) => ({ role: 'user', content });
const a = (content) => ({ role: 'assistant', content });

// A link as db.linkedImages returns it, for the turn at `i` of `thread`
// (with the reply that followed it, when the thread has one).
function linkFor(id, thread, i, extra = {}) {
  const k = keysForTurn(thread, i);
  const next = thread[i + 1];
  const rk = next && next.role === 'assistant' ? replyKey(next.content) : null;
  return { id, turnKey: k.turnKey, anchorKey: k.anchorKey, replyKey: rk, sizeBytes: 1000, createdAt: 0, ...extra };
}

describe('canonicalText', () => {
  test('drops outer whitespace and keeps the first CANON_CHARS units', () => {
    assert.equal(canonicalText('  hi there \n'), 'hi there');
    assert.equal(canonicalText('x'.repeat(CANON_CHARS + 50)).length, CANON_CHARS);
    assert.equal(canonicalText(null), '');
    assert.equal(canonicalText(42), '');
  });
});

describe('replyKey', () => {
  test('the start of the reply: a cut-off copy of a long reply still matches', () => {
    const full = 'That worksheet has two problems. ' + 'Number 7 asks you to solve for x. '.repeat(20);
    assert.equal(replyKey(full), replyKey(full.slice(0, REPLY_CHARS + 5)));
    assert.notEqual(replyKey(full), replyKey('A different reply.'));
    assert.equal(replyKey('   '), null);
    assert.equal(replyKey(undefined), null);
  });
});

describe('keysForTurn', () => {
  test('the photo turn and its later replays get the same keys', () => {
    // The turn as it arrives with its imageId, and as it is replayed later.
    const photoTurn = [u('hi'), a('Hey! What are we working on?'), u('i got x = 16 for number 7, is that right?')];
    const later = [...photoTurn, a('Show me your steps.'), u('ok and what does number 8 say again')];
    assert.deepEqual(keysForTurn(photoTurn, 2), keysForTurn(later, 2));
  });

  test("a lesson photo turn's iOS re-tag is gone once the server normalises it", () => {
    const opener = '[CURRICULUM: Unit 1, Lesson 1] Teach me about tokens.';
    const sent = normalizeReplayedHistory([u(opener), a('Tokens are…'), u(`[CURRICULUM: Unit 1, Lesson 1] ${SHARED}`)]);
    const replayed = normalizeReplayedHistory([u(opener), a('Tokens are…'), u(SHARED), a('I see a worksheet.'), u('[CURRICULUM: Unit 1, Lesson 1] what is #8')]);
    assert.equal(sent[2].content, SHARED);
    assert.deepEqual(keysForTurn(sent, 2), keysForTurn(replayed, 2));
  });

  test('iOS 2.0.0 long lesson turn: the 2,000-char cut differs by the re-tag, the keys do not', () => {
    const tag = '[CURRICULUM: Unit 1, Lesson 1]';
    const long = 'my working: '.repeat(200); // 2,400 chars
    const opener = `${tag} Teach me about tokens.`;
    // The photo turn: tagged, then cut to 2,000 with the tag inside the cut.
    const photo = normalizeReplayedHistory([u(opener), a('Tokens are…'), u(truncateUnits(`${tag} ${long}`, 2000))]);
    // A replay: untagged, cut to 2,000.
    const replay = normalizeReplayedHistory([u(opener), a('Tokens are…'), u(truncateUnits(long, 2000)), a('ok'), u('next')]);
    assert.notEqual(photo[2].content, replay[2].content, 'the bytes really differ');
    assert.deepEqual(keysForTurn(photo, 2), keysForTurn(replay, 2));
  });

  test('two photo-only turns share a turnKey but not an anchorKey', () => {
    const thread = [u(SHARED), a('That is problem 7.'), u(SHARED), a('That is page 2.'), u('thanks')];
    const k0 = keysForTurn(thread, 0);
    const k2 = keysForTurn(thread, 2);
    assert.equal(k0.turnKey, k2.turnKey);
    assert.notEqual(k0.anchorKey, k2.anchorKey);
  });

  test('null for an assistant turn, an empty turn, or an index out of range', () => {
    const thread = [u('  '), a('hi'), u('x')];
    assert.equal(keysForTurn(thread, 0), null);
    assert.equal(keysForTurn(thread, 1), null);
    assert.equal(keysForTurn(thread, 3), null);
    assert.equal(keysForTurn(null, 0), null);
  });
});

describe('plan', () => {
  const photoThread = [u('hi'), a('Hey!'), u(SHARED), a('I see a worksheet with problems 7 and 8.'), u('what is #8?')];

  test('the photo lands on the turn it came with, never on the new turn', () => {
    const links = [linkFor('img1', photoThread, 2)];
    assert.deepEqual(plan({ thread: photoThread, links }), [{ index: 2, id: 'img1' }]);
  });

  test('no links, or no earlier turn, plans nothing', () => {
    assert.deepEqual(plan({ thread: photoThread, links: [] }), []);
    assert.deepEqual(plan({ thread: [u(SHARED)], links: [linkFor('x', [u(SHARED)], 0)] }), []);
  });

  test('a photo from another thread position does not match (different anchor)', () => {
    const other = [u('something else'), a('Sure.'), u(SHARED), a('A chart.'), u('ok')];
    const links = [linkFor('elsewhere', other, 2)];
    assert.deepEqual(plan({ thread: photoThread, links }), []);
  });

  test('two photo-only turns each get their own photo', () => {
    const thread = [u(SHARED), a('That is problem 7.'), u(SHARED), a('That is page 2.'), u('thanks')];
    const links = [linkFor('page2', thread, 2), linkFor('page1', thread, 0)]; // newest first
    assert.deepEqual(plan({ thread, links }), [{ index: 2, id: 'page2' }, { index: 0, id: 'page1' }]);
  });

  test('an iOS Retry (same turn, re-uploaded) uses the newest upload only', () => {
    const thread = [u(SHARED), a('That is problem 7.'), u(SHARED), a('That is page 2.'), u('thanks')];
    const links = [
      linkFor('retry2', thread, 2),
      linkFor('retry1', thread, 2),
      linkFor('page1', thread, 0),
    ];
    assert.deepEqual(plan({ thread, links }), [{ index: 2, id: 'retry2' }, { index: 0, id: 'page1' }]);
  });

  test('two chats that each open with a photo-only turn: the reply that followed picks the photo', () => {
    // Same text, nothing before it: the two turns share an anchor.
    const chat1 = [u(SHARED), a('That worksheet is about solving for x.'), u('what is #8?')];
    const chat2 = [u(SHARED), a('That is a graph of phone plan costs.'), u('what is #8?')];
    assert.equal(keysForTurn(chat1, 0).anchorKey, keysForTurn(chat2, 0).anchorKey);
    const links = [linkFor('newer', chat2, 0), linkFor('older', chat1, 0)]; // newest first
    assert.deepEqual(plan({ thread: chat2, links }), [{ index: 0, id: 'newer' }]);
    assert.deepEqual(plan({ thread: chat1, links }), [{ index: 0, id: 'older' }], 'not the newer chat\'s photo');
    // A link with no reply recorded never claims a turn that has a reply.
    const bare = links.map((l) => ({ ...l, replyKey: null }));
    assert.deepEqual(plan({ thread: chat1, links: bare }), []);
  });

  test('a chat that opens with the same words as another chat\'s photo turn never gets that photo (review probe 1)', () => {
    // Chat A: the photo turn, answered. Chat B: the same words, no photo,
    // a different reply. Same session, so both links are the session's.
    const chatA = [u('can you help me with this'), a('That worksheet is about solving for x. Which one first?'), u('#5')];
    const chatB = [u('can you help me with this'), a('Sure. What are you working on?'), u('problem 1')];
    assert.equal(keysForTurn(chatA, 0).anchorKey, keysForTurn(chatB, 0).anchorKey, 'they share an anchor');
    const links = [linkFor('photoA', chatA, 0)];
    assert.deepEqual(plan({ thread: chatB, links }), []);
    assert.deepEqual(plan({ thread: chatA, links }), [{ index: 0, id: 'photoA' }], 'chat A still gets its own');
    // Chat B's opener got no reply in its thread (a failed first reply that
    // an older build dropped): nothing before it, so nothing ties it to A.
    assert.deepEqual(plan({ thread: [u('can you help me with this'), u('hello?')], links }), []);
  });

  test('a photo sent mid-chat does not land on another chat\'s identical opener (review probe 2, the text-only fallback)', () => {
    const chatA = [u('i have algebra homework'), a('Nice, what is it?'), u('what about this one?'), a('That one is a quadratic. What do you notice first?'), u('ok')];
    const links = [linkFor('photoA', chatA, 2)];
    const chatB = [u('what about this one?'), a('Which one do you mean? Paste or type it.'), u('the quadratic')];
    assert.equal(keysForTurn(chatB, 0).turnKey, links[0].turnKey, 'same words');
    assert.deepEqual(plan({ thread: chatB, links }), []);
    assert.deepEqual(plan({ thread: chatA, links }), [{ index: 2, id: 'photoA' }]);
  });

  test('re-attached while at most maxTurns user turns follow the photo turn', () => {
    const base = [u('hi'), a('Hey!'), u(SHARED)];
    const link = linkFor('img', [...base, a('reply 1')], 2);
    let thread = base.slice();
    const seen = [];
    for (let n = 1; n <= DEFAULT_MAX_TURNS + 2; n++) {
      thread = [...thread, a(`reply ${n}`), u(`follow-up ${n}`)];
      seen.push(plan({ thread, links: [link] }).length);
    }
    assert.deepEqual(seen, [1, 1, 1, 1, 1, 1, 0, 0], 'follow-ups 1..6 see it, the 7th does not');
    assert.equal(DEFAULT_MAX_TURNS, 6);
    // Consecutive user turns (a failed reply) count as turns too.
    const noReply = [u('hi'), a('Hey!'), u(SHARED), u('hello?')];
    assert.equal(plan({ thread: noReply, links: [linkFor('img', noReply, 2)], maxTurns: 1 }).length, 1);
    assert.equal(plan({ thread: [...noReply, u('again')], links: [linkFor('img', noReply, 2)], maxTurns: 1 }).length, 0);
  });

  test('maxTurns 0 (or not an integer) turns it off', () => {
    const links = [linkFor('img1', photoThread, 2)];
    assert.deepEqual(plan({ thread: photoThread, links, maxTurns: 0 }), []);
    assert.deepEqual(plan({ thread: photoThread, links, maxTurns: '6' }), []);
  });

  test('the text-only fallback applies only to a turn that is first in the thread', () => {
    // Linked while the reply before it was still in the thread …
    const linkedThread = [u('hi'), a('Hey!'), u(SHARED), a('I see problem 7.')];
    const links = [linkFor('img', linkedThread, 2)];
    // … the client's byte cap later drops "hi" and "Hey!": the turn is first.
    const capped = [u(SHARED), a('I see problem 7.'), u('and #8?')];
    assert.deepEqual(plan({ thread: capped, links }), [{ index: 0, id: 'img' }]);
    // A same-text turn anywhere else is a different turn.
    const elsewhere = [u('new chat'), a('Hi!'), u(SHARED), a('?'), u('and #8?')];
    assert.deepEqual(plan({ thread: elsewhere, links }), []);
    // First in the thread, but followed by a different reply: not this photo.
    assert.deepEqual(plan({ thread: [u(SHARED), a('A graph of phone plans.'), u('and #8?')], links }), []);
  });

  test('excluded ids (the new turn\'s own photo) are never re-attached', () => {
    const links = [linkFor('img1', photoThread, 2)];
    assert.deepEqual(plan({ thread: photoThread, links, excludeIds: ['img1'] }), []);
  });

  test('at most MAX_IMAGES photos, newest turns first, and a byte budget', () => {
    let thread = [];
    for (let n = 0; n < 5; n++) thread.push(u(`${SHARED} ${n}`), a(`reply ${n}`));
    thread.push(u('which one was hardest?'));
    const links = [0, 1, 2, 3, 4].map((n) => linkFor(`img${n}`, thread, 2 * n)).reverse(); // newest first
    const picks = plan({ thread, links });
    assert.equal(MAX_IMAGES, 3);
    assert.deepEqual(picks.map((p) => p.id), ['img4', 'img3', 'img2']);
    const tight = plan({ thread, links: links.map((l) => ({ ...l, sizeBytes: 4 * 1024 * 1024 })) });
    assert.deepEqual(tight.map((p) => p.id), ['img4', 'img3'], '10 MB holds two 4 MB photos');
  });

  test('ignores malformed links', () => {
    const links = [null, { id: 7 }, { id: 'x' }, linkFor('ok', photoThread, 2)];
    assert.deepEqual(plan({ thread: photoThread, links }), [{ index: 2, id: 'ok' }]);
  });
});

describe('apply', () => {
  const image = { contentType: 'image/png', dataBase64: 'iVBORw0KGgo=' };

  test('rebuilds the turn as [image, note, text] and never mutates its input', () => {
    const history = [u('hi'), a('Hey!'), u(SHARED), a('Problem 7.')];
    const before = JSON.stringify(history);
    const out = apply(history, [{ index: 2, image }]);
    assert.equal(JSON.stringify(history), before);
    assert.deepEqual(out[2], {
      role: 'user',
      content: [
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: image.dataBase64 } },
        { type: 'text', text: REATTACHED_PHOTO_NOTE },
        { type: 'text', text: SHARED },
      ],
    });
    assert.match(REATTACHED_PHOTO_NOTE, /earlier/);
    assert.match(REATTACHED_PHOTO_NOTE, /newest message/);
    assert.equal(out[0], history[0]);
    assert.equal(out[3], history[3]);
  });

  test('skips an assistant target, a bad index or an invalid image', () => {
    const history = [u('hi'), a('Hey!')];
    assert.deepEqual(apply(history, [{ index: 1, image }, { index: 9, image }, { index: 0, image: { contentType: 'text/plain', dataBase64: 'x' } }]), history);
  });
});

describe('textView', () => {
  const image = { contentType: 'image/png', dataBase64: 'iVBORw0KGgo=' };

  test('a re-attached turn reads as the student\'s words; every other turn is untouched', () => {
    const history = [u('this one: a car goes 150 km in 3 hours, how fast is it going'), a('What two things does speed compare?'), u('distance and time?')];
    const withPhoto = apply(history, [{ index: 0, image }]);
    assert.ok(Array.isArray(withPhoto[0].content));
    const view = textView(withPhoto);
    assert.deepEqual(view, history);
    assert.equal(view[1], withPhoto[1]);
    // An array turn that was not re-attached (this turn's own photo) stays an array.
    const own = [{ role: 'user', content: [{ type: 'image', source: {} }, { type: 'text', text: 'solve 3x + 5 = 20' }] }];
    assert.equal(textView(own)[0], own[0]);
  });

  test('homework detection sees a problem the student typed with an earlier photo (merge of AUD-10 with #44)', () => {
    const history = [u('this one: a car goes 150 km in 3 hours, how fast is it going'), a('What two things does speed compare?'), u('distance and time?')];
    const withPhoto = apply(history, [{ index: 0, image }]);
    assert.equal(looksLikeProblemWork(history), true);
    assert.equal(looksLikeProblemWork(withPhoto), false, 'the array turn hides the words');
    assert.equal(looksLikeProblemWork(textView(withPhoto)), true);
  });
});

describe('withHistoryBreakpoint on a re-attached photo turn', () => {
  const image = { contentType: 'image/png', dataBase64: 'iVBORw0KGgo=' };
  test('the breakpoint goes on the text block after the image', () => {
    const history = apply([u('hi'), a('Hey!'), u(SHARED)], [{ index: 2, image }]);
    const out = withHistoryBreakpoint([...history, u('hello?')], { window: 40 });
    assert.equal(out[2].content.length, 3);
    assert.equal(out[2].content[0].type, 'image');
    assert.equal(out[2].content[0].cache_control, undefined);
    assert.deepEqual(out[2].content[1], { type: 'text', text: REATTACHED_PHOTO_NOTE });
    assert.deepEqual(out[2].content[2], { type: 'text', text: SHARED, cache_control: { type: 'ephemeral' } });
    assert.equal(history[2].content[2].cache_control, undefined, 'input not mutated');
  });

  test('an earlier photo turn is simply part of the cached prefix', () => {
    const history = apply([u('hi'), a('Hey!'), u(SHARED), a('Problem 7.')], [{ index: 2, image }]);
    const out = withHistoryBreakpoint([...history, u('and #8?')], { window: 40 });
    assert.equal(out[2], history[2], 'the photo turn is untouched');
    assert.deepEqual(out[3].content, [{ type: 'text', text: 'Problem 7.', cache_control: { type: 'ephemeral' } }]);
  });

  test('skipped for an array ending in an image or empty text', () => {
    const imgOnly = { role: 'user', content: [{ type: 'image', source: {} }] };
    assert.equal(withHistoryBreakpoint([imgOnly, u('x')], { window: 40 })[0], imgOnly);
    const blank = { role: 'user', content: [{ type: 'image', source: {} }, { type: 'text', text: ' ' }] };
    assert.equal(withHistoryBreakpoint([blank, u('x')], { window: 40 })[0], blank);
  });
});
