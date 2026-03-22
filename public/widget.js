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

  // =========================================================================
  // 2. Session ID — persist across browser sessions using localStorage
  // =========================================================================
  var SESSION_KEY = 'merc_session_id';
  var sessionId = localStorage.getItem(SESSION_KEY);
  var isReturningStudent = !!sessionId;
  if (!sessionId) {
    sessionId =
      'merc_' +
      Math.random().toString(16).slice(2) +
      Math.random().toString(16).slice(2) +
      '_' +
      Date.now().toString(16);
    localStorage.setItem(SESSION_KEY, sessionId);
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
  var isUnlocked = localStorage.getItem('merc_unlocked') === 'true';
  var currentMode = localStorage.getItem('merc_mode') || 'socratic';
  var reflectionIndex = 0;
  var conversationHistory = [];
  var summaryFetched = false;
  var summaryMessageCountAtFetch = 0;
  var tooltipVisible = false;
  var voiceActive = false;
  var voiceRecognition = null;
  var currentRightPanel = null; // 'quiz' | 'map' | 'report' | 'leaderboard' | 'summary' | null

  var REFLECTION_PROMPTS = [
    '\u23F8 Pause: What\'s something Mercurius \u2160 said that you\'d want to verify yourself?',
    '\u23F8 Pause: In your own words, what\'s the most important thing you\'ve discussed so far?',
    '\u23F8 Pause: Has Mercurius \u2160 said anything that felt too confident? What would you push back on?',
    '\u23F8 Pause: Who might be affected by the topic you\'re discussing who wasn\'t mentioned?',
    '\u23F8 Pause: What question do you still have that hasn\'t been answered yet?',
    '\u23F8 Pause: How would you explain what you\'ve learned to someone who hasn\'t taken this class?',
    '\u23F8 Pause: What assumption is Mercurius \u2160 making that might not apply to everyone?',
    '\u23F8 Pause: If Mercurius \u2160 is wrong about something, how would you find out?',
  ];

  var STARTER_TOPICS = [
    { emoji: '\uD83E\uDD16', label: 'How does AI actually work?' },
    { emoji: '\u2696\uFE0F', label: 'Is AI biased?' },
    { emoji: '\uD83D\uDCDA', label: 'When should I NOT use AI?' },
    { emoji: '\uD83C\uDFAF', label: 'How do I prompt AI well?' },
    { emoji: '\uD83C\uDFEB', label: 'AI and education equity' },
    { emoji: '\uD83D\uDCCB', label: 'Prep me for the next club meeting' },
    { emoji: '\uD83C\uDF10', label: 'AI and the real world' },
  ];

  var TRANSPARENCY_TEXT =
    'Mercurius \u2160 is powered by Claude, an AI made by Anthropic. ' +
    'It cannot browse the web, remember previous sessions, or learn from your conversations. ' +
    'All responses are AI-generated and may contain errors. ' +
    'This tool is designed to build critical thinking about AI \u2014 not to replace it.';

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
      '        <span class="merc-mode-lock" id="merc-tab-lock-icon">&#128274;</span>',
      '      </button>',
      '      <button class="merc-mode-btn" id="merc-tab-debate">',
      '        <span class="merc-mode-dot"></span> &#9876;&#65039; Debate',
      '      </button>',
      '    </div>',

      '    <div class="merc-sidebar-section">',
      '      <div class="merc-sidebar-section-label">Tools</div>',
      '      <button class="merc-tool-btn" id="merc-btn-quiz"><span class="merc-tool-icon">&#128221;</span> Quiz</button>',
      '      <button class="merc-tool-btn" id="merc-btn-map"><span class="merc-tool-icon">&#128205;</span> Concept Map</button>',
      '      <button class="merc-tool-btn" id="merc-btn-report"><span class="merc-tool-icon">&#127941;</span> Report Card</button>',
      '      <button class="merc-tool-btn" id="merc-btn-lb"><span class="merc-tool-icon">&#127942;</span> Leaderboard</button>',
      '      <button class="merc-tool-btn" id="merc-btn-summary"><span class="merc-tool-icon">&#128203;</span> Summary</button>',
      '    </div>',

      '  </div>',
      '  <div class="merc-sidebar-footer">',
      '    <div class="merc-streak-badge merc-hidden" id="merc-header-streak">&#128293; <span id="merc-streak-val"></span> day streak</div>',
      '    <button class="merc-info-btn" id="merc-btn-info">&#8505;&#65039; About Mercurius &#8544;</button>',
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
      '      <button id="merc-voice-btn" class="merc-voice-btn" aria-label="Voice input" title="Speak your answer">&#127908;</button>',
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
      summary: 'merc-btn-summary'
    };
    var activeBtn = document.getElementById(btnIdMap[type]);
    if (activeBtn) activeBtn.classList.add('tool-active');

    // Set title
    var titles = {
      quiz: '\uD83D\uDCDD Comprehension Quiz',
      map: '\uD83D\uDCCD Concept Map',
      report: '\uD83C\uDFC6 Report Card',
      leaderboard: '\uD83C\uDFC5 Leaderboard',
      summary: '\uD83D\uDCCB Summary'
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

  function loadQuizInPanel(body) {
    if (conversationHistory.length < 4) {
      body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Have a longer conversation first \u2014 then I can quiz you on what we covered.</p>');
      return;
    }
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">Generating quiz\u2026</p>');
    fetch(QUIZ_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId })
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        // Remove loading paragraph
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        if (data.error) {
          body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Could not generate quiz.') + '</p>');
          return;
        }
        renderQuiz(data, body);
      })
      .catch(function () {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error \u2014 try again.</p>');
      });
  }

  function loadMapInPanel(body) {
    if (conversationHistory.length < 4) {
      body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Have a longer conversation first.</p>');
      return;
    }
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">Building concept map\u2026</p>');
    fetch(CONCEPT_MAP_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId })
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        if (data.error) {
          body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Error') + '</p>');
          return;
        }
        renderConceptMap(data, body);
      })
      .catch(function () {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error.</p>');
      });
  }

  function loadReportInPanel(body) {
    if (conversationHistory.length < 4) {
      body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Have a longer conversation first.</p>');
      return;
    }
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">Generating report card\u2026</p>');
    fetch(REPORT_CARD_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId })
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        if (data.error) {
          body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Error') + '</p>');
          return;
        }
        renderReportCard(data, body);
      })
      .catch(function () {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error.</p>');
      });
  }

  function loadLeaderboardInPanel(body) {
    body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-loading">Loading\u2026</p>');
    fetch(LEADERBOARD_ENDPOINT, {
      method: 'GET',
      headers: { 'Content-Type': 'application/json' }
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        renderLeaderboard(data, body);
      })
      .catch(function () {
        var loading = body.querySelector('.merc-quiz-loading');
        if (loading) loading.parentNode.removeChild(loading);
        body.insertAdjacentHTML('afterbegin', '<p class="merc-quiz-empty">Connection error.</p>');
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

    // Main close button (X in header)
    var closeBtn = document.getElementById('merc-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', function () {
        isOpen = false;
        panel.classList.remove('merc-open');
        toggle.setAttribute('aria-expanded', 'false');
      });
    }

    // Topic tags
    var tagsContainer = document.getElementById('merc-topic-tags');
    if (tagsContainer) {
      tagsContainer.addEventListener('click', function (e) {
        var btn = e.target.closest('.merc-tag');
        if (btn) {
          var topic = btn.getAttribute('data-topic');
          tagsContainer.parentNode.removeChild(tagsContainer);
          sendMessage(topic);
        }
      });
    }

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

    // Initialise mode bar to match stored state
    updateModeBar();
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
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ messages: messages, sessionId: sessionId }),
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        removeTyping(typingId);
        setLoading(false);

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
        } else if (data.mode && data.mode !== currentMode) {
          currentMode = data.mode;
          localStorage.setItem('merc_mode', currentMode);
          updateModeBar();
        }

        // Update streak badge
        if (data.streak && data.streak > 1) {
          var badge = document.getElementById('merc-header-streak');
          var val = document.getElementById('merc-streak-val');
          if (badge && val) {
            val.textContent = data.streak;
            badge.classList.remove('merc-hidden');
          }
        }

        // Always show bot reply
        appendBotMessage(reply);

        if (!isHidden) {
          if (summaryFetched && conversationHistory.length > summaryMessageCountAtFetch + 2) {
            summaryFetched = false;
          }
          if (userMessageCount > 0 && userMessageCount % 5 === 0) {
            appendReflectionCard();
          }
        }

        scrollToBottom();
      })
      .catch(function (err) {
        console.error('[Mercurius] fetch error:', err);
        removeTyping(typingId);
        setLoading(false);
        appendBotMessage(
          'I seem to have lost my connection \u2014 possibly a network hiccup on either end. ' +
          'This is actually something worth noting: AI tools depend on internet infrastructure, ' +
          'which can fail. Try again in a moment?'
        );
      });
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
      .then(function (res) { return res.json(); })
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
    if (el) el.parentNode.removeChild(el);
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

    escaped = escaped.replace(/\[SOURCE:\s*([^\]]+)\]/g, '<span class="merc-source">&#128279; $1</span>');

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
    unpackBtn.innerHTML = '&#128269; Unpack this';
    unpackBtn.title = 'Ask Mercurius to explain its reasoning';

    var flagBtn = document.createElement('button');
    flagBtn.className = 'merc-action-btn';
    flagBtn.innerHTML = '&#128681; Flag bias';
    flagBtn.title = 'Flag potential bias or missing perspectives';

    var hasQuestion = originalText.indexOf('?') !== -1;
    var whyBtn = null;
    if (hasQuestion) {
      whyBtn = document.createElement('button');
      whyBtn.className = 'merc-action-btn merc-action-btn-why';
      whyBtn.innerHTML = '&#129300; Why this question?';
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
      .then(function (res) { return res.json(); })
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
    var btnSocratic = document.getElementById('merc-tab-socratic');
    var btnDirect   = document.getElementById('merc-tab-direct');
    var btnDebate   = document.getElementById('merc-tab-debate');
    var lockIcon    = document.getElementById('merc-tab-lock-icon');
    var modeLabel   = document.getElementById('merc-mode-label');

    if (!btnSocratic || !btnDirect) return;

    // Unlock state
    if (isUnlocked) {
      btnDirect.disabled = false;
      if (lockIcon) lockIcon.textContent = '';
    } else {
      btnDirect.disabled = true;
      if (lockIcon) lockIcon.innerHTML = '&#128274;';
    }

    // Active states
    [btnSocratic, btnDirect, btnDebate].forEach(function (b) {
      if (b) b.classList.remove('active');
    });

    var activeBtn =
      currentMode === 'direct' ? btnDirect :
      currentMode === 'debate' ? btnDebate :
      btnSocratic;
    if (activeBtn) activeBtn.classList.add('active');

    // Mode label in header
    var modeNames = { socratic: 'Socratic', direct: 'Direct', debate: 'Debate' };
    if (modeLabel) modeLabel.textContent = modeNames[currentMode] || 'Socratic';
  }

  function showUnlockCelebration() {
    var header = document.getElementById('merc-main-header');
    if (header) {
      header.classList.add('merc-unlock-flash');
      setTimeout(function () { header.classList.remove('merc-unlock-flash'); }, 1800);
    }
  }

  function handleModeSwitchTo(newMode) {
    if (newMode !== 'debate' && !isUnlocked) return;
    fetch(MODE_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId, mode: newMode, clientUnlocked: isUnlocked }),
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.mode) {
          currentMode = data.mode;
          localStorage.setItem('merc_mode', currentMode);
          updateModeBar();
          appendSystemNotice(
            currentMode === 'debate'
              ? 'Switched to Debate Mode \u2014 Mercurius will take a position on AI ethics and argue against you. Make your case!'
              : currentMode === 'direct'
              ? 'Switched to Direct Mode \u2014 Mercurius will now lead with substantive explanations.'
              : 'Switched to Socratic Mode \u2014 Mercurius will guide your thinking with questions.'
          );
          if (data.mode === 'debate') {
            setTimeout(function () {
              sendMessage('Begin the debate \u2014 pick your position now and give your opening argument. Then challenge me.', true);
            }, 300);
          }
        }
      })
      .catch(function () { /* silent fail */ });
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
      '<span style="color:#C9922A">&#9679; Core</span>' +
      '<span style="color:#4ade80">&#9679; Related</span>' +
      '<span style="color:#60a5fa">&#9679; Example</span>' +
      '</div>';

    container.insertAdjacentHTML('afterbegin', '<div class="merc-map-svg">' + svg + '</div>' + legend);
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
    var html = '<div class="merc-lb-table">';
    html += '<div class="merc-lb-row merc-lb-header"><span>#</span><span>Student</span><span>\uD83D\uDD25</span><span>Msgs</span><span>Mode</span></div>';
    rows.forEach(function (r) {
      html += '<div class="merc-lb-row">';
      html += '<span>' + r.rank + '</span>';
      html += '<span class="merc-lb-badge">' + escapeHtml(r.badge) + '</span>';
      html += '<span>' + r.streak + '</span>';
      html += '<span>' + r.messages + '</span>';
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
    var SpeechRec = window.SpeechRecognition || window.webkitSpeechRecognition;
    voiceRecognition = new SpeechRec();
    voiceRecognition.continuous = false;
    voiceRecognition.interimResults = false;
    voiceRecognition.lang = 'en-US';
    voiceActive = true;
    if (btn) btn.classList.add('merc-voice-active');
    voiceRecognition.onresult = function (e) {
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
  function init() {
    if (document.getElementById('merc-toggle')) return;
    buildWidget();

    if (isUnlocked) {
      fetch(MODE_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionId: sessionId, mode: currentMode, clientUnlocked: true }),
      }).catch(function () { /* silent — best effort */ });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
