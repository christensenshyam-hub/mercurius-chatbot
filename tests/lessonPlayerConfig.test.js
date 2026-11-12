'use strict';

// The lesson player pilot's flag: off unless LESSON_PLAYER_ENABLED is set,
// read-only to clients through GET /api/lesson-player/config.

const { describe, test, after } = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnServer } = require('./support/spawnServer');
const { lessonPlayerConfig, PILOT_LESSONS } = require('../lib/lessonPlayer');

describe('lessonPlayerConfig', () => {
  test('off by default, with no lessons', () => {
    assert.deepEqual(lessonPlayerConfig({}), { enabled: false, lessons: [] });
    assert.deepEqual(lessonPlayerConfig({ LESSON_PLAYER_ENABLED: '0' }), { enabled: false, lessons: [] });
    assert.deepEqual(lessonPlayerConfig({ LESSON_PLAYER_ENABLED: 'yes' }), { enabled: false, lessons: [] });
  });

  test('on lists every pilot lesson, or the ones named', () => {
    assert.deepEqual(lessonPlayerConfig({ LESSON_PLAYER_ENABLED: '1' }), { enabled: true, lessons: PILOT_LESSONS.slice() });
    assert.deepEqual(lessonPlayerConfig({ LESSON_PLAYER_ENABLED: 'true', LESSON_PLAYER_LESSONS: 'u1_l3, nope' }),
      { enabled: true, lessons: ['u1_l3'] });
  });
});

describe('GET /api/lesson-player/config', () => {
  const procs = [];
  after(() => { for (const p of procs) p.kill(); });

  async function boot(env) {
    const dbPath = path.join(os.tmpdir(), `merc-lp-config-${crypto.randomBytes(4).toString('hex')}.db`);
    const { proc, ready } = spawnServer({ SQLITE_PATH: dbPath, ...env });
    procs.push(proc);
    return (await ready).base;
  }

  test('reports off by default, without a session and without caching', async () => {
    const base = await boot({});
    const res = await fetch(`${base}/api/lesson-player/config`);
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await res.json(), { enabled: false, lessons: [] });
  });

  test('reports on when the env flag is set', async () => {
    const base = await boot({ LESSON_PLAYER_ENABLED: '1' });
    const body = await (await fetch(`${base}/api/lesson-player/config`)).json();
    assert.equal(body.enabled, true);
    assert.deepEqual(body.lessons, PILOT_LESSONS.slice());
  });
});
