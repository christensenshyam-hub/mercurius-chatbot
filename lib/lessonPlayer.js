'use strict';

// The interactive lesson player pilot (docs/lesson-player-pilot/).
//
// The flag: LESSON_PLAYER_ENABLED (off unless "1" or "true") decides whether
// iOS opens a NEW attempt at a pilot lesson in the player. It is read-only
// to clients through GET /api/lesson-player/config, so turning it off is an
// env change and a restart, not an app release. An attempt already started
// keeps its experience either way (the client pins it).
//
// LESSON_PLAYER_LESSONS optionally narrows the pilot to some of the lessons
// the app has player content for (comma-separated ids). Unset = all of them.

const PILOT_LESSONS = Object.freeze(['u1_l3', 'b1_l1']);

function isOn(value) {
  return value === '1' || value === 'true';
}

function lessonPlayerConfig(env = process.env) {
  const enabled = isOn(env.LESSON_PLAYER_ENABLED);
  let lessons = PILOT_LESSONS.slice();
  if (typeof env.LESSON_PLAYER_LESSONS === 'string' && env.LESSON_PLAYER_LESSONS.trim()) {
    const wanted = new Set(env.LESSON_PLAYER_LESSONS.split(',').map((s) => s.trim()));
    lessons = lessons.filter((id) => wanted.has(id));
  }
  return { enabled, lessons: enabled ? lessons : [] };
}

module.exports = { PILOT_LESSONS, lessonPlayerConfig };
