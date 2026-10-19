'use strict';

/**
 * The few facts about the Mercurius app itself that the tutor may state.
 *
 * Audit 2026-10 found the tutor making these up or dodging them because no
 * prompt carried them: "I won't store your info" and "how your school set up
 * the app" (AUD-03), "I can't confirm or deny" which model it runs on although
 * the app's own consent screen names Anthropic's Claude (AUD-20), and "Debate
 * mode is something the app activates" with no hint to tap the button
 * (AUD-43). This block is the one source for those answers.
 *
 * It goes in the cached static prefix of every chat, lesson and widget call,
 * immediately BEFORE the safety core (lib/systemBlocks.withAppFacts does the
 * placement), so it must be:
 *
 *   - a compile-time constant: no templating, no env, no dates — the same
 *     bytes on every call, or the prompt cache misses;
 *   - short (about 230 tokens at most; tests/appFacts.test.js pins it);
 *   - true today, and only what the app's own surfaces already say. Sources:
 *       storage/retention  marketing/privacy.html ("How long we keep it") and
 *                          lib/scheduler.js RETENTIONS (MESSAGE_RETENTION_DAYS
 *                          90, IMAGE_RETENTION_HOURS 24, REPORT_RETENTION_DAYS
 *                          180)
 *       no training        marketing/privacy.html (Anthropic: "does not train
 *                          future models on API requests by default"); the
 *                          page states no Anthropic retention period, so the
 *                          block points to anthropic.com/legal as the page does
 *       Claude/Anthropic   ios OnboardingSteps.swift DisclosureStep and
 *                          SettingsFeature PrivacyChoicesView.swift
 *       delete control     iOS Settings "Delete my data & start over" (iOS
 *                          2.3.0+, commit f655c85; the App Store's 2.0.0 has
 *                          none, hence the privacy page's email fallback);
 *                          widget "Privacy & your data" → the same button
 *       modes              NetworkingKit ChatMode.displayName (Socratic,
 *                          Debate, Discussion): iOS ModeSelectorView pills at
 *                          the top of the chat; widget sidebar "Mode" section
 *       Explain more       iOS ChatView / CurriculumLessonView follow-up chip
 *                          (the web widget has none)
 *     If any of those change (a retention env override in Railway included),
 *     change this block and SAFETY_CORE rule 5 in the same commit.
 *   - free of bracket markers, so nothing here can leak into the client
 *     contract ([CHECK], [Q], [LESSON_COMPLETE] …).
 *
 * Editing it changes the cached prefix for every mode at once (a one-time
 * cache miss on deploy), and like any prompt change it must pass
 * scripts/eval-pacing.mjs --runs 3 in BOTH USE_UNIFIED_PROMPT states.
 *
 * Contract:
 *   - APP_FACTS        → the block as a plain string. Starts with its own
 *                        "## APP FACTS" heading; no leading or trailing
 *                        whitespace. For the legacy and curriculum prefixes,
 *                        which end with the plain SAFETY_CORE.
 *   - APP_FACTS_TAGGED → '<app_facts>\n' + APP_FACTS + '\n</app_facts>' for
 *                        the XML-structured v2 prompt, which ends with
 *                        SAFETY_CORE_TAGGED.
 */

const APP_FACTS = [
  '## APP FACTS (state plainly when asked; invent no others)',
  '- Your replies are written by Claude, an AI model made by Anthropic; say so if asked (exact version unknown).',
  '- Messages and photos go through the Mercurius server to Anthropic; the server keeps chats up to 90 days, photos 24 hours and reported replies (with the message before) 180 days, under a random ID, no name. "Delete my data & start over" (app: Settings; web: Privacy & your data) erases it all (before app 2.3: email privacy@trymercurius.com).',
  '- Anthropic does not train its models on these chats by default; its own retention is in its terms at anthropic.com/legal.',
  '- No accounts; no school or teacher dashboards.',
  '- Only the student can switch modes, with the Socratic, Discussion and Debate buttons (app: top of the chat; web: side menu); name the button to tap. In the app, "Explain more" under a reply goes deeper.',
].join('\n');

const APP_FACTS_TAGGED = '<app_facts>\n' + APP_FACTS + '\n</app_facts>';

module.exports = Object.freeze({ APP_FACTS, APP_FACTS_TAGGED });
