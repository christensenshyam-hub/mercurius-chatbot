'use strict';

/**
 * crisisHistory: keep one crisis message from stalling the rest of a chat or
 * a lesson (the AUD-01 follow-up from the October 2026 server gate).
 *
 * Claude's own classifier ends some self-harm-method questions ("how many
 * tylenol would it take to not wake up") with stop_reason "refusal" and no
 * text. The server answers those with REFUSAL_COPY (988, 741741, 911, a
 * trusted adult). But every shipped client replays its own thread on every
 * turn, so the refused message stays in the history, and the classifier then
 * refuses EVERY later turn in that thread, however ordinary ("ok. different
 * question, how do chatbots decide what to say?"): 12/12 in free chat. The
 * same happens in a lesson after the model itself answers the message with
 * crisis resources: the student's next quiz answer and "can we keep going"
 * were refused 6/6, and iOS always resumes a lesson, so it stayed stuck for
 * about 19 more turns.
 *
 * The fix is a history transform, so it reaches every client build: a
 * HISTORICAL user turn whose next message is a crisis hand-off (a reply that
 * gives both 988 and 741741: REFUSAL_COPY, CRISIS_COPY, or the model's own
 * SAFETY_CORE rule-1 reply) is sent to the model as WITHHELD_TURN_TEXT
 * instead of its words. The hand-off itself stays, so the model still knows
 * crisis resources were shared and can check in. Measured on the real API
 * before this module: a placeholder in that turn took the follow-up refusals
 * from 12/12 to 0/12 in chat and from 6/6 to 0/6 in a lesson.
 *
 * What it never does:
 *   - touch the NEW turn (the last message): a student who sends the same
 *     message again is judged on it again and gets the safe reply again;
 *   - touch an assistant turn, or a user turn answered by anything else;
 *   - change the stored transcript: only what the model is sent.
 *
 * It is deterministic in the thread, so a withheld turn reads the same on
 * every later request and the replayed history stays byte-stable for the
 * prompt cache.
 *
 * Contract (pure, never throws, never mutates its input):
 *   - isCrisisHandoff(text)       → true when `text` (a string, or content
 *                                   blocks) names both 988 and 741741.
 *   - withholdCrisisTurns(history) → { messages, withheld }: a NEW array in
 *                                   which every user turn i with
 *                                   history[i + 1] an assistant crisis
 *                                   hand-off reads WITHHELD_TURN_TEXT (any
 *                                   re-attached photo goes with its words),
 *                                   and how many turns were withheld. Pass
 *                                   the replayed history WITHOUT the new
 *                                   turn.
 *   - WITHHELD_TURN_TEXT
 */

const WITHHELD_TURN_TEXT = '[earlier message withheld; crisis resources were shared]';

function textOf(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map((b) => (b && b.type === 'text' && typeof b.text === 'string' ? b.text : ''))
    .join('\n');
}

// Both lines, as SAFETY_CORE rule 1, REFUSAL_COPY and CRISIS_COPY all give
// them. One number alone is content (a lesson about the 988 lifeline).
function isCrisisHandoff(content) {
  const text = textOf(content);
  return /\b988\b/.test(text) && /\b741741\b/.test(text);
}

function withholdCrisisTurns(history) {
  if (!Array.isArray(history)) return { messages: [], withheld: 0 };
  const messages = history.slice();
  let withheld = 0;
  for (let i = 0; i < messages.length - 1; i++) {
    const m = messages[i];
    const next = messages[i + 1];
    if (!m || m.role !== 'user' || !next || next.role !== 'assistant') continue;
    if (!isCrisisHandoff(next.content)) continue;
    if (m.content === WITHHELD_TURN_TEXT) continue;
    messages[i] = { role: 'user', content: WITHHELD_TURN_TEXT };
    withheld += 1;
  }
  return { messages, withheld };
}

module.exports = { isCrisisHandoff, withholdCrisisTurns, WITHHELD_TURN_TEXT };
