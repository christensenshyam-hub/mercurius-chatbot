'use strict';

/**
 * Crisis handling for the JSON helper routes (unit-test grading, fact-check,
 * quiz, report card, concept map, analyze).
 *
 * Chat and lessons rely on SAFETY_CORE rule 1 alone: the model's reply IS what
 * the student reads. A helper route is different: its reply must be a JSON
 * object, and a model that follows rule 1 in prose used to be thrown away as
 * a parse error ("please try again"), while one that kept to the contract
 * returned a grade. Two pieces close that:
 *
 *   - crisisSignal(text) → a deterministic floor run BEFORE the model call on
 *     routes that carry the student's own words (the unit-test defense
 *     answer, a fact-check claim). It matches FIRST-PERSON statements only:
 *     "I want to die", "I cut myself last night", "my dad hits me". Bare topic
 *     words ("suicide", "self-harm") never match, because the unit 8 defense
 *     invites answers about real AI harms ("a chatbot encouraged a teen's
 *     suicide") and those must still be graded. Anything subtler is left to
 *     the model, which sees SAFETY_CORE on every helper route.
 *   - isCrisisReply(raw) → whether a helper route's raw model reply took the
 *     rule-1 hand-off: a JSON object with crisis:true (HELPER_CRISIS_RULE),
 *     or both hotline numbers (988 AND 741741) in text OUTSIDE the JSON
 *     object, i.e. prose the parser would otherwise discard. A normal JSON
 *     result that mentions 988 inside its own fields is not a crisis reply,
 *     and neither is a trailing note that names only one line.
 *
 * Both are pure and never throw; non-strings are false.
 */

// Straight apostrophes only after normalisation; the model and phones both
// produce curly ones. A double-quoted span is reported speech — a unit 8
// answer quoting a real case ('the teen wrote "I want to die" and the bot
// replied') — so it is dropped here and left to the model, which sees
// SAFETY_CORE. An unclosed quote is kept.
function normalise(text) {
  return String(text)
    .toLowerCase()
    .replace(/[’‘`]/g, "'")
    .replace(/[“”„]/g, '"')
    .replace(/"[^"]*"/g, ' ')
    .replace(/\s+/g, ' ');
}

// "die of embarrassment", "die laughing", "die on this hill" are idioms.
const NOT_IDIOM = '(?! (?:of|from|laughing|on (?:this|that) hill))';

const INTENSIFIERS = '(?:(?:so|really|just|honestly|kind of|kinda|pretty|very|super|lowkey|literally|actually|sometimes|still|always|often|feeling|getting) )*';

const CRISIS_PATTERNS = [
  // Suicide, stated about oneself.
  /\bkill(?:ing)? my ?self\b/,
  /\b(?:gonna|going to|want to|wanna|about to|might|i'll|i will) kms\b/,
  // Not "take my life savings" (voice-clone scams are curriculum), "life-long",
  // or "taking my life back/over".
  /\b(?:end|ending) my (?:own )?life\b(?![- ](?:savings|long))/,
  /\b(?:take|taking) my (?:own )?life\b(?![- ](?:savings|long|over|back|in (?:my|our) (?:own )?hands|story|goals?|choices?|decisions?|habits?|insurance|lessons?|span))/,
  new RegExp(`\\bi(?:'m| am|m)? ${INTENSIFIERS}(?:want|wanna|ready|wish i could)(?: to)? die\\b${NOT_IDIOM}`),
  // "I hate my life and want to die": the subject sits before the "and".
  new RegExp(`\\b(?:and|but) ${INTENSIFIERS}(?:i )?(?:want|wanna)(?: to)? die\\b${NOT_IDIOM}`),
  /\bi (?:don't|do not|dont) (?:want to|wanna) (?:live|be alive|exist|be here) any ?more\b/,
  /\bi (?:don't|do not|dont) (?:want to|wanna) be alive\b/,
  /\bno reason (?:for me )?to (?:live|keep living|be alive|go on)\b/,
  /\bbetter off dead\b/,
  /\b(?:everyone|everybody|they|the world|my family|my friends)(?:'d| would) be better off without me\b/,
  /\bwish i (?:was|were) dead\b/,
  /\bwish i (?:had never been|was never|were never|wasn't) born\b/,
  new RegExp(`\\bi(?:'m| am|m|'ve been| have been| was| feel| felt| get| keep) ${INTENSIFIERS}suicidal\\b`),
  /\bi(?:'ve| have|'m| am)(?: been)? having (?:suicidal thoughts|thoughts (?:of|about) (?:suicide|killing myself|dying))\b/,
  /\bi(?:'ve| have)? (?:been )?(?:thinking|thought) (?:about|of) (?:ending my life|suicide)\b(?! (?:prevention|rates?|hotlines?|risk|and|in|on|by|among|as|detection|lawsuits?|cases?))/,
  // Self-harm, stated about oneself.
  /\bcut(?:ting)? my ?self\b(?! (?:off|out|short|some|a |slack|loose|free|from))/,
  // Not "I don't want to hurt myself academically by relying on ChatGPT".
  /(?<!\b(?:don't|do not|dont|never|not|won't|wouldn't|doesn't) )\b(?:want|wanna|going|gonna|tried|trying|try|thinking about|thought about|urge to|keep|started|start) (?:to )?(?:hurt|harm|burn|hurting|harming|burning) my ?self\b(?! (?:academically|financially|grade-wise))/,
  /\bi(?:'ve| have| am|'m|m)? (?:been )?self[- ]?harm(?:ing|ed)?\b/,
  // Abuse or danger, stated about oneself.
  /\bi(?:'m| am|m|'ve been| have been| was| get| got)(?: being)? (?:abused|molested|raped|sexually assaulted)\b/,
  // Not "my brother beat me at chess" or "my sister hit me up".
  /\b(?:my|our) (?:\w+ )?(?:dad|mom|father|mother|stepdad|stepmom|stepfather|stepmother|parents?|brother|sister|uncle|aunt|grandpa|grandma|boyfriend|girlfriend|coach|teacher|guardian) (?:hits|beats|abuses|hurts|touches|molests|rapes|hit|beat|abused|hurt|touched|molested|raped) me\b(?! (?:at|in|up|to|by|back|out|with (?:a |an |the |some )?(?:pop|surprise|question|quiz|test|project|joke|text|message|dm|call|email|homework|assignment|compliment|fact|story|meme|link)))/,
  /\bi(?:'m| am|m) not safe (?:at home|here\b|with (?:him|her|them|my (?:dad|mom|father|mother|stepdad|stepmom|stepfather|stepmother|parents?|brother|sister|uncle|aunt|boyfriend|girlfriend|family)))/,
  /\b(?:someone|he|she|they) (?:is|are|'s|'re) (?:going to|gonna) (?:hurt|kill) me\b/,
];

function crisisSignal(text) {
  if (typeof text !== 'string' || text.trim() === '') return false;
  const t = normalise(text);
  return CRISIS_PATTERNS.some((re) => re.test(t));
}

// Rule 1 gives BOTH lines, so a prose hand-off carries both numbers; one on
// its own is content (a quiz question about the 988 lifeline), not a hand-off.
const hasBothHotlines = (text) => /\b988\b/.test(text) && /\b741741\b/.test(text);
const CRISIS_FLAG_RE = /"crisis"\s*:\s*(?:true|"true")/;

function isCrisisReply(raw) {
  if (typeof raw !== 'string') return false;
  const start = raw.indexOf('{');
  if (start === -1) return hasBothHotlines(raw);
  const match = raw.match(/\{[\s\S]*\}/);
  let parsed;
  try {
    parsed = match ? JSON.parse(match[0]) : undefined;
  } catch {
    parsed = undefined;
  }
  if (parsed === undefined) {
    // An object that never parsed (cut off by max_tokens, or never closed):
    // its own crisis flag still counts, and only the prose BEFORE it can be
    // a hand-off — hotline numbers inside a half-written quiz are content.
    return CRISIS_FLAG_RE.test(raw.slice(start)) || hasBothHotlines(raw.slice(0, start));
  }
  if (parsed && (parsed.crisis === true || parsed.crisis === 'true')) return true;
  return hasBothHotlines(raw.replace(match[0], ' '));
}

module.exports = { crisisSignal, isCrisisReply };
