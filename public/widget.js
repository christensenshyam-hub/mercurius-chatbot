/**
 * widget.js — Mercurius Ⅰ Self-Contained Chat Widget (Full-Screen Redesign)
 *
 * Drop this onto any page alongside widget.css (or let this script inject the
 * CSS link automatically). Reads window.MercuriusConfig for configuration.
 *
 * Usage:
 *   <script>
 *     window.MercuriusConfig = { apiEndpoint: 'https://yourserver.com/api/chat' };
 *   </script>
 *   <script src="/widget.js"></script>
 *
 * No external dependencies. Vanilla JS only.
 */

(function () {
  'use strict';

  // =========================================================================
  // 1. Configuration
  // =========================================================================
  var config = window.MercuriusConfig || {};
  var API_ENDPOINT = config.apiEndpoint || 'http://localhost:3000/api/chat';
  var MODE_ENDPOINT = API_ENDPOINT.replace('/chat', '/mode');
  var QUIZ_ENDPOINT = API_ENDPOINT.replace('/chat', '/quiz');
  var REPORT_CARD_ENDPOINT = API_ENDPOINT.replace('/chat', '/report-card');
  var CONCEPT_MAP_ENDPOINT = API_ENDPOINT.replace('/chat', '/concept-map');
  var LEADERBOARD_ENDPOINT = API_ENDPOINT.replace('/chat', '/leaderboard');
  var FACTCHECK_ENDPOINT = API_ENDPOINT.replace('/chat', '/factcheck');
  var ANALYZE_ENDPOINT = API_ENDPOINT.replace('/chat', '/analyze');
  var CHALLENGE_ENDPOINT = API_ENDPOINT.replace('/chat', '/challenge');
  var PRE_BRIEFING_ENDPOINT = API_ENDPOINT.replace('/chat', '/pre-briefing');
  var PROFILE_ENDPOINT = API_ENDPOINT.replace('/chat', '/profile');

  // =========================================================================
  // 2. Session ID — persist across browser sessions using localStorage
  // =========================================================================
  var SESSION_KEY = 'merc_session_id';
  function safeGetItem(key) { try { return localStorage.getItem(key); } catch(e) { console.warn('[Mercurius]', e); return null; } }
  function safeSetItem(key, val) { try { localStorage.setItem(key, val); } catch(e) { console.warn('[Mercurius]', e); } }
  var sessionId = safeGetItem(SESSION_KEY);
  var isReturningStudent = !!sessionId;
  if (!sessionId) {
    sessionId =
      'merc_' +
      Math.random().toString(16).slice(2) +
      Math.random().toString(16).slice(2) +
      '_' +
      Date.now().toString(16);
    safeSetItem(SESSION_KEY, sessionId);
  }

  // =========================================================================
  // 3. Inject widget.css if not already present
  // =========================================================================
  (function injectCSS() {
    var cssHref = config.cssHref;
    if (!cssHref) {
      var scripts = document.querySelectorAll('script[src]');
      for (var i = 0; i < scripts.length; i++) {
        if (scripts[i].src.indexOf('widget.js') !== -1) {
          cssHref = scripts[i].src.replace('widget.js', 'widget.css');
          break;
        }
      }
    }
    if (!cssHref) return;
    var existing = document.querySelectorAll('link[rel="stylesheet"]');
    for (var j = 0; j < existing.length; j++) {
      if (existing[j].href === cssHref) return;
    }
    var link = document.createElement('link');
    link.rel = 'stylesheet';
    link.href = cssHref;
    document.head.appendChild(link);
  })();

  // =========================================================================
  // 4. State
  // =========================================================================
  var isOpen = false;
  var isLoading = false;
  var userMessageCount = 0;
  var isUnlocked = safeGetItem('merc_unlocked') === 'true';
  var currentMode = safeGetItem('merc_mode') || 'socratic';
  var reflectionIndex = 0;
  var conversationHistory = [];
  var summaryFetched = false;
  var summaryMessageCountAtFetch = 0;
  var tooltipVisible = false;
  var voiceActive = false;
  var voiceRecognition = null;
  var currentRightPanel = null; // 'quiz' | 'map' | 'report' | 'leaderboard' | 'summary' | null
  var debateRound = 0;
  var currentConversationId = null;

  // ── Conversation history helpers ──
  function getConversationList() {
    try { return JSON.parse(localStorage.getItem('merc_convos') || '[]'); } catch(e) { console.warn('[Mercurius]', e); return []; }
  }
  function saveCurrentConversation() {
    if (conversationHistory.length < 2) return; // don't save empty chats
    var list = getConversationList();
    var firstUserMsg = '';
    for (var i = 0; i < conversationHistory.length; i++) {
      if (conversationHistory[i].role === 'user') { firstUserMsg = conversationHistory[i].content; break; }
    }
    var title = firstUserMsg.slice(0, 60) || 'Untitled';
    if (title.length === 60) title += '...';
    var entry = {
      id: currentConversationId || ('conv_' + Date.now()),
      title: title,
      mode: currentMode,
      messages: conversationHistory.slice(),
      date: new Date().toISOString(),
      messageCount: conversationHistory.length
    };
    // Update existing or prepend
    var found = false;
    for (var j = 0; j < list.length; j++) {
      if (list[j].id === entry.id) { list[j] = entry; found = true; break; }
    }
    if (!found) list.unshift(entry);
    // Keep max 20 conversations
    if (list.length > 20) list = list.slice(0, 20);
    safeSetItem('merc_convos', JSON.stringify(list));
    currentConversationId = entry.id;
  }
  function loadConversation(convo) {
    conversationHistory = convo.messages.slice();
    currentConversationId = convo.id;
    userMessageCount = 0;
    for (var i = 0; i < conversationHistory.length; i++) {
      if (conversationHistory[i].role === 'user') userMessageCount++;
    }
    // Rebuild chat UI
    var container = document.getElementById('merc-messages');
    if (!container) return;
    container.innerHTML = '';
    for (var j = 0; j < conversationHistory.length; j++) {
      var msg = conversationHistory[j];
      if (msg.role === 'user') appendUserMessage(msg.content);
      else if (msg.role === 'assistant') appendBotMessage(msg.content);
    }
    scrollToBottom();
  }
  function startNewConversation() {
    saveCurrentConversation();
    conversationHistory = [];
    currentConversationId = 'conv_' + Date.now();
    userMessageCount = 0;
    var container = document.getElementById('merc-messages');
    if (container) {
      container.innerHTML = '';
      // Re-add starter topics
      container.innerHTML = '<div class="merc-topic-tags" id="merc-topic-tags"><div class="merc-topic-tags-label">Start with a topic</div>' + buildTopicTagsHTML() + '</div>';
      attachTopicTagListeners();
    }
  }
  var CURRICULUM_UNITS = [
    { id: 'unit_1', number: '01', title: 'How AI Actually Works', description: 'LLMs, training data, next-token prediction, and why AI sounds confident but can be wrong.',
      lessons: [
        { id: 'u1_l1', title: 'What happens when you type a prompt', objective: 'Understand tokenization and next-token prediction.', starter: '[CURRICULUM: Unit 1, Lesson 1] Teach me what physically happens inside an LLM when I type a prompt. Start with tokenization and next-token prediction. After explaining, give me a hands-on exercise.' },
        { id: 'u1_l2', title: 'Training data and where knowledge comes from', objective: 'Understand how LLMs are trained and what their knowledge actually is.', starter: '[CURRICULUM: Unit 1, Lesson 2] Explain where an LLM\'s knowledge comes from \u2014 training data, RLHF, and fine-tuning. After the explanation, give me an exercise to test my understanding.' },
        { id: 'u1_l3', title: 'Why AI sounds confident but can be wrong', objective: 'Understand hallucination and the confidence-accuracy gap.', starter: '[CURRICULUM: Unit 1, Lesson 3] Teach me about AI hallucination and why LLMs can sound confident even when wrong. Give a concrete example, then an exercise where I have to identify a potential hallucination.' },
        { id: 'u1_l4', title: 'Unit review and application', objective: 'Apply everything from Unit 1 to a real scenario.', starter: '[CURRICULUM: Unit 1, Lesson 4 - Review] Give me a comprehensive exercise that tests everything from Unit 1: tokenization, training data, and hallucination. Then grade my performance and tell me what to revisit.' }
      ]},
    { id: 'unit_2', number: '02', title: 'Bias & Fairness', description: 'Where AI bias comes from, real examples like COMPAS and facial recognition, and why "objective algorithm" is a myth.',
      lessons: [
        { id: 'u2_l1', title: 'Where bias enters AI systems', objective: 'Understand the pipeline of bias: data, design, deployment.', starter: '[CURRICULUM: Unit 2, Lesson 1] Walk me through how bias enters AI systems at each stage \u2014 data collection, model design, and deployment. After explaining, give me an exercise.' },
        { id: 'u2_l2', title: 'Case study: COMPAS and criminal justice', objective: 'Analyze a real-world case of algorithmic bias.', starter: '[CURRICULUM: Unit 2, Lesson 2] Teach me about the COMPAS algorithm and what went wrong. Present the case, then give me an exercise where I analyze the tradeoffs involved.' },
        { id: 'u2_l3', title: 'Facial recognition and representation', objective: 'Understand bias in computer vision systems.', starter: '[CURRICULUM: Unit 2, Lesson 3] Explain the bias problems in facial recognition systems \u2014 the Gender Shades study and Joy Buolamwini\'s work. Then give me an exercise.' },
        { id: 'u2_l4', title: 'Unit review: building a bias audit', objective: 'Apply bias analysis to a new scenario.', starter: '[CURRICULUM: Unit 2, Lesson 4 - Review] Give me a scenario where an AI system is being deployed and have me conduct a bias audit. Grade my analysis and provide detailed feedback.' }
      ]},
    { id: 'unit_3', number: '03', title: 'AI in Society', description: 'AI in hiring, healthcare, criminal justice, and education \u2014 who benefits, who gets harmed, and what the stakes are.',
      lessons: [
        { id: 'u3_l1', title: 'AI in hiring and employment', objective: 'Understand automated hiring tools and their consequences.', starter: '[CURRICULUM: Unit 3, Lesson 1] Teach me how AI is used in hiring \u2014 resume screening, video interviews, personality analysis. What are the benefits and what can go wrong? Then give me an exercise.' },
        { id: 'u3_l2', title: 'AI in healthcare', objective: 'Evaluate AI applications in medical contexts.', starter: '[CURRICULUM: Unit 3, Lesson 2] Walk me through how AI is used in healthcare \u2014 diagnostics, drug discovery, triage. What are the stakes when it fails? Give me an exercise after.' },
        { id: 'u3_l3', title: 'AI in education', objective: 'Think critically about AI tools in learning.', starter: '[CURRICULUM: Unit 3, Lesson 3] How is AI changing education \u2014 tutoring, grading, plagiarism detection? What should students and teachers be aware of? Give me an exercise.' },
        { id: 'u3_l4', title: 'Unit review: stakeholder analysis', objective: 'Map who benefits and who is harmed by an AI system.', starter: '[CURRICULUM: Unit 3, Lesson 4 - Review] Present me with a real AI deployment scenario and have me do a full stakeholder analysis: who benefits, who is harmed, what are the power dynamics. Grade my work.' }
      ]},
    { id: 'unit_4', number: '04', title: 'Prompt Engineering', description: 'How framing changes outputs, few-shot prompting, and how to use AI tools critically rather than passively.',
      lessons: [
        { id: 'u4_l1', title: 'How framing changes everything', objective: 'Learn how different phrasings produce different outputs.', starter: '[CURRICULUM: Unit 4, Lesson 1] Show me how the way I phrase a prompt completely changes the output. Give me examples of the same question asked 3 different ways with different results. Then give me a practice exercise.' },
        { id: 'u4_l2', title: 'Few-shot prompting and chain-of-thought', objective: 'Master intermediate prompting techniques.', starter: '[CURRICULUM: Unit 4, Lesson 2] Teach me few-shot prompting and chain-of-thought techniques. Explain each with examples, then give me exercises where I practice both.' },
        { id: 'u4_l3', title: 'Critical prompting: getting AI to admit uncertainty', objective: 'Learn how to prompt for honesty, not just answers.', starter: '[CURRICULUM: Unit 4, Lesson 3] Teach me how to prompt AI to be more honest \u2014 asking for confidence levels, requesting counterarguments, forcing nuance. Give me exercises to practice.' },
        { id: 'u4_l4', title: 'Unit review: prompt challenge', objective: 'Solve a real problem using advanced prompting.', starter: '[CURRICULUM: Unit 4, Lesson 4 - Review] Give me a challenging real-world task and have me write the best prompt I can for it. Then critique my prompt and suggest improvements. Grade my technique.' }
      ]},
    { id: 'unit_5', number: '05', title: 'Ethics & Alignment', description: 'The hardest problems: alignment, autonomous weapons, corporate responsibility, and what happens when AI fails.',
      lessons: [
        { id: 'u5_l1', title: 'The alignment problem', objective: 'Understand why aligning AI with human values is hard.', starter: '[CURRICULUM: Unit 5, Lesson 1] Explain the alignment problem in AI \u2014 what it is, why it is hard, and what the stakes are. Use concrete examples. Then give me an exercise.' },
        { id: 'u5_l2', title: 'Autonomous weapons and lethal AI', objective: 'Grapple with the ethics of autonomous weapons systems.', starter: '[CURRICULUM: Unit 5, Lesson 2] Teach me about autonomous weapons and the debate around lethal AI decision-making. Present both sides, then give me a scenario-based exercise.' },
        { id: 'u5_l3', title: 'Corporate responsibility and open vs. closed AI', objective: 'Understand who controls AI and why it matters.', starter: '[CURRICULUM: Unit 5, Lesson 3] Walk me through the debate about open vs. closed AI models and corporate responsibility. Who should control AI development? Exercise after.' },
        { id: 'u5_l4', title: 'Final review: your AI ethics framework', objective: 'Build a personal ethical framework for AI.', starter: '[CURRICULUM: Unit 5, Lesson 4 - Final Review] Have me build my own AI ethics framework from everything I have learned across all 5 units. Ask me hard questions, challenge my reasoning, and grade the result.' }
      ]}
  ];
  var ACHIEVEMENTS_DEF = [
    { id: 'first_chat', icon: 'I', name: 'First Conversation', desc: 'Sent your first message to Mercurius' },
    { id: 'critical_thinker', icon: 'II', name: 'Critical Thinker', desc: 'Unlocked Direct Mode by demonstrating genuine thinking' },
    { id: 'debate_starter', icon: 'III', name: 'Debate Starter', desc: 'Entered Debate Mode and challenged Mercurius' },
    { id: 'fact_checker', icon: 'IV', name: 'Fact Checker', desc: 'Used the Fact Check tool to verify an AI claim' },
    { id: 'analyst', icon: 'V', name: 'AI Output Analyst', desc: 'Analyzed an AI-generated response critically' },
    { id: 'meeting_prepper', icon: 'VI', name: 'Meeting Prepper', desc: 'Generated a pre-meeting briefing' },
    { id: 'bookmarker', icon: 'VII', name: 'Bookmarker', desc: 'Saved your first conversation highlight' },
    { id: 'streak_3', icon: 'VIII', name: '3-Day Streak', desc: 'Learned with Mercurius 3 days in a row' },
    { id: 'streak_7', icon: 'IX', name: 'Weekly Scholar', desc: 'Kept a 7-day learning streak' },
    { id: 'deep_diver', icon: 'X', name: 'Deep Diver', desc: 'Sent 20 or more messages in your sessions' },
    { id: 'challenger', icon: 'XI', name: 'Challenger', desc: 'Started the weekly club challenge' },
    { id: 'quiz_master', icon: 'XII', name: 'Quiz Master', desc: 'Scored 3 or more on a comprehension quiz' },
    { id: 'curriculum_unit', icon: 'XIII', name: 'Curriculum Explorer', desc: 'Started a structured curriculum unit' }
  ];

  var REFLECTION_PROMPTS = [
    'Pause: What\'s something Mercurius \u2160 said that you\'d want to verify yourself?',
    'Pause: In your own words, what\'s the most important thing you\'ve discussed so far?',
    'Pause: Has Mercurius \u2160 said anything that felt too confident? What would you push back on?',
    'Pause: Who might be affected by the topic you\'re discussing who wasn\'t mentioned?',
    'Pause: What question do you still have that hasn\'t been answered yet?',
    'Pause: How would you explain what you\'ve learned to someone who hasn\'t taken this class?',
    'Pause: What assumption is Mercurius \u2160 making that might not apply to everyone?',
    'Pause: If Mercurius \u2160 is wrong about something, how would you find out?',
  ];

  var STARTER_TOPICS = [
    { emoji: '', label: 'How does AI actually work?' },
    { emoji: '', label: 'Is AI biased?' },
    { emoji: '', label: 'When should I NOT use AI?' },
    { emoji: '', label: 'How do I prompt AI well?' },
    { emoji: '', label: 'AI and education equity' },
    { emoji: '', label: 'Prep me for the next club meeting' },
    { emoji: '', label: 'AI and the real world' },
  ];

  var TRANSPARENCY_TEXT =
    'Mercurius \u2160 is powered by Claude, an AI made by Anthropic. ' +
    'It cannot browse the web, remember previous sessions, or learn from your conversations. ' +
    'All responses are AI-generated and may contain errors. ' +
    'This tool is designed to build critical thinking about AI \u2014 not to replace it.';

  // =========================================================================
  // 4b. localStorage helpers — achievements, curriculum, bookmarks, profile
  // =========================================================================
  function getAchievementsLocal() {
    try { return JSON.parse(localStorage.getItem('merc_achievements') || '[]'); } catch(e) { console.warn('[Mercurius]', e); return []; }
  }
  function awardAchievement(id) {
    var existing = getAchievementsLocal();
    if (existing.indexOf(id) !== -1) return false; // already have it
    existing.push(id);
    localStorage.setItem('merc_achievements', JSON.stringify(existing));
    return true; // newly earned
  }
  function checkAndAwardAchievement(id) {
    if (awardAchievement(id)) {
      var def = ACHIEVEMENTS_DEF.filter(function(a) { return a.id === id; })[0];
      if (def) showAchievementToast(def);
    }
  }
  function getCurriculumProgress() {
    try { return JSON.parse(localStorage.getItem('merc_curriculum') || '{}'); } catch(e) { console.warn('[Mercurius]', e); return {}; }
  }
  function setCurriculumUnit(unitId, status) {
    var progress = getCurriculumProgress();
    progress[unitId] = status;
    localStorage.setItem('merc_curriculum', JSON.stringify(progress));
  }
  function getBookmarksLocal() {
    try { return JSON.parse(localStorage.getItem('merc_bookmarks') || '[]'); } catch(e) { console.warn('[Mercurius]', e); return []; }
  }
  function addBookmarkLocal(text, role) {
    var bookmarks = getBookmarksLocal();
    var entry = { id: Date.now().toString(), text: text, role: role || 'assistant', savedAt: new Date().toISOString() };
    bookmarks.unshift(entry);
    if (bookmarks.length > 50) bookmarks = bookmarks.slice(0, 50);
    localStorage.setItem('merc_bookmarks', JSON.stringify(bookmarks));
    return entry;
  }
  function removeBookmarkLocal(id) {
    var bookmarks = getBookmarksLocal().filter(function(b) { return b.id !== id; });
    localStorage.setItem('merc_bookmarks', JSON.stringify(bookmarks));
  }
  function getDisplayNameLocal() {
    return localStorage.getItem('merc_display_name') || '';
  }
  function setDisplayNameLocal(name) {
    localStorage.setItem('merc_display_name', name || '');
  }

  function showToast(html, duration) {
    var existing = document.getElementById('merc-toast');
    if (existing && existing.parentNode) existing.parentNode.removeChild(existing);
    var toast = document.createElement('div');
    toast.id = 'merc-toast';
    toast.className = 'merc-achievement-toast';
    toast.innerHTML = html;
    var panel = document.getElementById('merc-panel');
    if (panel) panel.appendChild(toast);
    setTimeout(function() { toast.classList.add('merc-toast-visible'); }, 50);
    setTimeout(function() {
      toast.classList.remove('merc-toast-visible');
      setTimeout(function() { if (toast.parentNode) toast.parentNode.removeChild(toast); }, 400);
    }, duration || 2500);
  }

  function showAchievementToast(def) {
    showToast(
      '<span class="merc-toast-icon">' + def.icon + '</span>' +
      '<div class="merc-toast-body">' +
      '<div class="merc-toast-title">Achievement Unlocked</div>' +
      '<div class="merc-toast-name">' + escapeHtml(def.name) + '</div>' +
      '</div>',
      3500
    );
  }

  var onboardStep = 0;
  function showOnboarding() {
    var overlay = document.getElementById('merc-onboard');
    if (overlay) overlay.classList.add('merc-onboard-visible');
    updateOnboardStep(0);
  }
  function updateOnboardStep(step) {
    onboardStep = step;
    var steps = document.querySelectorAll('.merc-onboard-step');
    steps.forEach(function(s, i) {
      s.classList.toggle('merc-onboard-step-active', i === step);
    });
    var dots = document.querySelectorAll('.merc-onboard-dot');
    dots.forEach(function(d, i) { d.classList.toggle('active', i === step); });
    var nextBtn = document.getElementById('merc-onboard-next');
    if (nextBtn) nextBtn.textContent = step === 2 ? 'Start Exploring' : 'Next \u2192';
  }
  function completeOnboarding() {
    var nameInput = document.getElementById('merc-onboard-name');
    if (nameInput && nameInput.value.trim()) {
      var name = nameInput.value.trim().slice(0, 30);
      setDisplayNameLocal(name);
      updateDisplayNameInSidebar(name);
      fetch(PROFILE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: sessionId, displayName: name })
      }).catch(function(e) { console.warn('[Mercurius]', e); });
    }
    safeSetItem('merc_onboarded', '1');
    var overlay = document.getElementById('merc-onboard');
    if (overlay) overlay.classList.remove('merc-onboard-visible');
    checkAndAwardAchievement('first_chat');
  }
  function updateDisplayNameInSidebar(name) {
    var el = document.getElementById('merc-display-name');
    if (el) el.textContent = name ? name : 'Add your name';
    el && el.classList.toggle('merc-name-set', !!name);
  }

  // =========================================================================
  // 5. Build DOM
  // =========================================================================
  function buildWidget() {
    // Toggle button
    var toggle = document.createElement('button');
    toggle.id = 'merc-toggle';
    toggle.setAttribute('aria-label', 'Open Mercurius \u2160 AI tutor');
    toggle.innerHTML = '<span class="merc-monogram">M&#8544;</span><span class="merc-toggle-label">Ask Mercurius</span><span class="merc-toggle-dot"></span>';

    // Main panel — full screen
    var panel = document.createElement('div');
    panel.id = 'merc-panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Mercurius \u2160 AI literacy tutor');

    panel.innerHTML = [
      '<div class="merc-offline-banner" id="merc-offline-banner">You\'re offline — Mercurius needs internet to think. <button class="merc-offline-retry">Retry</button></div>',
      // ── Sidebar ──────────────────────────────────────────────
      '<div class="merc-sidebar">',
      '  <div class="merc-sidebar-brand">',
      '    <div class="merc-sidebar-avatar">M&#8544;</div>',
      '    <div class="merc-sidebar-brand-text">',
      '      <div class="merc-sidebar-brand-name">Mercurius &#8544;</div>',
      '      <div class="merc-sidebar-brand-sub">AI LITERACY TUTOR</div>',
      '    </div>',
      '  </div>',
      '  <div class="merc-sidebar-body">',

      '    <div class="merc-sidebar-section">',
      '      <div class="merc-sidebar-section-label">Mode</div>',
      '      <button class="merc-mode-btn active" id="merc-tab-socratic">',
      '        <span class="merc-mode-dot"></span> Socratic',
      '      </button>',
      '      <button class="merc-mode-btn" id="merc-tab-direct">',
      '        <span class="merc-mode-dot"></span> Direct',
      '        <span class="merc-mode-lock" id="merc-tab-lock-icon">Locked</span>',
      '      </button>',
      '      <button class="merc-mode-btn" id="merc-tab-debate">',
      '        <span class="merc-mode-dot"></span> Debate',
      '      </button>',
      '      <button class="merc-mode-btn" id="merc-tab-discussion">',
      '        <span class="merc-mode-dot"></span> Discussion',
      '      </button>',
      '    </div>',

      '    <div class="merc-sidebar-section">',
      '      <div class="merc-sidebar-section-label">Tools</div>',
      '      <button class="merc-tool-btn" id="merc-btn-quiz">Quiz</button>',
      '      <button class="merc-tool-btn" id="merc-btn-map">Concept Map</button>',
      '      <button class="merc-tool-btn" id="merc-btn-report">Report Card</button>',
      '      <button class="merc-tool-btn" id="merc-btn-lb">Leaderboard</button>',
      '      <button class="merc-tool-btn" id="merc-btn-summary">Summary</button>',
      '      <button class="merc-tool-btn" id="merc-btn-factcheck">Fact Check</button>',
      '      <button class="merc-tool-btn" id="merc-btn-analyze">Analyze Output</button>',
      '      <button class="merc-tool-btn" id="merc-btn-challenge">Challenge</button>',
      '      <button class="merc-tool-btn" id="merc-btn-curriculum">Curriculum</button>',
      '      <button class="merc-tool-btn" id="merc-btn-achievements">Achievements</button>',
      '      <button class="merc-tool-btn" id="merc-btn-bookmarks">Bookmarks</button>',
      '    </div>',

      '    <div class="merc-sidebar-section">',
      '      <div class="merc-sidebar-section-label">History</div>',
      '      <button class="merc-tool-btn merc-new-chat-btn" id="merc-btn-new-chat">+ New Chat</button>',
      '      <div class="merc-history-list" id="merc-history-list"></div>',
      '    </div>',

      '  </div>',
      '  <div class="merc-sidebar-footer">',
      '    <div class="merc-display-name-row" id="merc-display-name-row">',
      '      <span class="merc-display-name" id="merc-display-name">Add your name</span>',
      '      <button class="merc-name-edit-btn" id="merc-name-edit-btn" title="Edit name">Edit</button>',
      '    </div>',
      '    <div class="merc-streak-badge merc-hidden" id="merc-header-streak"><span id="merc-streak-val"></span> day streak</div>',
      '    <button class="merc-info-btn" id="merc-btn-info">About Mercurius \u2160</button>',
      '  </div>',
      '</div>',

      // ── Main ─────────────────────────────────────────────────
      '<div class="merc-main">',

      '  <div class="merc-chat-area">',
      '    <div class="merc-main-header" id="merc-main-header">',
      '      <div style="display:flex;align-items:center;gap:10px;">',
      '        <div class="merc-main-header-title">Here to help you think, not think for you</div>',
      '        <div class="merc-main-header-mode" id="merc-mode-label">Socratic</div>',
      '      </div>',
      '      <button class="merc-close-btn" id="merc-close-btn" aria-label="Close">&#10005;</button>',
      '    </div>',

      '    <div class="merc-messages" id="merc-messages">',
      '      <div class="merc-topic-tags" id="merc-topic-tags">',
      '        <div class="merc-topic-tags-label">Start with a topic</div>',
      buildTopicTagsHTML(),
      '      </div>',
      '    </div>',

      '    <div class="merc-input-area">',
      '      <button id="merc-voice-btn" class="merc-voice-btn" aria-label="Voice input" title="Speak your answer">MIC</button>',
      '      <textarea id="merc-textarea" class="merc-textarea" placeholder="Ask me anything about AI..." rows="1" aria-label="Message input"></textarea>',
      '      <button id="merc-send-btn" class="merc-send-btn" aria-label="Send message">',
      '        <svg viewBox="0 0 24 24"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>',
      '      </button>',
      '    </div>',
      '  </div>',

      // ── Right panel (shared by all tools) ────────────────────
      '  <div class="merc-right-panel" id="merc-right-panel">',
      '    <div class="merc-rp-header">',
      '      <span class="merc-rp-title" id="merc-rp-title">Panel</span>',
      '      <button class="merc-rp-close" id="merc-rp-close" aria-label="Close panel">&#10005;</button>',
      '    </div>',
      '    <div class="merc-rp-body" id="merc-rp-body">',
      '      <div class="merc-summary-panel merc-hidden" id="merc-summary-panel">',
      '        <h4>Conversation Summary</h4>',
      '        <div id="merc-summary-content" style="color:rgba(241,245,249,0.85);font-size:12.5px;line-height:1.6;"></div>',
      '      </div>',
      '    </div>',
      '  </div>',

      '</div>',

      // Tooltip (absolute positioned inside panel)
      '<div class="merc-tooltip merc-hidden" id="merc-tooltip">',
      '  <strong style="color:#C9922A;font-size:12px;">About Mercurius &#8544;</strong><br><br>',
      TRANSPARENCY_TEXT,
      '</div>',

      // Onboarding overlay
      '<div class="merc-onboard" id="merc-onboard">',
      '  <div class="merc-onboard-card">',
      '    <div class="merc-onboard-step merc-onboard-step-active" data-step="0">',
      '      <div class="merc-onboard-icon">M&#8544;</div>',
      '      <h2>Welcome to Mercurius &#8544;</h2>',
      '      <p>An AI literacy tutor built by Mayo AI Literacy Club. I\'m here to help you think critically about AI \u2014 not to think for you.</p>',
      '    </div>',
      '    <div class="merc-onboard-step" data-step="1">',
      '      <h2>Three Ways to Learn</h2>',
      '      <div class="merc-onboard-modes">',
      '        <div class="merc-onboard-mode"><strong>Socratic</strong> \u2014 I ask questions first to activate your thinking before sharing anything.</div>',
      '        <div class="merc-onboard-mode"><strong>Direct</strong> \u2014 Unlocked after you demonstrate critical thinking. More depth, more nuance.</div>',
      '        <div class="merc-onboard-mode"><strong>Debate</strong> \u2014 I take a position on AI ethics and argue against you. Anyone can use this.</div>',
      '      </div>',
      '    </div>',
      '    <div class="merc-onboard-step" data-step="2">',
      '      <h2>One Last Thing</h2>',
      '      <p>Add your name so we can personalize your experience. (Completely optional.)</p>',
      '      <input class="merc-onboard-name-input" id="merc-onboard-name" type="text" placeholder="Your first name or nickname" maxlength="30">',
      '    </div>',
      '    <div class="merc-onboard-footer">',
      '      <div class="merc-onboard-dots">',
      '        <span class="merc-onboard-dot active"></span>',
      '        <span class="merc-onboard-dot"></span>',
      '        <span class="merc-onboard-dot"></span>',
      '      </div>',
      '      <button class="merc-onboard-next" id="merc-onboard-next">Next \u2192</button>',
      '      <button class="merc-onboard-skip" id="merc-onboard-skip">Skip</button>',
      '    </div>',
      '  </div>',
      '</div>',

    ].join('');

    document.body.appendChild(toggle);
    document.body.appendChild(panel);
    attachEvents(toggle, panel);
  }

  function buildTopicTagsHTML() {
    return STARTER_TOPICS.map(function (t) {
      return (
        '<button class="merc-tag" data-topic="' +
        escapeAttr(t.label) +
        '">' +
        t.emoji +
        ' ' +
        escapeHtml(t.label) +
        '</button>'
      );
    }).join('');
  }

  function attachTopicTagListeners() {
    var tagsContainer = document.getElementById('merc-topic-tags');
    if (tagsContainer) {
      tagsContainer.addEventListener('click', function (e) {
        var btn = e.target.closest('.merc-tag');
        if (btn) {
          var topic = btn.getAttribute('data-topic');
          if (tagsContainer.parentNode) tagsContainer.parentNode.removeChild(tagsContainer);
          sendMessage(topic);
        }
      });
    }
  }

  function renderHistoryList() {
    var container = document.getElementById('merc-history-list');
    if (!container) return;
    var list = getConversationList();
    if (list.length === 0) {
      container.innerHTML = '<div class="merc-history-empty">No past conversations</div>';
      return;
    }
    var html = '';
    list.slice(0, 10).forEach(function(convo) {
      var d = new Date(convo.date);
      var dateStr = d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      var isActive = convo.id === currentConversationId ? ' merc-history-active' : '';
      html += '<button class="merc-history-item' + isActive + '" data-convo-id="' + escapeAttr(convo.id) + '">';
      html += '<span class="merc-history-title">' + escapeHtml(convo.title) + '</span>';
      html += '<span class="merc-history-meta">' + dateStr + ' \u00b7 ' + convo.messageCount + ' msgs</span>';
      html += '</button>';
    });
    container.innerHTML = html;
    container.querySelectorAll('.merc-history-item').forEach(function(item) {
      item.addEventListener('click', function() {
        var id = item.getAttribute('data-convo-id');
        var convos = getConversationList();
        for (var i = 0; i < convos.length; i++) {
          if (convos[i].id === id) { loadConversation(convos[i]); renderHistoryList(); break; }
        }
      });
    });
  }

  function showOfflineOverlay() {
    if (document.getElementById('merc-offline-overlay')) return;
    var overlay = document.createElement('div');
    overlay.id = 'merc-offline-overlay';
    overlay.innerHTML = '<div class="merc-offline-box">' +
      '<div class="merc-offline-icon">/ /</div>' +
      '<div class="merc-offline-title">You are offline</div>' +
      '<div class="merc-offline-desc">Mercurius needs internet to think. Check your connection and try again.</div>' +
      '<button class="merc-offline-retry" id="merc-offline-retry">Retry</button>' +
      '</div>';
    var panel = document.getElementById('merc-panel');
    if (panel) panel.appendChild(overlay);
    else document.body.appendChild(overlay);
    var retryBtn = document.getElementById('merc-offline-retry');
    if (retryBtn) retryBtn.addEventListener('click', function() { window.location.reload(); });
  }

  function hideOfflineOverlay() {
    var overlay = document.getElementById('merc-offline-overlay');
    if (overlay && overlay.parentNode) overlay.parentNode.removeChild(overlay);
  }

  // =========================================================================
  // 6. Right panel management
  // =========================================================================
  function openRightPanel(type) {
    var rp = document.getElementById('merc-right-panel');
    var title = document.getElementById('merc-rp-title');
    var body = document.getElementById('merc-rp-body');
    if (!rp || !body) return;

    // If same panel clicked again — close it
    if (currentRightPanel === type) {
      closeRightPanel();
      return;
    }

    currentRightPanel = type;
    rp.classList.add('merc-rp-open');

    // Clear active tool state
    document.querySelectorAll('.merc-tool-btn').forEach(function (b) {
      b.classList.remove('tool-active');
    });

    var btnIdMap = {
      quiz: 'merc-btn-quiz',
      map: 'merc-btn-map',
      report: 'merc-btn-report',
      leaderboard: 'merc-btn-lb',
      summary: 'merc-btn-summary',
      factcheck: 'merc-btn-factcheck',
      analyze: 'merc-btn-analyze',
      challenge: 'merc-btn-challenge',
      curriculum: 'merc-btn-curriculum',
      achievements: 'merc-btn-achievements',
      bookmarks: 'merc-btn-bookmarks'
    };
    var activeBtn = document.getElementById(btnIdMap[type]);
    if (activeBtn) activeBtn.classList.add('tool-active');

    // Set title
    var titles = {
      quiz: 'Comprehension Quiz',
      map: 'Concept Map',
      report: 'Report Card',
      leaderboard: 'Leaderboard',
      summary: 'Summary',
      factcheck: 'Fact Check',
      analyze: 'Analyze Output',
      challenge: 'Weekly Challenge',
      curriculum: 'Curriculum',
      achievements: 'Achievements',
      bookmarks: 'Bookmarks'
    };
    if (title) title.textContent = titles[type] || type;

    // Preserve summary panel in DOM — move it aside temporarily
    var summaryPanel = document.getElementById('merc-summary-panel');

    // Clear body content but keep summary panel
    body.innerHTML = '';
    // Re-create summary panel slot and re-append
    if (summaryPanel) {
      body.appendChild(summaryPanel);
    }

    if (type === 'summary') {
      if (summaryPanel) summaryPanel.classList.remove('merc-hidden');
      handleSummaryToggle();
    } else {
      if (summaryPanel) summaryPanel.classList.add('merc-hidden');
      if (type === 'quiz') {
        loadQuizInPanel(body);
      } else if (type === 'map') {
        loadMapInPanel(body);
      } else if (type === 'report') {
        loadReportInPanel(body);
      } else if (type === 'leaderboard') {
        loadLeaderboardInPanel(body);
      } else if (type === 'factcheck') {
        loadFactCheckPanel(body);
      } else if (type === 'analyze') {
        loadAnalyzePanel(body);
      } else if (type === 'challenge') {
        loadChallengePanel(body);
      } else if (type === 'curriculum') {
        loadCurriculumPanel(body);
      } else if (type === 'achievements') {
        loadAchievementsPanel(body);
      } else if (type === 'bookmarks') {
        loadBookmarksPanel(body);
      }
    }
  }

  function closeRightPanel() {
    var rp = document.getElementById('merc-right-panel');
    if (rp) rp.classList.remove('merc-rp-open');
    document.querySelectorAll('.merc-tool-btn').forEach(function (b) {
      b.classList.remove('tool-active');
    });
    currentRightPanel = null;
  }

  function removeLoadingFromPanel(body) {
    var el = body.querySelector('.merc-quiz-loading');
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  function loadPanelWithFetch(body, opts) {
    if (opts.minHistory && conversationHistory.length < opts.minHistory) {
      body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + (opts.emptyMsg || 'Have a longer conversation first.') + '</p>');
      return;
    }
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">' + (opts.loadingMsg || 'Loading...') + '</p>');
    var fetchOpts = { method: opts.method || 'POST', headers: { 'Content-Type': 'application/json' } };
    if (opts.body) fetchOpts.body = JSON.stringify(opts.body);
    fetch(opts.endpoint, fetchOpts)
      .then(function(r) { return r.json(); })
      .then(function(data) {
        removeLoadingFromPanel(body);
        if (data.error) {
          body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Error') + '</p>');
          return;
        }
        opts.render(data, body);
      })
      .catch(function() {
        removeLoadingFromPanel(body);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error — try again.</p>');
      });
  }

  function loadQuizInPanel(body) {
    loadPanelWithFetch(body, {
      minHistory: 4,
      emptyMsg: 'Have a longer conversation first \u2014 then I can quiz you on what we covered.',
      loadingMsg: 'Generating quiz\u2026',
      endpoint: QUIZ_ENDPOINT,
      body: { sessionId: sessionId },
      render: renderQuiz
    });
  }

  function loadMapInPanel(body) {
    loadPanelWithFetch(body, {
      minHistory: 4,
      emptyMsg: 'Have a longer conversation first.',
      loadingMsg: 'Building concept map\u2026',
      endpoint: CONCEPT_MAP_ENDPOINT,
      body: { sessionId: sessionId },
      render: renderConceptMap
    });
  }

  function loadReportInPanel(body) {
    loadPanelWithFetch(body, {
      minHistory: 4,
      emptyMsg: 'Have a longer conversation first.',
      loadingMsg: 'Generating report card\u2026',
      endpoint: REPORT_CARD_ENDPOINT,
      body: { sessionId: sessionId },
      render: renderReportCard
    });
  }

  function loadLeaderboardInPanel(body) {
    loadPanelWithFetch(body, {
      loadingMsg: 'Loading\u2026',
      endpoint: LEADERBOARD_ENDPOINT,
      method: 'GET',
      render: renderLeaderboard
    });
  }

  function loadFactCheckPanel(body) {
    body.insertAdjacentHTML('afterbegin',
      '<div class="merc-tool-panel">' +
      '<p class="merc-tool-instructions">Paste an AI claim below \u2014 about AI capabilities, hype, policy, or anything you\'ve read. Mercurius will break it down.</p>' +
      '<textarea class="merc-tool-textarea" id="merc-fc-input" placeholder="e.g. \'AI will replace all programmers by 2030\'" rows="4" maxlength="1000"></textarea>' +
      '<button class="merc-tool-submit-btn" id="merc-fc-submit">Fact Check This \u2192</button>' +
      '<div id="merc-fc-result"></div>' +
      '</div>'
    );
    var submitBtn = document.getElementById('merc-fc-submit');
    if (submitBtn) {
      submitBtn.addEventListener('click', function() {
        var input = document.getElementById('merc-fc-input');
        if (!input || !input.value.trim()) return;
        var claim = input.value.trim();
        var resultEl = document.getElementById('merc-fc-result');
        if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-loading">Analyzing claim\u2026</p>';
        submitBtn.disabled = true;
        fetch(FACTCHECK_ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionId: sessionId, claim: claim })
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          submitBtn.disabled = false;
          if (data.error) {
            if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Error') + '</p>';
            return;
          }
          checkAndAwardAchievement('fact_checker');
          renderFactCheckResult(data, resultEl);
        })
        .catch(function() {
          submitBtn.disabled = false;
          if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-empty">Connection error \u2014 try again.</p>';
        });
      });
    }
  }

  function renderFactCheckResult(data, container) {
    var verdictColors = { accurate: '#4ade80', misleading: '#fbbf24', false: '#f87171', nuanced: '#60a5fa', unverifiable: '#94a3b8' };
    var color = verdictColors[data.verdict] || '#94a3b8';
    var html = '<div class="merc-fc-result-card">';
    html += '<div class="merc-fc-verdict" style="color:' + color + ';">' + escapeHtml(data.verdictLabel || data.verdict || '') + '</div>';
    html += '<p class="merc-fc-summary">' + escapeHtml(data.summary || '') + '</p>';
    if (data.breakdown && data.breakdown.length) {
      html += '<div class="merc-fc-breakdown">';
      data.breakdown.forEach(function(b) {
        var icon = b.status === 'true' ? '\u2713' : b.status === 'false' ? '\u2717' : '\u223C';
        var bcolor = b.status === 'true' ? '#4ade80' : b.status === 'false' ? '#f87171' : '#fbbf24';
        html += '<div class="merc-fc-item"><span style="color:' + bcolor + '">' + icon + '</span> <strong>' + escapeHtml(b.claim || '') + '</strong> \u2014 ' + escapeHtml(b.explanation || '') + '</div>';
      });
      html += '</div>';
    }
    if (data.nuances) html += '<p class="merc-fc-nuances"><em>' + escapeHtml(data.nuances) + '</em></p>';
    if (data.literacyLesson) html += '<div class="merc-fc-lesson">' + escapeHtml(data.literacyLesson) + '</div>';
    html += '</div>';
    container.innerHTML = html;
  }

  function loadAnalyzePanel(body) {
    body.insertAdjacentHTML('afterbegin',
      '<div class="merc-tool-panel">' +
      '<p class="merc-tool-instructions">Paste any AI-generated response \u2014 from ChatGPT, Gemini, or anywhere else. Mercurius will critique it as an AI literacy exercise.</p>' +
      '<textarea class="merc-tool-textarea" id="merc-az-input" placeholder="Paste an AI response here\u2026" rows="5" maxlength="3000"></textarea>' +
      '<button class="merc-tool-submit-btn" id="merc-az-submit">Analyze This \u2192</button>' +
      '<div id="merc-az-result"></div>' +
      '</div>'
    );
    var submitBtn = document.getElementById('merc-az-submit');
    if (submitBtn) {
      submitBtn.addEventListener('click', function() {
        var input = document.getElementById('merc-az-input');
        if (!input || !input.value.trim()) return;
        var aiOutput = input.value.trim();
        var resultEl = document.getElementById('merc-az-result');
        if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-loading">Analyzing\u2026</p>';
        submitBtn.disabled = true;
        fetch(ANALYZE_ENDPOINT, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ sessionId: sessionId, aiOutput: aiOutput })
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          submitBtn.disabled = false;
          if (data.error) {
            if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Error') + '</p>';
            return;
          }
          checkAndAwardAchievement('analyst');
          renderAnalyzeResult(data, resultEl);
        })
        .catch(function() {
          submitBtn.disabled = false;
          if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-empty">Connection error.</p>';
        });
      });
    }
  }

  function renderAnalyzeResult(data, container) {
    var assessColors = { strong: '#4ade80', decent: '#fbbf24', problematic: '#f87171' };
    var color = assessColors[data.overallAssessment] || '#94a3b8';
    var html = '<div class="merc-fc-result-card">';
    html += '<div class="merc-fc-verdict" style="color:' + color + ';">' + escapeHtml(data.overallAssessment || '') + '</div>';
    html += '<p class="merc-fc-summary">' + escapeHtml(data.summary || '') + '</p>';
    if (data.issues && data.issues.length) {
      var typeIcons = { hallucination: '\u2022', overconfidence: '\u2022', bias: '\u2022', missing_context: '\u2022', vague: '\u2022', good: '\u2713' };
      html += '<div class="merc-fc-breakdown">';
      data.issues.forEach(function(issue) {
        var icon = typeIcons[issue.type] || '\u25CF';
        html += '<div class="merc-fc-item">' + icon + ' <strong>' + escapeHtml(issue.type || '') + '</strong>: ' + escapeHtml(issue.description || '');
        if (issue.quote) html += ' <em>\u201C' + escapeHtml(issue.quote) + '\u201D</em>';
        html += '</div>';
      });
      html += '</div>';
    }
    if (data.confidenceFlags) html += '<p class="merc-fc-nuances"><strong>Confidence flags:</strong> ' + escapeHtml(data.confidenceFlags) + '</p>';
    if (data.missingPerspectives) html += '<p class="merc-fc-nuances"><strong>Missing perspectives:</strong> ' + escapeHtml(data.missingPerspectives) + '</p>';
    if (data.literacyLesson) html += '<div class="merc-fc-lesson">' + escapeHtml(data.literacyLesson) + '</div>';
    html += '</div>';
    container.innerHTML = html;
  }

  function loadChallengePanel(body) {
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">Loading challenge\u2026</p>');
    fetch(CHALLENGE_ENDPOINT)
      .then(function(r) { return r.json(); })
      .then(function(data) {
        removeLoadingFromPanel(body);
        if (data.error) {
          body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'No challenge available yet.') + '</p>');
          return;
        }
        var html = '<div class="merc-challenge-card">';
        html += '<div class="merc-challenge-label">\u26A1 Weekly Challenge</div>';
        html += '<h3 class="merc-challenge-title">' + escapeHtml(data.title || '') + '</h3>';
        html += '<p class="merc-challenge-desc">' + escapeHtml(data.description || '') + '</p>';
        if (data.keyQuestions && data.keyQuestions.length) {
          html += '<div class="merc-challenge-questions"><div class="merc-challenge-q-label">Key questions:</div><ul>';
          data.keyQuestions.forEach(function(q) { html += '<li>' + escapeHtml(q) + '</li>'; });
          html += '</ul></div>';
        }
        html += '<button class="merc-tool-submit-btn merc-challenge-start" id="merc-challenge-start" data-starter="' + escapeAttr(data.starter || '') + '">Start This Challenge \u2192</button>';
        html += '</div>';
        body.insertAdjacentHTML('afterbegin', html);
        var startBtn = document.getElementById('merc-challenge-start');
        if (startBtn) {
          startBtn.addEventListener('click', function() {
            var starter = startBtn.getAttribute('data-starter');
            closeRightPanel();
            checkAndAwardAchievement('challenger');
            if (starter) sendMessage(starter, true);
          });
        }
        // Also add pre-briefing section
        var briefSection = document.createElement('div');
        briefSection.className = 'merc-briefing-section';
        briefSection.innerHTML = '<div class="merc-challenge-label" style="margin-top:20px;">Pre-Meeting Briefing</div>' +
          '<p style="font-size:11px;color:rgba(241,245,249,0.6);margin-bottom:10px;">Get a 3-point prep summary for the meeting.</p>' +
          '<button class="merc-tool-submit-btn" id="merc-briefing-btn" style="margin-top:0">Generate Briefing \u2192</button>' +
          '<div id="merc-briefing-result"></div>';
        body.appendChild(briefSection);
        var briefBtn = document.getElementById('merc-briefing-btn');
        if (briefBtn) {
          briefBtn.addEventListener('click', function() {
            var resultEl = document.getElementById('merc-briefing-result');
            if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-loading">Generating briefing\u2026</p>';
            briefBtn.disabled = true;
            fetch(PRE_BRIEFING_ENDPOINT + '?sessionId=' + encodeURIComponent(sessionId))
              .then(function(r) { return r.json(); })
              .then(function(bdata) {
                briefBtn.disabled = false;
                if (resultEl) {
                  if (bdata.error) {
                    resultEl.innerHTML = '<p class="merc-quiz-empty">Could not generate briefing.</p>';
                    return;
                  }
                  checkAndAwardAchievement('meeting_prepper');
                  var bhtml = '<div class="merc-briefing-card">';
                  bhtml += '<h4>' + escapeHtml(bdata.meetingTitle || '') + '</h4>';
                  if (bdata.date) bhtml += '<p class="merc-briefing-date">' + escapeHtml(bdata.date) + '</p>';
                  if (bdata.bullets) bdata.bullets.forEach(function(b) {
                    bhtml += '<div class="merc-briefing-bullet"><strong>' + escapeHtml(b.heading) + '</strong><p>' + escapeHtml(b.body) + '</p></div>';
                  });
                  if (bdata.keyQuestion) bhtml += '<div class="merc-briefing-key-q">' + escapeHtml(bdata.keyQuestion) + '</div>';
                  bhtml += '</div>';
                  resultEl.innerHTML = bhtml;
                }
              })
              .catch(function() {
                briefBtn.disabled = false;
                if (resultEl) resultEl.innerHTML = '<p class="merc-quiz-empty">Connection error.</p>';
              });
          });
        }
      })
      .catch(function() {
        removeLoadingFromPanel(body);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error.</p>');
      });
  }

  function getLessonProgress() {
    try { return JSON.parse(localStorage.getItem('merc_lessons') || '{}'); } catch(e) { console.warn('[Mercurius]', e); return {}; }
  }
  function setLessonComplete(lessonId) {
    var p = getLessonProgress();
    p[lessonId] = 'complete';
    safeSetItem('merc_lessons', JSON.stringify(p));
  }
  function countUnitLessonsDone(unit) {
    var p = getLessonProgress();
    var done = 0;
    (unit.lessons || []).forEach(function(l) { if (p[l.id] === 'complete') done++; });
    return done;
  }
  function isUnitComplete(unit) {
    return unit.lessons && countUnitLessonsDone(unit) === unit.lessons.length;
  }

  var curriculumExpandedUnit = null;

  function loadCurriculumPanel(body) {
    var progress = getCurriculumProgress();
    var totalLessons = 0;
    var completedLessons = 0;
    CURRICULUM_UNITS.forEach(function(u) {
      if (u.lessons) { totalLessons += u.lessons.length; completedLessons += countUnitLessonsDone(u); }
    });
    var html = '<div class="merc-curriculum-panel">';
    // Overall progress
    html += '<div class="merc-curriculum-progress">';
    html += '<div class="merc-curriculum-progress-text">' + completedLessons + ' / ' + totalLessons + ' lessons completed</div>';
    html += '<div class="merc-curriculum-progress-bar"><div class="merc-curriculum-progress-fill" style="width:' + Math.round((completedLessons / totalLessons) * 100) + '%"></div></div>';
    html += '</div>';
    html += '<p class="merc-tool-instructions">Five units, each with structured lessons. Expand a unit to see its lesson plan.</p>';
    CURRICULUM_UNITS.forEach(function(unit) {
      var lessonsDone = countUnitLessonsDone(unit);
      var total = unit.lessons ? unit.lessons.length : 0;
      var unitDone = lessonsDone === total;
      var isExpanded = curriculumExpandedUnit === unit.id;
      var unitStatus = unitDone ? 'complete' : lessonsDone > 0 ? 'in_progress' : 'not_started';
      html += '<div class="merc-unit-card merc-unit-' + unitStatus.replace('_', '-') + '">';
      html += '<div class="merc-unit-header" data-unit-id="' + escapeAttr(unit.id) + '">';
      html += '<div class="merc-unit-num">' + escapeHtml(unit.number) + '</div>';
      html += '<div class="merc-unit-body">';
      html += '<div class="merc-unit-title">' + escapeHtml(unit.title) + '</div>';
      html += '<div class="merc-unit-desc">' + escapeHtml(unit.description) + '</div>';
      html += '</div>';
      html += '<div class="merc-unit-status">' + lessonsDone + '/' + total + '</div>';
      html += '</div>';
      // Lessons list (expandable)
      html += '<div class="merc-lessons-list' + (isExpanded ? '' : ' merc-hidden') + '" data-unit-lessons="' + escapeAttr(unit.id) + '">';
      if (unit.lessons) {
        var lessonProg = getLessonProgress();
        unit.lessons.forEach(function(lesson, idx) {
          var lDone = lessonProg[lesson.id] === 'complete';
          var isNext = !lDone && (idx === 0 || lessonProg[unit.lessons[idx - 1].id] === 'complete');
          html += '<div class="merc-lesson-row' + (lDone ? ' merc-lesson-done' : '') + (isNext ? ' merc-lesson-next' : '') + '">';
          html += '<div class="merc-lesson-num">' + (idx + 1) + '</div>';
          html += '<div class="merc-lesson-info">';
          html += '<div class="merc-lesson-title">' + escapeHtml(lesson.title) + '</div>';
          html += '<div class="merc-lesson-obj">' + escapeHtml(lesson.objective) + '</div>';
          html += '</div>';
          if (lDone) {
            html += '<div class="merc-lesson-status merc-lesson-status-done">\u2713</div>';
          } else if (isNext) {
            html += '<button class="merc-lesson-start-btn" data-lesson-id="' + escapeAttr(lesson.id) + '" data-starter="' + escapeAttr(lesson.starter) + '" data-unit-id="' + escapeAttr(unit.id) + '">Start</button>';
          } else {
            html += '<div class="merc-lesson-status merc-lesson-status-locked">\u2014</div>';
          }
          html += '</div>';
        });
      }
      html += '</div>';
      html += '</div>';
    });
    html += '</div>';
    body.insertAdjacentHTML('afterbegin', html);
    // Expand/collapse unit
    body.querySelectorAll('.merc-unit-header').forEach(function(header) {
      header.addEventListener('click', function() {
        var unitId = header.getAttribute('data-unit-id');
        var lessonsList = body.querySelector('[data-unit-lessons="' + unitId + '"]');
        if (lessonsList) {
          var isHidden = lessonsList.classList.contains('merc-hidden');
          // Collapse all first
          body.querySelectorAll('.merc-lessons-list').forEach(function(ll) { ll.classList.add('merc-hidden'); });
          if (isHidden) {
            lessonsList.classList.remove('merc-hidden');
            curriculumExpandedUnit = unitId;
          } else {
            curriculumExpandedUnit = null;
          }
        }
      });
    });
    // Start lesson buttons
    body.querySelectorAll('.merc-lesson-start-btn').forEach(function(btn) {
      btn.addEventListener('click', function(e) {
        e.stopPropagation();
        var lessonId = btn.getAttribute('data-lesson-id');
        var starter = btn.getAttribute('data-starter');
        var unitId = btn.getAttribute('data-unit-id');
        setLessonComplete(lessonId);
        setCurriculumUnit(unitId, 'in_progress');
        var matchedUnit = null;
        for (var k = 0; k < CURRICULUM_UNITS.length; k++) {
          if (CURRICULUM_UNITS[k].id === unitId) { matchedUnit = CURRICULUM_UNITS[k]; break; }
        }
        if (matchedUnit && isUnitComplete(matchedUnit)) {
          setCurriculumUnit(unitId, 'complete');
        }
        closeRightPanel();
        checkAndAwardAchievement('curriculum_unit');
        if (starter) sendMessage(starter, true);
      });
    });
  }

  function loadAchievementsPanel(body) {
    var earned = getAchievementsLocal();
    var html = '<div class="merc-achievements-panel">';
    html += '<p style="font-size:11px;color:rgba(241,245,249,0.5);margin-bottom:14px;">' + earned.length + ' of ' + ACHIEVEMENTS_DEF.length + ' earned</p>';
    if (earned.length === 0) {
      html += '<p style="font-size:12px;color:rgba(241,245,249,0.4);margin-bottom:16px;font-style:italic;">Start chatting with Mercurius to earn your first achievement!</p>';
    }
    html += '<div class="merc-achievements-grid">';
    ACHIEVEMENTS_DEF.forEach(function(def) {
      var isEarned = earned.indexOf(def.id) !== -1;
      html += '<div class="merc-achievement-item' + (isEarned ? ' merc-achievement-earned' : ' merc-achievement-locked') + '" title="' + escapeAttr(def.desc) + '">';
      html += '<div class="merc-achievement-icon">' + (isEarned ? def.icon : '\u2014') + '</div>';
      html += '<div class="merc-achievement-name">' + escapeHtml(def.name) + '</div>';
      html += '</div>';
    });
    html += '</div></div>';
    body.insertAdjacentHTML('afterbegin', html);
  }

  function loadBookmarksPanel(body) {
    var bookmarks = getBookmarksLocal();
    if (bookmarks.length === 0) {
      body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">No bookmarks yet. Click Save on any message to save it here.</p>');
      return;
    }
    var html = '<div class="merc-bookmarks-panel">';
    bookmarks.forEach(function(bm) {
      var preview = bm.text.length > 120 ? bm.text.slice(0, 120) + '\u2026' : bm.text;
      html += '<div class="merc-bookmark-item" data-id="' + escapeAttr(bm.id) + '">';
      html += '<div class="merc-bookmark-text">' + escapeHtml(preview) + '</div>';
      html += '<div class="merc-bookmark-actions">';
      html += '<button class="merc-bookmark-copy" data-text="' + escapeAttr(bm.text) + '">Copy</button>';
      html += '<button class="merc-bookmark-delete" data-id="' + escapeAttr(bm.id) + '">Delete</button>';
      html += '</div></div>';
    });
    html += '</div>';
    body.insertAdjacentHTML('afterbegin', html);
    body.querySelectorAll('.merc-bookmark-copy').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var text = btn.getAttribute('data-text');
        if (navigator.clipboard) {
          navigator.clipboard.writeText(text).then(function() {
            btn.textContent = 'Copied!';
            setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
          }).catch(function(e) { console.warn('[Mercurius]', e); });
        }
      });
    });
    body.querySelectorAll('.merc-bookmark-delete').forEach(function(btn) {
      btn.addEventListener('click', function() {
        var id = btn.getAttribute('data-id');
        removeBookmarkLocal(id);
        var item = body.querySelector('.merc-bookmark-item[data-id="' + id + '"]');
        if (item && item.parentNode) item.parentNode.removeChild(item);
      });
    });
  }

  // =========================================================================
  // 7. Events
  // =========================================================================
  function attachEvents(toggle, panel) {
    // Toggle open/close
    toggle.addEventListener('click', function () {
      isOpen = !isOpen;
      if (isOpen) {
        panel.classList.add('merc-open');
        toggle.setAttribute('aria-expanded', 'true');
        var ta = document.getElementById('merc-textarea');
        if (ta) setTimeout(function () { ta.focus(); }, 280);
      } else {
        panel.classList.remove('merc-open');
        toggle.setAttribute('aria-expanded', 'false');
      }
    });

    // Main close button (X in header) — hide entirely in standalone PWA mode
    var closeBtn = document.getElementById('merc-close-btn');
    var isStandalonePWA = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
    if (closeBtn && isStandalonePWA) {
      closeBtn.style.display = 'none';
    } else if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        isOpen = false;
        panel.classList.remove('merc-open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    }

    // Topic tags
    attachTopicTagListeners();

    // New chat button
    var newChatBtn = document.getElementById('merc-btn-new-chat');
    if (newChatBtn) {
      newChatBtn.addEventListener('click', function() {
        startNewConversation();
        renderHistoryList();
      });
    }

    // Render saved conversation history in sidebar
    renderHistoryList();

    // Offline detection overlay
    window.addEventListener('offline', showOfflineOverlay);
    window.addEventListener('online', hideOfflineOverlay);
    if (!navigator.onLine) showOfflineOverlay();

    // Send button
    var sendBtn = document.getElementById('merc-send-btn');
    if (sendBtn) {
      sendBtn.addEventListener('click', function () {
        triggerSend();
      });
    }

    // Textarea — Enter to send, Shift+Enter for newline, auto-expand
    var textarea = document.getElementById('merc-textarea');
    if (textarea) {
      textarea.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' && !e.shiftKey) {
          e.preventDefault();
          triggerSend();
        }
      });
      textarea.addEventListener('input', function () {
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 140) + 'px';
      });
    }

    // Info tooltip toggle
    var infoBtn = document.getElementById('merc-btn-info');
    var tooltip = document.getElementById('merc-tooltip');
    if (infoBtn && tooltip) {
      infoBtn.addEventListener('click', function (e) {
        e.stopPropagation();
        tooltipVisible = !tooltipVisible;
        tooltip.classList.toggle('merc-hidden', !tooltipVisible);
      });
      document.addEventListener('click', function (e) {
        if (tooltipVisible && !tooltip.contains(e.target) && e.target !== infoBtn) {
          tooltipVisible = false;
          tooltip.classList.add('merc-hidden');
        }
      });
    }

    // Tool buttons → open right panel
    var quizBtn = document.getElementById('merc-btn-quiz');
    if (quizBtn) { quizBtn.addEventListener('click', function () { openRightPanel('quiz'); }); }

    var mapBtn = document.getElementById('merc-btn-map');
    if (mapBtn) { mapBtn.addEventListener('click', function () { openRightPanel('map'); }); }

    var reportBtn = document.getElementById('merc-btn-report');
    if (reportBtn) { reportBtn.addEventListener('click', function () { openRightPanel('report'); }); }

    var lbBtn = document.getElementById('merc-btn-lb');
    if (lbBtn) { lbBtn.addEventListener('click', function () { openRightPanel('leaderboard'); }); }

    var summaryBtn = document.getElementById('merc-btn-summary');
    if (summaryBtn) { summaryBtn.addEventListener('click', function () { openRightPanel('summary'); }); }

    // Right panel close button
    var rpClose = document.getElementById('merc-rp-close');
    if (rpClose) {
      rpClose.addEventListener('click', function () {
        closeRightPanel();
      });
    }

    // Voice input button
    var voiceBtn = document.getElementById('merc-voice-btn');
    if (voiceBtn) { voiceBtn.addEventListener('click', toggleVoiceInput); }

    // Mode tab clicks
    var tabSocratic = document.getElementById('merc-tab-socratic');
    var tabDirect   = document.getElementById('merc-tab-direct');
    if (tabSocratic) {
      tabSocratic.addEventListener('click', function () {
        if (currentMode !== 'socratic') handleModeSwitchTo('socratic');
      });
    }
    if (tabDirect) {
      tabDirect.addEventListener('click', function () {
        if (isUnlocked && currentMode !== 'direct') handleModeSwitchTo('direct');
      });
    }
    var tabDebate = document.getElementById('merc-tab-debate');
    if (tabDebate) {
      tabDebate.addEventListener('click', function () {
        if (currentMode !== 'debate') handleModeSwitchTo('debate');
      });
    }
    var tabDiscussion = document.getElementById('merc-tab-discussion');
    if (tabDiscussion) {
      tabDiscussion.addEventListener('click', function () {
        if (currentMode !== 'discussion') handleModeSwitchTo('discussion');
      });
    }

    // Initialise mode bar to match stored state
    updateModeBar();

    // New tool buttons
    var factcheckBtn = document.getElementById('merc-btn-factcheck');
    if (factcheckBtn) { factcheckBtn.addEventListener('click', function() { openRightPanel('factcheck'); }); }
    var analyzeBtn = document.getElementById('merc-btn-analyze');
    if (analyzeBtn) { analyzeBtn.addEventListener('click', function() { openRightPanel('analyze'); }); }
    var challengeBtn = document.getElementById('merc-btn-challenge');
    if (challengeBtn) { challengeBtn.addEventListener('click', function() { openRightPanel('challenge'); }); }
    var curriculumBtn = document.getElementById('merc-btn-curriculum');
    if (curriculumBtn) { curriculumBtn.addEventListener('click', function() { openRightPanel('curriculum'); }); }
    var achievementsBtn = document.getElementById('merc-btn-achievements');
    if (achievementsBtn) { achievementsBtn.addEventListener('click', function() { openRightPanel('achievements'); }); }
    var bookmarksBtn = document.getElementById('merc-btn-bookmarks');
    if (bookmarksBtn) { bookmarksBtn.addEventListener('click', function() { openRightPanel('bookmarks'); }); }

    // Display name edit button
    var nameEditBtn = document.getElementById('merc-name-edit-btn');
    if (nameEditBtn) {
      nameEditBtn.addEventListener('click', function() {
        var row = document.getElementById('merc-display-name-row');
        var existing = getDisplayNameLocal();
        var input = document.createElement('input');
        input.type = 'text';
        input.value = existing;
        input.maxLength = 30;
        input.className = 'merc-name-inline-input';
        input.placeholder = 'Your name';
        var saveBtn = document.createElement('button');
        saveBtn.className = 'merc-name-save-btn';
        saveBtn.textContent = '\u2713';
        if (row) {
          row.innerHTML = '';
          row.appendChild(input);
          row.appendChild(saveBtn);
          input.focus();
        }
        function saveName() {
          var name = input.value.trim().slice(0, 30);
          setDisplayNameLocal(name);
          fetch(PROFILE_ENDPOINT, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ sessionId: sessionId, displayName: name })
          }).catch(function(e) { console.warn('[Mercurius]', e); });
          if (row) {
            row.innerHTML = '<span class="merc-display-name' + (name ? ' merc-name-set' : '') + '" id="merc-display-name">' + escapeHtml(name || 'Add your name') + '</span><button class="merc-name-edit-btn" id="merc-name-edit-btn" title="Edit name">Edit</button>';
            var newEditBtn = document.getElementById('merc-name-edit-btn');
            if (newEditBtn) {
              newEditBtn.addEventListener('click', function() {
                var newRow = document.getElementById('merc-display-name-row');
                var curName = getDisplayNameLocal();
                var newInput = document.createElement('input');
                newInput.type = 'text';
                newInput.value = curName;
                newInput.maxLength = 30;
                newInput.className = 'merc-name-inline-input';
                newInput.placeholder = 'Your name';
                var newSaveBtn = document.createElement('button');
                newSaveBtn.className = 'merc-name-save-btn';
                newSaveBtn.textContent = '\u2713';
                if (newRow) {
                  newRow.innerHTML = '';
                  newRow.appendChild(newInput);
                  newRow.appendChild(newSaveBtn);
                  newInput.focus();
                }
                function saveNewName() {
                  var newName = newInput.value.trim().slice(0, 30);
                  setDisplayNameLocal(newName);
                  fetch(PROFILE_ENDPOINT, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ sessionId: sessionId, displayName: newName })
                  }).catch(function(e) { console.warn('[Mercurius]', e); });
                  if (newRow) {
                    newRow.innerHTML = '<span class="merc-display-name' + (newName ? ' merc-name-set' : '') + '" id="merc-display-name">' + escapeHtml(newName || 'Add your name') + '</span><button class="merc-name-edit-btn" id="merc-name-edit-btn" title="Edit name">Edit</button>';
                  }
                }
                newSaveBtn.addEventListener('click', saveNewName);
                newInput.addEventListener('keydown', function(e) { if (e.key === 'Enter') saveNewName(); });
              });
            }
          }
        }
        saveBtn.addEventListener('click', saveName);
        input.addEventListener('keydown', function(e) { if (e.key === 'Enter') saveName(); });
      });
    }

    // Onboarding next/skip buttons
    var onboardNext = document.getElementById('merc-onboard-next');
    if (onboardNext) {
      onboardNext.addEventListener('click', function() {
        if (onboardStep < 2) {
          updateOnboardStep(onboardStep + 1);
        } else {
          completeOnboarding();
        }
      });
    }
    var onboardSkip = document.getElementById('merc-onboard-skip');
    if (onboardSkip) {
      onboardSkip.addEventListener('click', function() {
        safeSetItem('merc_onboarded', '1');
        var overlay = document.getElementById('merc-onboard');
        if (overlay) overlay.classList.remove('merc-onboard-visible');
      });
    }
  }

  function triggerSend() {
    if (isLoading) return;
    var textarea = document.getElementById('merc-textarea');
    if (!textarea) return;
    var text = textarea.value.trim();
    if (!text) return;
    textarea.value = '';
    textarea.style.height = 'auto';
    sendMessage(text);
  }

  // =========================================================================
  // 8. Send message & get reply
  // =========================================================================
  function sendMessage(text, isHidden) {
    isHidden = isHidden || false;

    if (!isHidden) {
      userMessageCount++;
      appendUserMessage(text);
    }

    conversationHistory.push({ role: 'user', content: text });
    if (conversationHistory.length > 20) {
      conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
    }

    setLoading(true);
    var typingId = showTyping();
    var messages = conversationHistory.slice(-20);

    fetch(API_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' },
      body: JSON.stringify({ messages: messages, sessionId: sessionId }),
    })
    .then(function(res) {
      if (!res.ok) return res.json().then(function(e) { throw new Error(e.reply || 'Server error'); });
      var contentType = res.headers.get('content-type') || '';

      // Non-streaming fallback
      if (!contentType.includes('text/event-stream') || !res.body) {
        return res.json().then(function(data) {
          removeTyping(typingId);
          setLoading(false);
          handleChatResponse(data, isHidden);
        });
      }

      // SSE streaming
      removeTyping(typingId);
      var streamBubble = createStreamBubble();
      var reader = res.body.getReader();
      var decoder = new TextDecoder();
      var buffer = '';
      var fullText = '';
      var completeData = null;
      var lastStreamUpdate = 0;

      function pump() {
        return reader.read().then(function(result) {
          if (result.done) {
            setLoading(false);
            if (completeData) {
              finalizeStreamBubble(streamBubble, completeData.reply || fullText);
              completeData._streamRendered = true;
              handleChatResponse(completeData, isHidden);
            } else {
              finalizeStreamBubble(streamBubble, fullText);
            }
            return;
          }
          buffer += decoder.decode(result.value, { stream: true });
          var lines = buffer.split('\n');
          buffer = lines.pop() || '';
          for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            if (line.startsWith('data: ')) {
              var payload = line.slice(6);
              if (payload === '[DONE]') continue;
              try {
                var parsed = JSON.parse(payload);
                if (parsed.type === 'delta') {
                  fullText += parsed.text;
                  var now = Date.now();
                  if (now - lastStreamUpdate > 80) {
                    updateStreamBubble(streamBubble, fullText);
                    lastStreamUpdate = now;
                  }
                } else if (parsed.type === 'complete') {
                  completeData = parsed;
                } else if (parsed.type === 'error') {
                  setLoading(false);
                  removeStreamBubble(streamBubble);
                  appendBotMessage('Error: ' + (parsed.error || 'Unknown error'));
                  return;
                }
              } catch(e) { console.warn('[Mercurius]', e); }
            }
          }
          return pump();
        });
      }
      return pump();
    })
    .catch(function(err) {
      console.error('[Mercurius] fetch error:', err);
      removeTyping(typingId);
      setLoading(false);
      appendBotMessage('Connection error — try again in a moment.');
    });
  }

  function handleChatResponse(data, isHidden) {
    var reply = data.reply || 'No response received.';

    conversationHistory.push({ role: 'assistant', content: reply });
    if (conversationHistory.length > 20) {
      conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
    }

    // Handle unlock event
    if (data.justUnlocked) {
      isUnlocked = true;
      currentMode = 'socratic';
      localStorage.setItem('merc_unlocked', 'true');
      localStorage.setItem('merc_mode', 'socratic');
      updateModeBar();
      showUnlockCelebration();
      checkAndAwardAchievement('critical_thinker');
    }
    // Note: do NOT override currentMode from chat response — the user
    // may have switched modes while the request was in flight.

    // Track debate rounds
    if (currentMode === 'debate') {
      debateRound++;
      if (debateRound === 1) checkAndAwardAchievement('debate_starter');
    }
    // Award first_chat on first message
    if (userMessageCount === 1) checkAndAwardAchievement('first_chat');
    // Streak achievements
    if (data.streak >= 3) checkAndAwardAchievement('streak_3');
    if (data.streak >= 7) checkAndAwardAchievement('streak_7');
    // Deep diver
    if (userMessageCount >= 20) checkAndAwardAchievement('deep_diver');

    // Update streak badge
    if (data.streak && data.streak > 1) {
      var badge = document.getElementById('merc-header-streak');
      var val = document.getElementById('merc-streak-val');
      if (badge && val) {
        val.textContent = data.streak;
        badge.classList.remove('merc-hidden');
      }
    }

    // Session summary suggestion
    if (data.suggestSummary) {
      setTimeout(function() {
        appendSystemNotice('You\'ve been at this for a while. Want a summary of what you\'ve covered? Click Summary in the sidebar.');
      }, 1500);
    }

    // Always show bot reply (skip if streaming already rendered it)
    if (!data._streamRendered) {
      appendBotMessage(reply);
    }

    if (!isHidden) {
      if (summaryFetched && conversationHistory.length > summaryMessageCountAtFetch + 2) {
        summaryFetched = false;
      }
      if (userMessageCount > 0 && userMessageCount % 5 === 0) {
        appendReflectionCard();
      }
    }

    // Auto-save conversation to history
    saveCurrentConversation();
    renderHistoryList();

    scrollToBottom();
  }

  // sendHiddenUserVisibleBot — for Unpack/Flag action buttons
  // Sends a message without a user bubble but DOES show the bot reply.
  function sendHiddenUserVisibleBot(text) {
    conversationHistory.push({ role: 'user', content: text });
    if (conversationHistory.length > 20) {
      conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
    }

    setLoading(true);
    var typingId = showTyping();
    var messages = conversationHistory.slice(-20);

    fetch(API_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: messages, sessionId: sessionId }),
    })
      .then(function (res) {
        if (!res.ok) throw new Error('Server error: ' + res.status);
        return res.json();
      })
      .then(function (data) {
        removeTyping(typingId);
        setLoading(false);
        var reply = data.reply || 'No response received.';
        conversationHistory.push({ role: 'assistant', content: reply });
        if (conversationHistory.length > 20) {
          conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
        }
        appendBotMessage(reply);
        scrollToBottom();
      })
      .catch(function () {
        removeTyping(typingId);
        setLoading(false);
        appendBotMessage(
          "Connection issue \u2014 couldn't fetch the explanation. Try again in a moment."
        );
      });
  }

  // =========================================================================
  // 9. DOM helpers — append messages
  // =========================================================================
  function appendUserMessage(text) {
    var container = document.getElementById('merc-messages');
    if (!container) return;

    var wrapper = document.createElement('div');
    wrapper.className = 'merc-msg merc-msg-user';

    var bubble = document.createElement('div');
    bubble.className = 'merc-bubble';
    bubble.textContent = text;

    var ts = document.createElement('div');
    ts.className = 'merc-timestamp';
    ts.textContent = getTimestamp();

    wrapper.appendChild(bubble);
    wrapper.appendChild(ts);
    container.appendChild(wrapper);
    scrollToBottom();
  }

  function createStreamBubble() {
    var container = document.getElementById('merc-messages');
    if (!container) return null;
    var wrapper = document.createElement('div');
    wrapper.className = 'merc-msg merc-msg-bot merc-msg-streaming';
    var bubble = document.createElement('div');
    bubble.className = 'merc-bubble';
    bubble.innerHTML = '<span class="merc-stream-cursor"></span>';
    wrapper.appendChild(bubble);
    container.appendChild(wrapper);
    scrollToBottom();
    return wrapper;
  }

  function updateStreamBubble(wrapper, text) {
    if (!wrapper) return;
    var bubble = wrapper.querySelector('.merc-bubble');
    if (bubble) {
      bubble.innerHTML = renderMarkdown(text) + '<span class="merc-stream-cursor"></span>';
      scrollToBottom();
    }
  }

  function finalizeStreamBubble(wrapper, text) {
    if (!wrapper) return;
    wrapper.classList.remove('merc-msg-streaming');
    var bubble = wrapper.querySelector('.merc-bubble');
    if (bubble) {
      bubble.innerHTML = renderMarkdown(text);
      // Add action buttons
      var actions = buildActionButtons(text);
      if (actions) wrapper.insertBefore(actions, bubble);
    }
  }

  function removeStreamBubble(wrapper) {
    if (wrapper && wrapper.parentNode) wrapper.parentNode.removeChild(wrapper);
  }

  function appendBotMessage(text) {
    var container = document.getElementById('merc-messages');
    if (!container) return;

    var wrapper = document.createElement('div');
    wrapper.className = 'merc-msg merc-msg-bot';

    var bubble = document.createElement('div');
    bubble.className = 'merc-bubble';
    bubble.innerHTML = renderMarkdown(text);

    var ts = document.createElement('div');
    ts.className = 'merc-timestamp';
    ts.textContent = getTimestamp();

    var confidenceEl = buildConfidenceMeter(text);
    var actions = buildActionButtons(text);

    // Bookmark + share button row
    var msgActions = document.createElement('div');
    msgActions.className = 'merc-msg-actions';

    var bookmarkBtn = document.createElement('button');
    bookmarkBtn.className = 'merc-msg-action-btn merc-bookmark-btn';
    bookmarkBtn.title = 'Save this message';
    bookmarkBtn.innerHTML = 'Save';
    (function(capturedText) {
      bookmarkBtn.addEventListener('click', function() {
        addBookmarkLocal(capturedText, 'assistant');
        bookmarkBtn.innerHTML = '\u2713';
        bookmarkBtn.style.color = '#4ade80';
        checkAndAwardAchievement('bookmarker');
        setTimeout(function() {
          bookmarkBtn.innerHTML = 'Save';
          bookmarkBtn.style.color = '';
        }, 1500);
      });
    })(text);

    var shareBtn = document.createElement('button');
    shareBtn.className = 'merc-msg-action-btn merc-share-btn';
    shareBtn.title = 'Copy message';
    shareBtn.innerHTML = 'Copy';
    (function(capturedText) {
      shareBtn.addEventListener('click', function() {
        if (navigator.clipboard) {
          navigator.clipboard.writeText('--- Mercurius \u2160 ---\n\n' + capturedText + '\n\n--- mayoailiteracy.com/mercurius ---').then(function() {
            shareBtn.innerHTML = '\u2713 Copied';
            setTimeout(function() { shareBtn.innerHTML = 'Copy'; }, 1500);
          }).catch(function(e) { console.warn('[Mercurius]', e); });
        }
      });
    })(text);

    msgActions.appendChild(bookmarkBtn);
    msgActions.appendChild(shareBtn);
    wrapper.appendChild(msgActions);

    wrapper.appendChild(bubble);
    wrapper.appendChild(ts);
    wrapper.appendChild(confidenceEl);
    wrapper.appendChild(actions);
    container.appendChild(wrapper);
    scrollToBottom();
  }

  function appendReflectionCard() {
    var container = document.getElementById('merc-messages');
    if (!container) return;

    var prompt = REFLECTION_PROMPTS[reflectionIndex % REFLECTION_PROMPTS.length];
    reflectionIndex++;

    var wrapper = document.createElement('div');
    wrapper.className = 'merc-msg merc-msg-system';

    var bubble = document.createElement('div');
    bubble.className = 'merc-bubble';
    bubble.textContent = prompt;

    wrapper.appendChild(bubble);
    container.appendChild(wrapper);
    scrollToBottom();
  }

  function appendSummaryBotMessage(text) {
    var summaryContent = document.getElementById('merc-summary-content');
    if (!summaryContent) return;
    summaryContent.innerHTML = renderMarkdown(text);
  }

  function appendSystemNotice(text) {
    var container = document.getElementById('merc-messages');
    if (!container) return;
    // Remove starter chips if still visible
    var tags = document.getElementById('merc-topic-tags');
    if (tags && tags.parentNode) tags.parentNode.removeChild(tags);
    var el = document.createElement('div');
    el.className = 'merc-msg merc-msg-notice';
    el.textContent = text;
    container.appendChild(el);
    scrollToBottom();
  }

  // =========================================================================
  // 10. Typing indicator
  // =========================================================================
  var typingCounter = 0;

  function showTyping() {
    var container = document.getElementById('merc-messages');
    if (!container) return null;

    typingCounter++;
    var id = 'merc-typing-' + typingCounter;

    var wrapper = document.createElement('div');
    wrapper.className = 'merc-msg merc-msg-bot';
    wrapper.id = id;

    var indicator = document.createElement('div');
    indicator.className = 'merc-typing';
    indicator.innerHTML = '<span></span><span></span><span></span>';

    wrapper.appendChild(indicator);
    container.appendChild(wrapper);
    scrollToBottom();
    return id;
  }

  function removeTyping(id) {
    if (!id) return;
    var el = document.getElementById(id);
    if (el && el.parentNode) el.parentNode.removeChild(el);
  }

  // =========================================================================
  // 11. Minimal Markdown renderer (no external deps)
  // =========================================================================
  function renderMarkdown(text) {
    if (!text) return '';

    var escaped = escapeHtml(text);

    escaped = escaped.replace(/^##\s+(.+)$/gm, '<h3>$1</h3>');
    escaped = escaped.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');

    escaped = escaped.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    escaped = escaped.replace(/__(.+?)__/g, '<strong>$1</strong>');

    escaped = escaped.replace(/(?<![*_])\*(?!\s)(.+?)(?<!\s)\*(?![*_])/g, '<em>$1</em>');
    escaped = escaped.replace(/(?<!_)_(?!\s)(.+?)(?<!\s)_(?!_)/g, '<em>$1</em>');

    escaped = escaped.replace(/`(.+?)`/g, '<code>$1</code>');

    escaped = escaped.replace(/\[SOURCE:\s*([^\]]+)\]/g, '<span class="merc-source">$1</span>');

    escaped = escaped.replace(/^[-*]\s+(.+)$/gm, '<li>$1</li>');
    escaped = escaped.replace(/(<li>.*<\/li>(\n|$))+/g, function (m) {
      return '<ul>' + m.replace(/\n$/, '') + '</ul>';
    });

    escaped = escaped.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');
    escaped = escaped.replace(/(<li>.*<\/li>(\n|$))+/g, function (m) {
      if (m.indexOf('<ul>') !== -1 || m.indexOf('<ol>') !== -1) return m;
      return '<ol>' + m.replace(/\n$/, '') + '</ol>';
    });

    var parts = escaped.split(/\n\n+/);
    escaped = parts
      .map(function (p) {
        p = p.trim();
        if (!p) return '';
        if (/^<(h[2-6]|ul|ol|li|blockquote)/.test(p)) return p;
        return '<p>' + p.replace(/\n/g, '<br>') + '</p>';
      })
      .filter(Boolean)
      .join('');

    return escaped;
  }

  // =========================================================================
  // 12. Confidence meter
  // =========================================================================
  function parseConfidence(text) {
    if (!text) return null;

    var lower = text.toLowerCase();

    var pctMatch = text.match(/\b(\d{1,3})%/);
    if (pctMatch) {
      var pct = parseInt(pctMatch[1], 10);
      if (pct >= 0 && pct <= 100) return pct;
    }

    if (/50\s*\/\s*50/.test(lower)) return 50;

    if (/\b(quite confident|very confident|highly confident|very sure|pretty confident)\b/.test(lower)) return 82;
    if (/\bconfident\b/.test(lower)) return 70;
    if (/\b(uncertain|not sure|murky|murkier|unclear|not certain|a bit unsure)\b/.test(lower)) return 35;
    if (/\b(i actually don'?t know|i don'?t know|no idea|not sure at all|genuinely don'?t know)\b/.test(lower)) return 15;
    if (/\b(might|may|possibly|perhaps|could be|probably)\b/.test(lower)) return 55;
    if (/\b(likely|generally|typically|usually)\b/.test(lower)) return 68;

    return null;
  }

  function buildConfidenceMeter(text) {
    var confidence = parseConfidence(text);
    var el = document.createElement('div');
    el.className = 'merc-confidence';

    if (confidence !== null) {
      confidence = Math.max(0, Math.min(100, confidence));
    }

    if (confidence === null) {
      el.innerHTML = '<div class="merc-confidence-unverified">Confidence: unverified</div>';
    } else {
      var colorClass =
        confidence >= 70 ? 'merc-conf-green' :
        confidence >= 45 ? 'merc-conf-yellow' :
        'merc-conf-red';

      el.innerHTML =
        '<div class="merc-confidence-label">Confidence: ' + confidence + '%</div>' +
        '<div class="merc-confidence-bar-track">' +
        '  <div class="merc-confidence-bar-fill ' + colorClass + '" style="width:' + confidence + '%"></div>' +
        '</div>';
    }
    return el;
  }

  // =========================================================================
  // 13. Action buttons — Unpack & Flag
  // =========================================================================
  function buildActionButtons(originalText) {
    var el = document.createElement('div');
    el.className = 'merc-actions';

    var unpackBtn = document.createElement('button');
    unpackBtn.className = 'merc-action-btn';
    unpackBtn.innerHTML = 'Unpack this';
    unpackBtn.title = 'Ask Mercurius to explain its reasoning';

    var flagBtn = document.createElement('button');
    flagBtn.className = 'merc-action-btn';
    flagBtn.innerHTML = 'Flag bias';
    flagBtn.title = 'Flag potential bias or missing perspectives';

    var hasQuestion = originalText.indexOf('?') !== -1;
    var whyBtn = null;
    if (hasQuestion) {
      whyBtn = document.createElement('button');
      whyBtn.className = 'merc-action-btn merc-action-btn-why';
      whyBtn.innerHTML = 'Why this question?';
      whyBtn.title = 'Understand the Socratic reasoning behind this question';
    }

    function disableAll() {
      unpackBtn.disabled = true;
      flagBtn.disabled = true;
      if (whyBtn) whyBtn.disabled = true;
    }

    unpackBtn.addEventListener('click', function () {
      disableAll();
      sendHiddenUserVisibleBot(
        'Please explain your reasoning for your last response \u2014 what assumptions did you make, ' +
        'how did you arrive at that answer, and what might you be getting wrong?'
      );
    });

    flagBtn.addEventListener('click', function () {
      disableAll();
      sendHiddenUserVisibleBot(
        'Flag this response for potential bias \u2014 what perspectives or groups might this answer overlook? ' +
        'Be specific about whose voices or experiences are missing.'
      );
    });

    if (whyBtn) {
      whyBtn.addEventListener('click', function () {
        disableAll();
        sendHiddenUserVisibleBot(
          'You just asked me a Socratic question. Explain your reasoning: ' +
          'what concept were you trying to get me to discover, why did you choose that question specifically, ' +
          'and what answer were you hoping to guide me toward?'
        );
      });
    }

    el.appendChild(unpackBtn);
    el.appendChild(flagBtn);
    if (whyBtn) el.appendChild(whyBtn);
    return el;
  }

  // =========================================================================
  // 14. Summary panel
  // =========================================================================
  function handleSummaryToggle() {
    // Summary is displayed in the right panel — just fetch/render into it
    var summaryContent = document.getElementById('merc-summary-content');

    var hasNewMessages =
      !summaryFetched ||
      conversationHistory.length > summaryMessageCountAtFetch + 2;

    if (!hasNewMessages && summaryFetched) {
      // Already have fresh content — nothing to do, just show
      return;
    }

    if (conversationHistory.length < 2) {
      if (summaryContent) {
        summaryContent.innerHTML =
          '<em style="color: rgba(148,163,184,0.7)">Start chatting first \u2014 I\'ll summarize once we\'ve talked a bit.</em>';
      }
      return;
    }

    if (summaryContent) {
      summaryContent.innerHTML =
        '<em style="color: rgba(148,163,184,0.5)">Generating summary...</em>';
    }

    var summaryPrompt =
      'Please provide a brief summary of our conversation so far in this format:\n\n' +
      '**Key ideas covered**\n[2-3 bullet points]\n\n' +
      '**Questions worth thinking more about**\n[1-2 bullet points]\n\n' +
      '**One thing to verify yourself**\n[1 specific suggestion]\n\n' +
      'Keep it concise \u2014 this is a learning summary for the student.';

    var messages = conversationHistory.slice(-20).concat([
      { role: 'user', content: summaryPrompt },
    ]);

    fetch(API_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: messages, sessionId: sessionId }),
    })
      .then(function (res) {
        if (!res.ok) throw new Error('Server error: ' + res.status);
        return res.json();
      })
      .then(function (data) {
        var reply = data.reply || 'Could not generate summary.';
        appendSummaryBotMessage(reply);
        summaryFetched = true;
        summaryMessageCountAtFetch = conversationHistory.length;
      })
      .catch(function () {
        if (summaryContent) {
          summaryContent.innerHTML =
            '<em style="color: rgba(239,68,68,0.8)">Could not fetch summary \u2014 try again.</em>';
        }
      });
  }

  // =========================================================================
  // 15. Loading state
  // =========================================================================
  function setLoading(loading) {
    isLoading = loading;
    var sendBtn = document.getElementById('merc-send-btn');
    var textarea = document.getElementById('merc-textarea');
    if (sendBtn) sendBtn.disabled = loading;
    if (textarea) textarea.disabled = loading;
  }

  // =========================================================================
  // 16. Utilities
  // =========================================================================
  function scrollToBottom() {
    var container = document.getElementById('merc-messages');
    if (container) {
      requestAnimationFrame(function () {
        container.scrollTop = container.scrollHeight;
      });
    }
  }

  function getTimestamp() {
    var now = new Date();
    var h = now.getHours().toString().padStart(2, '0');
    var m = now.getMinutes().toString().padStart(2, '0');
    return h + ':' + m;
  }

  function escapeHtml(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function escapeAttr(str) {
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  // =========================================================================
  // 17. Mode bar helpers
  // =========================================================================
  function updateModeBar() {
    var btnSocratic   = document.getElementById('merc-tab-socratic');
    var btnDirect     = document.getElementById('merc-tab-direct');
    var btnDebate     = document.getElementById('merc-tab-debate');
    var btnDiscussion = document.getElementById('merc-tab-discussion');
    var lockIcon      = document.getElementById('merc-tab-lock-icon');
    var modeLabel     = document.getElementById('merc-mode-label');

    if (!btnSocratic || !btnDirect) return;

    // Unlock state
    if (isUnlocked) {
      btnDirect.disabled = false;
      if (lockIcon) lockIcon.textContent = '';
    } else {
      btnDirect.disabled = true;
      if (lockIcon) lockIcon.innerHTML = 'Locked';
    }

    // Active states
    [btnSocratic, btnDirect, btnDebate, btnDiscussion].forEach(function (b) {
      if (b) b.classList.remove('active');
    });

    var activeBtn =
      currentMode === 'direct' ? btnDirect :
      currentMode === 'debate' ? btnDebate :
      currentMode === 'discussion' ? btnDiscussion :
      btnSocratic;
    if (activeBtn) activeBtn.classList.add('active');

    // Mode label in header
    var modeNames = { socratic: 'Socratic', direct: 'Direct', debate: 'Debate', discussion: 'Discussion' };
    if (modeLabel) modeLabel.textContent = modeNames[currentMode] || 'Socratic';
  }

  function showUnlockCelebration() {
    var header = document.getElementById('merc-main-header');
    if (header) {
      header.classList.add('merc-unlock-flash');
      setTimeout(function () { header.classList.remove('merc-unlock-flash'); }, 1800);
    }
  }

  function showModeToast(label) {
    showToast(
      '<div class="merc-toast-body"><div class="merc-toast-name">Mode: ' + escapeHtml(label) + '</div></div>',
      2000
    );
  }

  function handleModeSwitchTo(newMode) {
    if (newMode === 'debate') debateRound = 0;
    if (newMode === 'direct' && !isUnlocked) return;

    var specialModes = ['debate', 'discussion'];
    var leavingSpecial = (specialModes.indexOf(currentMode) !== -1 && specialModes.indexOf(newMode) === -1);
    var enteringDebate = (currentMode !== 'debate' && newMode === 'debate');
    var enteringDiscussion = (currentMode !== 'discussion' && newMode === 'discussion');

    // Update state
    currentMode = newMode;
    safeSetItem('merc_mode', currentMode);
    updateModeBar();

    var container = document.getElementById('merc-messages');
    if (!container) return;

    if (enteringDebate) {
      // Clear chat and show debate-specific UI
      container.innerHTML = '';
      var debateIntro = document.createElement('div');
      debateIntro.className = 'merc-msg merc-msg-notice';
      debateIntro.innerHTML = '<strong>Debate Mode</strong> — Mercurius will take a position and coach you through a structured argument. Your reasoning skills will be graded.';
      container.appendChild(debateIntro);

      setTimeout(function () {
        sendMessage('I want to debate. Present me with 3 topic options to choose from, then we\'ll begin.', true);
      }, 400);

    } else if (enteringDiscussion) {
      // Clear chat and show discussion-specific UI
      container.innerHTML = '';
      var discussIntro = document.createElement('div');
      discussIntro.className = 'merc-msg merc-msg-notice';
      discussIntro.innerHTML = '<strong>Discussion Mode</strong> — Mercurius will pose a hard AI question and score the quality of your reasoning on 5 dimensions. Think carefully before you answer.';
      container.appendChild(discussIntro);

      setTimeout(function () {
        sendMessage('Start a discussion. Pose a provocative AI question and I\'ll give you my reasoning.', true);
      }, 400);

    } else if (leavingSpecial) {
      // Clear special mode messages and restore normal chat
      container.innerHTML = '';
      var notice = document.createElement('div');
      notice.className = 'merc-msg merc-msg-notice';
      notice.textContent = newMode === 'direct'
        ? 'Switched to Direct Mode — Mercurius will now lead with substantive explanations.'
        : 'Switched to Socratic Mode — Mercurius will guide your thinking with questions.';
      container.appendChild(notice);

      var tags = document.createElement('div');
      tags.className = 'merc-topic-tags';
      tags.id = 'merc-topic-tags';
      tags.innerHTML = '<div class="merc-topic-tags-label">Start with a topic</div>' + buildTopicTagsHTML();
      container.appendChild(tags);
      attachTopicTagListeners();

    } else {
      // Normal mode switch (socratic <-> direct)
      var modeNotices = {
        direct: 'Switched to Direct Mode \u2014 Mercurius will now lead with substantive explanations.',
        socratic: 'Switched to Socratic Mode \u2014 Mercurius will guide your thinking with questions.'
      };
      appendSystemNotice(modeNotices[newMode] || 'Mode switched.');
    }

    showModeToast({ socratic: 'Socratic', direct: 'Direct', debate: 'Debate', discussion: 'Discussion' }[newMode] || newMode);

    // Tell server
    fetch(MODE_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId, mode: newMode, clientUnlocked: isUnlocked }),
    }).catch(function (e) { console.warn('[Mercurius]', e); });
  }

  // =========================================================================
  // 18. Render functions (accept container param for right panel)
  // =========================================================================
  function renderQuiz(quiz, container) {
    var questions = quiz.questions || [];
    var html = '<div style="margin-bottom:8px;color:#C9922A;font-family:\'Josefin Sans\',sans-serif;font-size:12px;font-weight:700;">' +
      escapeHtml(quiz.title || 'Comprehension Check') + '</div>';
    html += '<form id="merc-quiz-form">';

    questions.forEach(function (q, i) {
      html += '<div class="merc-quiz-q" data-index="' + i + '">';
      html += '<p class="merc-quiz-qtext"><strong>' + escapeHtml((i + 1) + '. ') + '</strong>' + escapeHtml(q.q) + '</p>';
      html += '<div class="merc-quiz-options">';
      (q.options || []).forEach(function (opt) {
        var letter = opt.charAt(0);
        html += '<label class="merc-quiz-option">' +
          '<input type="radio" name="q' + i + '" value="' + escapeAttr(letter) + '">' +
          '<span>' + escapeHtml(opt) + '</span>' +
          '</label>';
      });
      html += '</div>';
      html += '<div class="merc-quiz-explanation merc-hidden" id="merc-quiz-exp-' + i + '">' + escapeHtml(q.explanation || '') + '</div>';
      html += '</div>';
    });

    html += '</form>';
    html += '<button class="merc-quiz-submit" id="merc-quiz-submit">Check Answers</button>';
    html += '<div class="merc-quiz-result merc-hidden" id="merc-quiz-result"></div>';

    container.insertAdjacentHTML('afterbegin', html);

    var submitBtn = document.getElementById('merc-quiz-submit');
    if (submitBtn) {
      submitBtn.addEventListener('click', function () {
        var form = document.getElementById('merc-quiz-form');
        if (!form) return;
        var correct = 0;
        questions.forEach(function (q, i) {
          var selected = form.querySelector('input[name="q' + i + '"]:checked');
          var expEl = document.getElementById('merc-quiz-exp-' + i);
          var qEl = form.querySelector('.merc-quiz-q[data-index="' + i + '"]');
          if (selected) {
            var isRight = selected.value === q.answer;
            if (isRight) correct++;
            if (qEl) qEl.classList.add(isRight ? 'merc-quiz-correct' : 'merc-quiz-wrong');
            if (expEl) expEl.classList.remove('merc-hidden');
          }
        });

        submitBtn.style.display = 'none';
        var resultEl = document.getElementById('merc-quiz-result');
        if (resultEl) {
          var pct = Math.round((correct / questions.length) * 100);
          var msg = pct === 100 ? 'Perfect score!' : pct >= 75 ? 'Great work!' : pct >= 50 ? 'Good effort.' : 'Keep exploring \u2014 revisit the topics above.';
          resultEl.innerHTML = '<span class="merc-quiz-score">' + correct + ' / ' + questions.length + '</span> ' + msg;
          resultEl.classList.remove('merc-hidden');
          if (correct >= 3) checkAndAwardAchievement('quiz_master');
          // Add retry button
          var retryBtn = document.createElement('button');
          retryBtn.className = 'merc-quiz-submit';
          retryBtn.textContent = 'Try Another Quiz';
          retryBtn.style.marginTop = '10px';
          retryBtn.addEventListener('click', function() {
            var rpBody = document.querySelector('.merc-rp-body');
            if (rpBody) { rpBody.innerHTML = ''; loadQuizInPanel(rpBody); }
          });
          resultEl.parentNode.insertBefore(retryBtn, resultEl.nextSibling);
        }
      });
    }
  }

  function renderConceptMap(data, container) {
    var W = 380, H = 300;
    var nodes = data.nodes || [];
    var edges = data.edges || [];

    var cx = W / 2, cy = H / 2, r = 110;
    var positions = { central: { x: cx, y: cy } };
    nodes.forEach(function (n, i) {
      var angle = (2 * Math.PI * i / nodes.length) - Math.PI / 2;
      positions[n.id] = { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
    });

    var colorMap = { core: '#C9922A', related: '#4ade80', example: '#60a5fa' };

    var svg = '<svg width="' + W + '" height="' + H + '" xmlns="http://www.w3.org/2000/svg">';

    edges.forEach(function (e) {
      var from = e.from === 'central' ? positions.central : positions[e.from];
      var to = e.to === 'central' ? positions.central : positions[e.to];
      if (!from || !to) return;
      var mx = (from.x + to.x) / 2, my = (from.y + to.y) / 2;
      svg += '<line x1="' + from.x + '" y1="' + from.y + '" x2="' + to.x + '" y2="' + to.y + '" stroke="rgba(201,146,42,0.3)" stroke-width="1.5"/>';
      if (e.label) svg += '<text x="' + mx + '" y="' + my + '" fill="rgba(241,245,249,0.4)" font-size="7" text-anchor="middle" dy="-3">' + escapeHtml(e.label) + '</text>';
    });

    svg += '<circle cx="' + cx + '" cy="' + cy + '" r="28" fill="#C9922A" opacity="0.9"/>';
    var centralWords = (data.central || '').split(' ');
    centralWords.forEach(function (w, i) {
      svg += '<text x="' + cx + '" y="' + (cy - (centralWords.length - 1) * 6 + i * 13) + '" fill="#122e1e" font-size="9" font-weight="700" text-anchor="middle">' + escapeHtml(w) + '</text>';
    });

    nodes.forEach(function (n) {
      var p = positions[n.id];
      if (!p) return;
      var fill = colorMap[n.group] || '#94a3b8';
      svg += '<circle cx="' + p.x + '" cy="' + p.y + '" r="20" fill="' + fill + '" opacity="0.8"/>';
      var words = (n.label || '').split(' ');
      words.slice(0, 2).forEach(function (w, i) {
        svg += '<text x="' + p.x + '" y="' + (p.y - (Math.min(words.length, 2) - 1) * 5 + i * 11) + '" fill="#122e1e" font-size="8" font-weight="600" text-anchor="middle">' + escapeHtml(w) + '</text>';
      });
    });

    svg += '</svg>';

    var legend = '<div class="merc-map-legend">' +
      '<span style="color:#C9922A">\u2022 Core</span>' +
      '<span style="color:#4ade80">\u2022 Related</span>' +
      '<span style="color:#60a5fa">\u2022 Example</span>' +
      '</div>';

    container.insertAdjacentHTML('afterbegin', '<div class="merc-map-svg">' + svg + '</div>' + legend);

    // Make concept map nodes clickable — click to explore a topic
    setTimeout(function() {
      var svgEl = container.querySelector('svg');
      if (!svgEl) return;
      nodes.forEach(function(n) {
        var p = positions[n.id];
        if (!p) return;
        // Create invisible clickable overlay circle
        var clickCircle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        clickCircle.setAttribute('cx', p.x);
        clickCircle.setAttribute('cy', p.y);
        clickCircle.setAttribute('r', '22');
        clickCircle.setAttribute('fill', 'transparent');
        clickCircle.setAttribute('style', 'cursor:pointer');
        clickCircle.setAttribute('title', n.label);
        clickCircle.addEventListener('click', function() {
          closeRightPanel();
          sendMessage('Can we explore "' + n.label + '" more? Tell me about this concept and how it connects to what we\'ve been discussing.', true);
        });
        svgEl.appendChild(clickCircle);
      });
    }, 50);
  }

  function renderReportCard(data, container) {
    var gradeColor = (data.overallGrade || '').startsWith('A') ? '#4ade80' :
      (data.overallGrade || '').startsWith('B') ? '#C9922A' : '#f87171';
    var html = '<div class="merc-report-grade" style="color:' + gradeColor + '">' + escapeHtml(data.overallGrade || 'B') + '</div>';
    html += '<p class="merc-report-summary">' + escapeHtml(data.summary || '') + '</p>';
    html += '<div class="merc-report-bars">';
    html += '<div class="merc-report-bar-row"><span>Critical Thinking</span><div class="merc-report-bar"><div style="width:' + (data.criticalThinkingScore || 0) + '%"></div></div><span>' + (data.criticalThinkingScore || 0) + '</span></div>';
    html += '<div class="merc-report-bar-row"><span>Curiosity</span><div class="merc-report-bar"><div style="width:' + (data.curiosityScore || 0) + '%"></div></div><span>' + (data.curiosityScore || 0) + '</span></div>';
    html += '</div>';
    if (data.strengths && data.strengths.length) {
      html += '<div class="merc-report-section"><div class="merc-report-section-title" style="color:#4ade80">Strengths</div><ul>';
      data.strengths.forEach(function (s) { html += '<li>' + escapeHtml(s) + '</li>'; });
      html += '</ul></div>';
    }
    if (data.areasToRevisit && data.areasToRevisit.length) {
      html += '<div class="merc-report-section"><div class="merc-report-section-title" style="color:#C9922A">Revisit</div><ul>';
      data.areasToRevisit.forEach(function (s) { html += '<li>' + escapeHtml(s) + '</li>'; });
      html += '</ul></div>';
    }
    if (data.nextSessionSuggestion) {
      html += '<div class="merc-report-next">Next: ' + escapeHtml(data.nextSessionSuggestion) + '</div>';
    }
    container.insertAdjacentHTML('afterbegin', html);
  }

  function renderLeaderboard(rows, container) {
    if (!rows || rows.length === 0) {
      container.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">No data yet \u2014 start chatting!</p>');
      return;
    }
    var myBadge = sessionId.slice(-4).toUpperCase();
    var html = '<div class="merc-lb-table">';
    html += '<div class="merc-lb-row merc-lb-header"><span>#</span><span>Student</span><span>Streak</span><span>Msgs</span><span>Mode</span></div>';
    rows.forEach(function (r) {
      var isMe = r.badge === myBadge;
      html += '<div class="merc-lb-row' + (isMe ? ' merc-lb-me' : '') + '">';
      html += '<span>' + escapeHtml(String(r.rank)) + '</span>';
      html += '<span class="merc-lb-badge">' + escapeHtml(r.name || r.badge) + (isMe ? ' <span style="font-size:9px;opacity:0.6">(you)</span>' : '') + '</span>';
      html += '<span>' + escapeHtml(String(r.streak)) + '</span>';
      html += '<span>' + escapeHtml(String(r.messages)) + '</span>';
      html += '<span>' + (r.unlocked ? '<span style="color:#C9922A">Direct</span>' : 'Socratic') + '</span>';
      html += '</div>';
    });
    html += '</div>';
    container.insertAdjacentHTML('afterbegin', html);
  }

  // =========================================================================
  // 19. Voice input
  // =========================================================================
  function toggleVoiceInput() {
    var btn = document.getElementById('merc-voice-btn');
    if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
      appendSystemNotice('Voice input is not supported in this browser. Try Chrome.');
      return;
    }
    if (voiceActive && voiceRecognition) {
      voiceRecognition.stop();
      voiceActive = false;
      if (btn) btn.classList.remove('merc-voice-active');
      return;
    }
    if (voiceRecognition) {
      try { voiceRecognition.abort(); } catch(e) { console.warn('[Mercurius]', e); }
      voiceRecognition = null;
    }
    var SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    voiceRecognition = new SpeechRec();
    voiceRecognition.continuous = false;
    voiceRecognition.interimResults = false;
    voiceRecognition.lang = 'en-US';
    voiceActive = true;
    if (btn) btn.classList.add('merc-voice-active');
    voiceRecognition.onresult = function (e) {
      if (!e.results || !e.results[0] || !e.results[0][0]) return;
      var transcript = e.results[0][0].transcript;
      var ta = document.getElementById('merc-textarea');
      if (ta) { ta.value = transcript; ta.dispatchEvent(new Event('input')); }
      voiceActive = false;
      if (btn) btn.classList.remove('merc-voice-active');
    };
    voiceRecognition.onerror = function () {
      voiceActive = false;
      if (btn) btn.classList.remove('merc-voice-active');
      appendSystemNotice('Voice input error \u2014 please try again.');
    };
    voiceRecognition.onend = function () {
      voiceActive = false;
      if (btn) btn.classList.remove('merc-voice-active');
    };
    voiceRecognition.start();
  }

  // =========================================================================
  // 20. Initialize on DOMContentLoaded (or immediately if already loaded)
  // =========================================================================
  // ── Thursday meeting push notification ──
  var meetingReminderTimeout = null;
  function scheduleMeetingReminder() {
    if (!('Notification' in window) || Notification.permission !== 'granted') return;
    var now = new Date();
    var dayOfWeek = now.getDay(); // 0=Sun, 4=Thu
    // Find next Thursday at 7:50 AM (30 min before 8:20 meeting)
    var daysUntilThursday = (4 - dayOfWeek + 7) % 7;
    if (daysUntilThursday === 0) {
      // It's Thursday — check if we're before 7:50
      var target = new Date(now);
      target.setHours(7, 50, 0, 0);
      if (now >= target) daysUntilThursday = 7; // Already past, schedule next week
    }
    var nextThursday = new Date(now);
    nextThursday.setDate(now.getDate() + daysUntilThursday);
    nextThursday.setHours(7, 50, 0, 0);
    var msUntil = nextThursday.getTime() - now.getTime();
    // Only schedule if within 7 days (don't hold timers forever)
    if (msUntil > 0 && msUntil < 7 * 24 * 60 * 60 * 1000) {
      meetingReminderTimeout = setTimeout(function() {
        // Check we still have permission
        if (Notification.permission === 'granted') {
          var notif = new Notification('Mayo AI Literacy Club', {
            body: 'Club meets in 30 minutes. Want to prep with Mercurius?',
            icon: '/icons/icon-192.png',
            tag: 'meeting-reminder',
            requireInteraction: true
          });
          notif.addEventListener('click', function() {
            window.focus();
            if (typeof MercuriusOpen === 'function') MercuriusOpen();
            notif.close();
          });
          // Schedule the next one
          scheduleMeetingReminder();
        }
      }, msUntil);
    }
  }

  function init() {
    if (document.getElementById('merc-toggle')) return;
    buildWidget();

    // Auto-open mode: hide the toggle and open the panel immediately
    var autoOpen = window.MercuriusConfig && window.MercuriusConfig.autoOpen;
    if (autoOpen) {
      var toggle = document.getElementById('merc-toggle');
      var panel  = document.getElementById('merc-panel');
      if (toggle) toggle.style.display = 'none';
      if (panel)  { panel.classList.add('merc-open'); isOpen = true; }
      var ta = document.getElementById('merc-textarea');
      if (ta) setTimeout(function () { ta.focus(); }, 280);
    }

    // Expose global open function for in-page buttons
    window.MercuriusOpen = function () {
      var panel  = document.getElementById('merc-panel');
      var toggle = document.getElementById('merc-toggle');
      if (panel)  { panel.classList.add('merc-open'); isOpen = true; }
      if (toggle) toggle.style.display = 'none';
      var ta = document.getElementById('merc-textarea');
      if (ta) setTimeout(function () { ta.focus(); }, 280);
    };

    if (isUnlocked) {
      fetch(MODE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: sessionId, mode: currentMode, clientUnlocked: true }),
      }).catch(function (e) { console.warn('[Mercurius]', e); });
    }

    // Immediate-value onboarding: auto-send starter message for first-time visitors
    if (!safeGetItem('merc_onboarded')) {
      safeSetItem('merc_onboarded', '1');
      setTimeout(function() {
        sendMessage('This is my first time using Mercurius. Introduce yourself briefly and ask me one interesting question about AI to get started.', true);
      }, 800);
    }

    // Returning user context
    var convos = [];
    try { convos = JSON.parse(safeGetItem('merc_convos') || '[]'); } catch(e) { console.warn('[Mercurius]', e); }
    if (convos.length > 0 && safeGetItem('merc_onboarded')) {
      var lastConvo = convos[0];
      if (lastConvo && lastConvo.title) {
        var welcomeEl = document.createElement('div');
        welcomeEl.className = 'merc-msg merc-msg-notice';
        welcomeEl.textContent = 'Welcome back. Last time: "' + lastConvo.title.slice(0, 80) + '..."';
        var container = document.getElementById('merc-messages');
        if (container) {
          var tags = document.getElementById('merc-topic-tags');
          if (tags) container.insertBefore(welcomeEl, tags);
        }
      }
    }

    // Restore display name
    var savedName = getDisplayNameLocal();
    if (savedName) updateDisplayNameInSidebar(savedName);

    // Initialize conversation ID for this session
    currentConversationId = 'conv_' + Date.now();

    // Request notification permission (non-blocking)
    if ('Notification' in window && Notification.permission === 'default') {
      // Delay to avoid annoying users on first load
      setTimeout(function() {
        if (isOpen) Notification.requestPermission();
      }, 30000);
    }

    // Schedule Thursday meeting reminder check
    scheduleMeetingReminder();

    // Offline banner retry button
    var retryBtn = document.querySelector('.merc-offline-retry');
    if (retryBtn) retryBtn.addEventListener('click', function() { window.location.reload(); });

    // Offline detection
    window.addEventListener('offline', function() {
      var banner = document.getElementById('merc-offline-banner');
      if (banner) banner.classList.add('merc-visible');
    });
    window.addEventListener('online', function() {
      var banner = document.getElementById('merc-offline-banner');
      if (banner) banner.classList.remove('merc-visible');
    });
    // Check on load
    if (!navigator.onLine) {
      var offBanner = document.getElementById('merc-offline-banner');
      if (offBanner) offBanner.classList.add('merc-visible');
    }

    // Cleanup on page unload
    window.addEventListener('beforeunload', function() {
      if (meetingReminderTimeout) clearTimeout(meetingReminderTimeout);
      if (voiceRecognition) { try { voiceRecognition.abort(); } catch(e) { console.warn('[Mercurius]', e); } }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
