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
 *     or a hotline number (988 / 741741) in text OUTSIDE the first JSON
 *     object, i.e. prose the parser would otherwise discard. A normal JSON
 *     result that mentions 988 inside its own fields is not a crisis reply.
 *
 * Both are pure and never throw; non-strings are false.
 */

// Straight apostrophes only after normalisation; the model and phones both
// produce curly ones.
function normalise(text) {
  return String(text).toLowerCase().replace(/[’‘`]/g, "'").replace(/\s+/g, ' ');
}

const INTENSIFIERS = '(?:(?:so|really|just|honestly|kind of|kinda|pretty|very|super|lowkey|literally|actually|sometimes|still|always|often|feeling|getting) )*';

const CRISIS_PATTERNS = [
  // Suicide, stated about oneself.
  /\bkill(?:ing)? my ?self\b/,
  /\b(?:gonna|going to|want to|wanna|about to|might|i'll|i will) kms\b/,
  /\b(?:end|ending|take|taking) my (?:own )?life\b/,
  new RegExp(`\\bi(?:'m| am|m)? ${INTENSIFIERS}(?:want|wanna|ready|wish i could)(?: to)? die\\b(?! (?:of|from|laughing|when|if|at|on|in|for))`),
  /\bi (?:don't|do not|dont) want to (?:live|be alive|exist|be here) any ?more\b/,
  /\bi (?:don't|do not|dont) want to be alive\b/,
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
  /\b(?:want|wanna|going|gonna|tried|trying|try|thinking about|thought about|urge to|keep|started|start) (?:to )?(?:hurt|harm|burn|hurting|harming|burning) my ?self\b/,
  /\bi(?:'ve| have| am|'m|m)? (?:been )?self[- ]?harm(?:ing|ed)?\b/,
  // Abuse or danger, stated about oneself.
  /\bi(?:'m| am|m|'ve been| have been| was| get| got)(?: being)? (?:abused|molested|raped|sexually assaulted)\b/,
  /\b(?:my|our) (?:\w+ )?(?:dad|mom|father|mother|stepdad|stepmom|stepfather|stepmother|parents?|brother|sister|uncle|aunt|grandpa|grandma|boyfriend|girlfriend|coach|teacher|guardian) (?:hits|beats|abuses|hurts|touches|molests|rapes|hit|beat|abused|hurt|touched|molested|raped) me\b/,
  /\bi(?:'m| am|m) not safe (?:at home|here|with)\b/,
  /\b(?:someone|he|she|they) (?:is|are|'s|'re) (?:going to|gonna) (?:hurt|kill) me\b/,
];

function crisisSignal(text) {
  if (typeof text !== 'string' || text.trim() === '') return false;
  const t = normalise(text);
  return CRISIS_PATTERNS.some((re) => re.test(t));
}

const HOTLINE_RE = /\b988\b|\b741741\b/;

function isCrisisReply(raw) {
  if (typeof raw !== 'string') return false;
  const match = raw.match(/\{[\s\S]*\}/);
  let outside = raw;
  if (match) {
    try {
      const parsed = JSON.parse(match[0]);
      if (parsed && (parsed.crisis === true || parsed.crisis === 'true')) return true;
      outside = raw.replace(match[0], ' ');
    } catch {
      // Not JSON: the whole reply is prose.
    }
  }
  return HOTLINE_RE.test(outside);
}

module.exports = { crisisSignal, isCrisisReply };
