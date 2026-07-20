'use strict';

const { describe, test } = require('node:test');
const assert = require('node:assert/strict');
const { useUnifiedSystem } = require('../lib/unifiedPrompt');

// The gate that decides whether /api/chat serves the unified v2 system
// prompt. The load-bearing row is the curriculum exemption: v2 has no
// lesson machinery, so a lesson served by v2 loses the beat structure and
// the [CHECK]/[LESSON_COMPLETE] contract (lessons never complete). This
// regressed silently in prod because only the flag-off path was evaluated.
describe('useUnifiedSystem', () => {
  test('serves v2 for chat modes when flag on and prompt loaded', () => {
    assert.equal(useUnifiedSystem({ flagOn: true, promptLoaded: true, isCurriculum: false }), true);
  });

  test('NEVER serves v2 for curriculum, even with flag on', () => {
    assert.equal(useUnifiedSystem({ flagOn: true, promptLoaded: true, isCurriculum: true }), false);
  });

  test('falls back to legacy when the prompt file failed to load', () => {
    assert.equal(useUnifiedSystem({ flagOn: true, promptLoaded: false, isCurriculum: false }), false);
  });

  test('flag off means legacy for everything', () => {
    assert.equal(useUnifiedSystem({ flagOn: false, promptLoaded: true, isCurriculum: false }), false);
    assert.equal(useUnifiedSystem({ flagOn: false, promptLoaded: true, isCurriculum: true }), false);
  });
});
