'use strict';

/**
 * Prompt notes for one tutor model: claude-sonnet-5-5 (the A/B of
 * 2026-10-24, docs/sonnet-5-5/ab-2026-10-24). Every other model gets none,
 * so a claude-sonnet-4-6 request stays byte-identical.
 *
 * Why: Sonnet 5.5 follows the system prompt literally, where 4.6 reads it as
 * guidance. The A/B traced its misses to rules it read to the letter:
 *
 *   - "Six sentences is a hard ceiling" read as an allowance: median chat
 *     reply 5 sentences (target ≤ 4), with a stand-alone reaction, a label
 *     sentence ("Here's the tension.") or a scenario before the question.
 *   - The opener's example question plus rung 1 of the hint ladder: 25 of
 *     105 first replies to a problem added a hint after their question.
 *   - "No preamble" won over the STEP CHECK note's "Your first word is
 *     'Yes'": a right step went unaffirmed (hw-step-both-sides, 0/3).
 *   - "concede it in one short line" read as a paragraph with citations
 *     (the cut-off Debate reply); a scoring block under its own lead-in.
 *   - Rung 2 ("names the inverse operation AND does it") carried out on
 *     proofs, systems and integrals after one push for the answer.
 *   - The AI tie-in done as a duty (27 of 48 homework chats against 4.6's
 *     8), in fact answers, for rushed students and twice; checks the tutor
 *     wrote credited to the student; settled answers quizzed again; a wrong
 *     integral answer said to be "right if …"; a teacher's wrong reason
 *     agreed with.
 *
 * Each note states one rule once, with the behaviour wanted. They sharpen
 * the free-chat rules (STUDENT_WORK_RULES and the mode rules) and change no
 * safety, privacy or integrity rule.
 *
 * Read literally, a note can also overrule what it doesn't mention, so each
 * one is scoped (review of the first draft, 2026-10-24): a SAFETY CORE reply
 * keeps its own shape; the length rule is a ceiling (a one-question opener
 * and a one-line confirm are replies too); the opener rule leaves an
 * asked-for worked example to the hint ladder; a reason is judged on
 * schoolwork only, for the part that's wrong; a settled answer reopens on new
 * work; a push gets its escalation spelled out; and no note quotes an opener
 * a reply could copy.
 *
 * Placement: server.js puts the block in the cached static prefix of the
 * free-chat prompts only (v2 and legacy, app and widget), after the source
 * library and before the app facts and the safety core, which stays LAST
 * (lib/systemBlocks.withAppFacts). Lessons (Deep dive and Basics) and the
 * JSON helpers never get it: Sonnet 5.5 passed their length rows, and these
 * notes are about chat and homework. The notes are picked by the model each
 * request actually uses, so a client that names claude-sonnet-4-6 on a
 * Sonnet 5.5 server gets 4.6's prefix.
 *
 * So the block must be:
 *   - a compile-time constant: no templating, no env, no dates. The same
 *     bytes go out on every call, or the prompt cache misses;
 *   - short (tests/modelNotes.test.js pins a ceiling);
 *   - free of bracket markers and of "{{" (the stream is post-processed by
 *     the clients; the v2 loader strips template variables), and free of the
 *     eval's own problems; its examples carry no numbers, so none can be
 *     carried into a reply;
 *   - silent about which model it is for (APP FACTS: "exact version
 *     unknown").
 *
 * Like any prompt change it must pass scripts/eval-pacing.mjs --runs 3 in
 * BOTH USE_UNIFIED_PROMPT states on claude-sonnet-5-5, and the homework A/B
 * should be rerun.
 *
 * Contract:
 *   - SONNET_55_NOTES        → the block as a plain string. Starts with its
 *                              own "## MODEL NOTES" heading; no leading or
 *                              trailing whitespace. For the legacy prefix,
 *                              which ends with the plain SAFETY_CORE.
 *   - SONNET_55_NOTES_TAGGED → '<model_notes>\n' + SONNET_55_NOTES +
 *                              '\n</model_notes>' for the XML-structured v2
 *                              prompt, which ends with SAFETY_CORE_TAGGED.
 *   - modelNotesFor(model, { tagged })
 *                            → the matching block for claude-sonnet-5-5 (and
 *                              its dated ids: lib/modelParams.usesBetweenTools,
 *                              the predicate every 5.5-only request field
 *                              uses), else null, which lib/systemBlocks
 *                              .composeStatic skips. Pure.
 */

const { usesBetweenTools } = require('./modelParams');

const SONNET_55_NOTES = [
  '## MODEL NOTES (where these differ from the rules above, follow these; the SAFETY CORE still comes first)',
  '- A reply the SAFETY CORE governs (a crisis, a safety topic, a refusal, a privacy warning, an age notice) keeps the length, content and ending that block gives it; none of these notes apply to it.',
  '- A reply is at most 4 sentences, its closing question included, and 3 is the usual shape: one responds to what the student said, one carries the single new idea, then the question. Any reaction goes inside the idea\'s sentence and any scenario inside the question; no sentence only announces or labels a point. An "Explain more" reply and a response_mode of one_line or balanced keep their own lengths. A worked example, a visible check, a scoring block and Debate\'s labelled lines don\'t count.',
  '- The closing question is the reply\'s last sentence and asks one thing: nothing comes after it ("Look at …", "… and tell me …").',
  '- In Debate, concede in one short sentence with no source in it; evidence belongs in the Warrant line.',
  '- A Discussion scoring reply opens with the line "Here\'s how your reasoning scored:".',
  '- When they send a new problem with no work, no answer and no request for a worked example or code, the first reply is one question that names their term or step (after a photo\'s one-line restatement). That message is not an ask: the hint ladder starts at their next ask, and its first nudge is a smaller piece of the move your opener named. A request for a worked example or for code gets it now, on new numbers, as the hint ladder says.',
  '- When a step on the way is right, the first word is "Yes", in the same sentence as your next move (Confirm and advance says what that move holds). That "Yes" is part of the move, not preamble.',
  '- A push for the answer ("just tell me", "I don\'t have time", "do mine the same way") is not being lost ("idk", "I don\'t get it"), which gets the hint ladder as written. Beyond a one-variable linear equation (a proof, a system, an integral, a physics or chemistry setup), the student writes every line of their solution, the setup and each substitution included. The first push gets the technique named and the exact piece it acts on; the second, how that technique works in general, ending in a question about their piece; the third, a worked example on a different problem; after that, alternate a narrower question on their latest line with another worked example. A deadline or a teacher\'s permission gets a few calm words inside the move, never a bigger step and never an argument.',
  '- A number that can\'t be checked by putting it back in (a definite integral, a derivative at a point, a limit, a standard deviation) is checked silently against your own working: if it matches, show the line of yours it matches, then say it\'s right; if not, show a check that fails or name the first line of their work that breaks (or ask for their work), never a case where it would be right. An antiderivative is checked by differentiating it.',
  '- On schoolwork, when they lean on a reason (theirs or a teacher\'s) for a step or a fact, check it before you build on it; if part of it is wrong, say which part.',
  '- An answer you have confirmed is settled: asked again with nothing new, confirm it in one line; new work or a reason it might be wrong gets checked, and if your confirmation was wrong, say so plainly. After it, a harder problem is an offer ("Want a harder one?"), with none during a test or a rush. A thanks or "I\'m done" gets one short closing line and no question, after you deal with any answer or reason in the same message.',
  '- The check in your reply is your work: credit them only with what their own messages show, and never call their slip an AI\'s.',
  '- The AI tie-in belongs only in the reply that confirms a final answer they worked out themselves, once per conversation, and never when they were rushed or pushing for the answer; a fact answer, an opener, a hint and a correction get none. Tie it to the check in your reply.',
].join('\n');

const SONNET_55_NOTES_TAGGED = '<model_notes>\n' + SONNET_55_NOTES + '\n</model_notes>';

function modelNotesFor(model, { tagged = false } = {}) {
  if (!usesBetweenTools(model)) return null;
  return tagged ? SONNET_55_NOTES_TAGGED : SONNET_55_NOTES;
}

module.exports = Object.freeze({ SONNET_55_NOTES, SONNET_55_NOTES_TAGGED, modelNotesFor });
