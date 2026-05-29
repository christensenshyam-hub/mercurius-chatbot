'use strict';

const fs = require('fs');
const path = require('path');

/**
 * The unified v2 Mercurius system prompt — one prompt with an internal
 * <mode_router> that handles all app modes, replacing the 10 separate
 * per-mode prompt constants.
 *
 * Loaded once at startup. We strip the {{template_vars}} the Console
 * authoring format uses, because the live per-request context is injected
 * SEPARATELY via buildRuntimeContext() as its own block. Keeping this text
 * byte-stable is what lets it cache (prompt caching is a prefix match — any
 * per-request byte in here would defeat it).
 */
const PROMPT_PATH = path.join(__dirname, '..', 'prompts', 'mercurius-v2.md');
let UNIFIED_PROMPT = '';
try {
  UNIFIED_PROMPT = fs.readFileSync(PROMPT_PATH, 'utf8').replace(/\{\{[^}]*\}\}/g, '');
} catch (e) {
  // Defensive: never let a missing/unreadable prompt file crash startup.
  // With USE_UNIFIED_PROMPT off this value is unused; with it on, the chat
  // handler treats an empty prompt as "fall back to the legacy path" rather
  // than shipping an empty system prompt. This guarantees a flag-off deploy
  // can never take production down on a file-load failure.
  console.error('[unifiedPrompt] failed to load prompt file — v2 path will fall back to legacy:', e.message);
}

/**
 * Map the backend's lowercase mode + test/curriculum state to the
 * uppercase mode tokens the unified prompt's <mode_router> expects.
 */
const MODE_TOKENS = {
  socratic: 'SOCRATIC',
  direct: 'DIRECT',
  debate: 'DEBATE',
  discussion: 'DISCUSSION',
  curriculum: 'CURRICULUM',
  test: 'TEST_EVALUATOR',
};

/**
 * Build the per-request volatile context block. Injected AFTER the cached
 * system prompt (as a second system block), so nothing here touches the
 * cached prefix. Only non-empty sections are emitted — the prompt is built
 * to "continue gracefully if context is missing," so empty tags are noise.
 *
 * @param {object} o
 * @param {string} o.mode            uppercase mode token (see MODE_TOKENS)
 * @param {string} o.responseMode    one_line | concise | balanced | deep
 * @param {boolean} o.unlocked       direct-mode unlock flag
 * @param {string} o.currentDate     ISO date (YYYY-MM-DD)
 * @param {string} [o.memory]        persistent memory profile text
 * @param {string} [o.performance]   difficulty + struggled-topics note
 * @param {string} [o.meeting]       live meeting/events context
 * @param {string} [o.blog]          blog library context
 */
function buildRuntimeContext({ mode, responseMode, unlocked, currentDate, memory, performance, meeting, blog }) {
  const parts = [
    '<runtime>',
    `  <mode>${mode}</mode>`,
    `  <response_mode>${responseMode}</response_mode>`,
    `  <direct_mode_unlocked>${unlocked ? 'true' : 'false'}</direct_mode_unlocked>`,
    `  <current_date>${currentDate}</current_date>`,
    '</runtime>',
  ];
  const tag = (name, value) => {
    const v = (value || '').trim();
    if (v) parts.push(`<${name}>\n${v}\n</${name}>`);
  };
  tag('conversation_memory', memory);
  tag('recent_performance', performance);
  tag('meeting_context', meeting);
  tag('blog_context', blog);
  return parts.join('\n');
}

module.exports = { UNIFIED_PROMPT, MODE_TOKENS, buildRuntimeContext };
