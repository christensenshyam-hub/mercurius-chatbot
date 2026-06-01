'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');

const { buildUserContent } = require('../lib/visionContent');

const IMG = { contentType: 'image/jpeg', dataBase64: 'QUJDRA==' };

describe('buildUserContent', () => {
  test('text-only returns a plain string (unchanged behavior)', () => {
    assert.equal(buildUserContent('What is an LLM?', null), 'What is an LLM?');
    assert.equal(buildUserContent('  trimmed  ', null), 'trimmed');
  });

  test('with a valid image returns a multimodal [image, text] array', () => {
    const out = buildUserContent('What is this?', IMG);
    assert.ok(Array.isArray(out));
    assert.equal(out.length, 2);
    assert.deepEqual(out[0], {
      type: 'image',
      source: { type: 'base64', media_type: 'image/jpeg', data: 'QUJDRA==' },
    });
    assert.equal(out[1].type, 'text');
    assert.equal(out[1].text, 'What is this?');
  });

  test('image with empty text gets a default, non-empty text block', () => {
    const out = buildUserContent('', IMG);
    assert.ok(Array.isArray(out));
    assert.equal(out[1].type, 'text');
    assert.ok(out[1].text.length > 0, 'text block must be non-empty for the API');
  });

  test('unsupported image content type degrades to text-only', () => {
    const out = buildUserContent('hello', { contentType: 'image/tiff', dataBase64: 'QUJD' });
    assert.equal(out, 'hello');
  });

  test('missing/empty image data degrades to text-only', () => {
    assert.equal(buildUserContent('hi', { contentType: 'image/png', dataBase64: '' }), 'hi');
    assert.equal(buildUserContent('hi', null), 'hi');
    assert.equal(buildUserContent('hi', undefined), 'hi');
  });

  test('each allowed type produces an image block', () => {
    for (const ct of ['image/jpeg', 'image/png', 'image/webp', 'image/gif']) {
      const out = buildUserContent('x', { contentType: ct, dataBase64: 'QUJD' });
      assert.ok(Array.isArray(out), `${ct} should be multimodal`);
      assert.equal(out[0].source.media_type, ct);
    }
  });
});
