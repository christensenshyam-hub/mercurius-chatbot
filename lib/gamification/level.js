'use strict';

/**
 * Deterministic Level curve for the standby gamification system.
 *
 * LEVEL ≠ RANK. Level is the XP-driven engagement track (dopamine). It maps a
 * cumulative XP total to a Level for progress bars and the progress display.
 * It says NOTHING about AI-literacy mastery — that is Rank, a separate
 * credentialed ladder this file must never reference or compute.
 *
 * Curve: the cumulative XP required to REACH level L is
 *     xpForLevel(L) = round(BASE * (L - 1) ^ EXPONENT)
 * a smooth super-linear curve so early levels come quickly (encouraging) and
 * later levels stretch out (without ever implying competence). All tunables
 * live in CONFIG — no magic numbers below.
 */

const CONFIG = Object.freeze({
  BASE: 100,
  EXPONENT: 1.5,
  MAX_LEVEL: 50,
});

/** Cumulative XP required to reach `level` (level 1 = 0 XP). */
function xpForLevel(level) {
  const L = Math.max(1, Math.min(CONFIG.MAX_LEVEL, Math.floor(level)));
  if (L <= 1) return 0;
  return Math.round(CONFIG.BASE * Math.pow(L - 1, CONFIG.EXPONENT));
}

/** The Level for a given cumulative XP (clamped to [1, MAX_LEVEL]). */
function levelForXp(xp) {
  const x = Math.max(0, Math.floor(xp || 0));
  let level = 1;
  while (level < CONFIG.MAX_LEVEL && xpForLevel(level + 1) <= x) level++;
  return level;
}

/** XP remaining until the next level (0 at MAX_LEVEL). */
function xpToNext(xp) {
  const x = Math.max(0, Math.floor(xp || 0));
  const level = levelForXp(x);
  if (level >= CONFIG.MAX_LEVEL) return 0;
  return Math.max(0, xpForLevel(level + 1) - x);
}

/** Progress through the current level as a 0..1 fraction (1 at MAX_LEVEL). */
function progressPercent(xp) {
  const x = Math.max(0, Math.floor(xp || 0));
  const level = levelForXp(x);
  if (level >= CONFIG.MAX_LEVEL) return 1;
  const floor = xpForLevel(level);
  const ceil = xpForLevel(level + 1);
  if (ceil <= floor) return 0;
  return (x - floor) / (ceil - floor);
}

/** Bundle the whole derived Level view for a given XP total. */
function levelState(xp) {
  const x = Math.max(0, Math.floor(xp || 0));
  const level = levelForXp(x);
  return {
    xp: x,
    level,
    xpForCurrentLevel: xpForLevel(level),
    xpForNextLevel: level >= CONFIG.MAX_LEVEL ? null : xpForLevel(level + 1),
    xpToNext: xpToNext(x),
    progress: progressPercent(x),
    isMax: level >= CONFIG.MAX_LEVEL,
  };
}

module.exports = { CONFIG, xpForLevel, levelForXp, xpToNext, progressPercent, levelState };
