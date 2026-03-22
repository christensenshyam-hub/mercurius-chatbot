/**
 * widget.js — Mercurius Ⅰ Self-Contained Chat Widget
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

  // =========================================================================
  // 2. Session ID — persist across browser sessions using localStorage
  // =========================================================================
  var SESSION_KEY = 'merc_session_id';
  var sessionId = localStorage.getItem(SESSION_KEY);
  var isReturningStudent = !!sessionId;
  if (!sessionId) {
    // Generate a simple UUID-like string without crypto dependency
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
      // Derive the CSS URL from the script tag's src
      var scripts = document.querySelectorAll('script[src]');
      for (var i = 0; i < scripts.length; i++) {
        if (scripts[i].src.indexOf('widget.js') !== -1) {
          cssHref = scripts[i].src.replace('widget.js', 'widget.css');
          break;
        }
      }
    }
    // Skip if we couldn't find the URL, or if a link with that href already exists
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
  var conversationHistory = []; // [{role, content}, ...] — max 20 stored
  var summaryFetched = false;
  var summaryMessageCountAtFetch = 0;
  var summaryVisible = false;
  var quizVisible = false;
  var tooltipVisible = false;

  var REFLECTION_PROMPTS = [
    '⏸ Pause: What\'s something Mercurius Ⅰ said that you\'d want to verify yourself?',
    '⏸ Pause: In your own words, what\'s the most important thing you\'ve discussed so far?',
    '⏸ Pause: Has Mercurius Ⅰ said anything that felt too confident? What would you push back on?',
    '⏸ Pause: Who might be affected by the topic you\'re discussing who wasn\'t mentioned?',
    '⏸ Pause: What question do you still have that hasn\'t been answered yet?',
    '⏸ Pause: How would you explain what you\'ve learned to someone who hasn\'t taken this class?',
    '⏸ Pause: What assumption is Mercurius Ⅰ making that might not apply to everyone?',
    '⏸ Pause: If Mercurius Ⅰ is wrong about something, how would you find out?',
  ];

  var STARTER_TOPICS = [
    { emoji: '🤖', label: 'How does AI actually work?' },
    { emoji: '⚖️', label: 'Is AI biased?' },
    { emoji: '📚', label: 'When should I NOT use AI?' },
    { emoji: '🎯', label: 'How do I prompt AI well?' },
    { emoji: '🏫', label: 'AI and education equity' },
    { emoji: '📋', label: 'Prep me for the next club meeting' },
  ];

  var TRANSPARENCY_TEXT =
    'Mercurius Ⅰ is powered by Claude, an AI made by Anthropic. ' +
    'It cannot browse the web, remember previous sessions, or learn from your conversations. ' +
    'All responses are AI-generated and may contain errors. ' +
    'This tool is designed to build critical thinking about AI — not to replace it.';

  // =========================================================================
  // 5. Build DOM
  // =========================================================================
  function buildWidget() {
    // --- Toggle button ---
    var toggle = document.createElement('button');
    toggle.id = 'merc-toggle';
    toggle.setAttribute('aria-label', 'Open Mercurius Ⅰ AI tutor');
    toggle.innerHTML = '<span class="merc-monogram">M&#8544;</span>';

    // --- Main panel ---
    var panel = document.createElement('div');
    panel.id = 'merc-panel';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Mercurius Ⅰ AI literacy tutor');

    panel.innerHTML = [
      // Header
      '<div class="merc-header">',
      '  <div class="merc-header-avatar">M&#8544;</div>',
      '  <div class="merc-header-text">',
      '    <div class="merc-header-title">Mercurius &#8544;</div>',
      '    <div class="merc-header-subtitle">Here to help you think, not think for you</div>',
      '  </div>',
      '  <div class="merc-header-actions">',
      '    <button class="merc-header-btn" id="merc-btn-quiz"    title="Generate comprehension quiz" aria-label="Quiz">&#128221;</button>',
      '    <button class="merc-header-btn" id="merc-btn-summary" title="Get conversation summary"    aria-label="Conversation summary">&#128203;</button>',
      '    <button class="merc-header-btn" id="merc-btn-info"    title="About Mercurius Ⅰ"          aria-label="About">&#8505;&#65039;</button>',
      '  </div>',
      '</div>',

      // Mode selector
      '<div class="merc-mode-bar" id="merc-mode-bar">',
      '  <span class="merc-mode-bar-label">MODE</span>',
      '  <div class="merc-mode-tabs">',
      '    <button class="merc-mode-tab merc-mode-tab-active" id="merc-tab-socratic">Socratic</button>',
      '    <button class="merc-mode-tab merc-mode-tab-locked" id="merc-tab-direct" disabled>',
      '      Direct <span class="merc-tab-lock" id="merc-tab-lock-icon">&#128274;</span>',
      '    </button>',
      '  </div>',
      '</div>',

      // Tooltip (hidden by default)
      '<div class="merc-tooltip merc-hidden" id="merc-tooltip">',
      '  <strong style="color: var(--merc-gold); font-size:12px;">About Mercurius &#8544;</strong><br><br>',
      TRANSPARENCY_TEXT,
      '</div>',

      // Summary panel (hidden by default)
      '<div class="merc-summary-panel merc-hidden" id="merc-summary-panel">',
      '  <h4>Conversation Summary</h4>',
      '  <div id="merc-summary-content" style="color: rgba(241,245,249,0.85); font-size:12.5px; line-height:1.6;"></div>',
      '</div>',

      // Quiz panel (hidden by default)
      '<div class="merc-quiz-panel merc-hidden" id="merc-quiz-panel">',
      '  <div class="merc-quiz-header">',
      '    <span class="merc-quiz-title" id="merc-quiz-title">Comprehension Check</span>',
      '    <button class="merc-quiz-close" id="merc-quiz-close" aria-label="Close quiz">&#10005;</button>',
      '  </div>',
      '  <div id="merc-quiz-content"></div>',
      '</div>',

      // Messages area
      '<div class="merc-messages" id="merc-messages">',
      '  <div class="merc-topic-tags" id="merc-topic-tags">',
      '    <div class="merc-topic-tags-label">Start with a topic</div>',
      buildTopicTagsHTML(),
      '  </div>',
      '</div>',

      // Input area
      '<div class="merc-input-area">',
      '  <textarea',
      '    id="merc-textarea"',
      '    class="merc-textarea"',
      '    placeholder="Ask me anything about AI..."',
      '    rows="1"',
      '    aria-label="Message input"',
      '  ></textarea>',
      '  <button id="merc-send-btn" class="merc-send-btn" aria-label="Send message">',
      '    <svg viewBox="0 0 24 24"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>',
      '  </button>',
      '</div>',
    ].join('');

    document.body.appendChild(toggle);
    document.body.appendChild(panel);

    // Attach events after DOM insertion
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
  // 6. Events
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

    // Topic tags
    var tagsContainer = document.getElementById('merc-topic-tags');
    if (tagsContainer) {
      tagsContainer.addEventListener('click', function (e) {
        var btn = e.target.closest('.merc-tag');
        if (btn) {
          var topic = btn.getAttribute('data-topic');
          // Remove the tags area so it doesn't clutter
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
        // Auto-expand up to ~3 lines (90px max set in CSS)
        textarea.style.height = 'auto';
        textarea.style.height = Math.min(textarea.scrollHeight, 90) + 'px';
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
      // Close tooltip on click outside
      document.addEventListener('click', function (e) {
        if (tooltipVisible && !tooltip.contains(e.target) && e.target !== infoBtn) {
          tooltipVisible = false;
          tooltip.classList.add('merc-hidden');
        }
      });
    }

    // Summary panel toggle
    var summaryBtn = document.getElementById('merc-btn-summary');
    if (summaryBtn) {
      summaryBtn.addEventListener('click', function () {
        handleSummaryToggle();
      });
    }

    // Quiz panel toggle
    var quizBtn = document.getElementById('merc-btn-quiz');
    if (quizBtn) {
      quizBtn.addEventListener('click', function () {
        handleQuizToggle();
      });
    }

    // Quiz close button
    var quizClose = document.getElementById('merc-quiz-close');
    if (quizClose) {
      quizClose.addEventListener('click', function () {
        var qp = document.getElementById('merc-quiz-panel');
        if (qp) qp.classList.add('merc-hidden');
        quizVisible = false;
      });
    }

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
  // 7. Send message & get reply
  // =========================================================================
  function sendMessage(text, isHidden) {
    isHidden = isHidden || false;

    if (!isHidden) {
      userMessageCount++;
      appendUserMessage(text);
    }

    // Add to history
    conversationHistory.push({ role: 'user', content: text });
    if (conversationHistory.length > 20) {
      conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
    }

    // Disable send while waiting
    setLoading(true);

    // Show typing indicator
    var typingId = showTyping();

    // Build messages payload (last 20)
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

        // Add assistant reply to history
        conversationHistory.push({ role: 'assistant', content: reply });
        if (conversationHistory.length > 20) {
          conversationHistory = conversationHistory.slice(conversationHistory.length - 20);
        }

        if (!isHidden) {
          appendBotMessage(reply);
          // Summary is now stale — require re-fetch on next open
          if (summaryFetched && conversationHistory.length > summaryMessageCountAtFetch + 2) {
            summaryFetched = false;
          }
        }

        // Inject reflection card every 5 user messages
        if (!isHidden && userMessageCount > 0 && userMessageCount % 5 === 0) {
          appendReflectionCard();
        }

        scrollToBottom();
      })
      .catch(function (err) {
        console.error('[Mercurius] fetch error:', err);
        removeTyping(typingId);
        setLoading(false);
        if (!isHidden) {
          appendBotMessage(
            "I seem to have lost my connection — possibly a network hiccup on either end. " +
            "This is actually something worth noting: AI tools depend on internet infrastructure, " +
            "which can fail. Try again in a moment?"
          );
        }
      });
  }

  // =========================================================================
  // 8. DOM helpers — append messages
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

    // Confidence meter
    var confidenceEl = buildConfidenceMeter(text);

    // Action buttons
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

  // =========================================================================
  // 9. Typing indicator
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
  // 10. Minimal Markdown renderer (no external deps)
  // =========================================================================
  function renderMarkdown(text) {
    if (!text) return '';

    // Escape HTML first to prevent XSS
    var escaped = escapeHtml(text);

    // Process headings: ## Heading → <h3>
    escaped = escaped.replace(/^##\s+(.+)$/gm, '<h3>$1</h3>');
    escaped = escaped.replace(/^###\s+(.+)$/gm, '<h3>$1</h3>');

    // Bold: **text** or __text__
    escaped = escaped.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    escaped = escaped.replace(/__(.+?)__/g, '<strong>$1</strong>');

    // Italic: *text* or _text_ (single, not preceded by letter)
    escaped = escaped.replace(/(?<![*_])\*(?!\s)(.+?)(?<!\s)\*(?![*_])/g, '<em>$1</em>');
    escaped = escaped.replace(/(?<!_)_(?!\s)(.+?)(?<!\s)_(?!_)/g, '<em>$1</em>');

    // Inline code: `code`
    escaped = escaped.replace(/`(.+?)`/g, '<code>$1</code>');

    // Source citations: [SOURCE: text] → styled chip
    escaped = escaped.replace(/\[SOURCE:\s*([^\]]+)\]/g, '<span class="merc-source">&#128279; $1</span>');

    // Unordered lists: lines starting with "- " or "* "
    escaped = escaped.replace(/^[-*]\s+(.+)$/gm, '<li>$1</li>');
    escaped = escaped.replace(/(<li>.*<\/li>(\n|$))+/g, function (m) {
      return '<ul>' + m.replace(/\n$/, '') + '</ul>';
    });

    // Ordered lists: lines starting with "1. " or "2. " etc.
    escaped = escaped.replace(/^\d+\.\s+(.+)$/gm, '<li>$1</li>');
    escaped = escaped.replace(/(<li>.*<\/li>(\n|$))+/g, function (m) {
      // Avoid double-wrapping ul items as ol
      if (m.indexOf('<ul>') !== -1 || m.indexOf('<ol>') !== -1) return m;
      return '<ol>' + m.replace(/\n$/, '') + '</ol>';
    });

    // Double newlines → paragraph breaks
    var parts = escaped.split(/\n\n+/);
    escaped = parts
      .map(function (p) {
        p = p.trim();
        if (!p) return '';
        // Don't wrap block elements in <p>
        if (/^<(h[2-6]|ul|ol|li|blockquote)/.test(p)) return p;
        return '<p>' + p.replace(/\n/g, '<br>') + '</p>';
      })
      .filter(Boolean)
      .join('');

    return escaped;
  }

  // =========================================================================
  // 11. Confidence meter
  // =========================================================================
  function parseConfidence(text) {
    if (!text) return null;

    var lower = text.toLowerCase();

    // Explicit percentage like "85%" or "(85%)" or "maybe 85%"
    var pctMatch = text.match(/\b(\d{1,3})%/);
    if (pctMatch) {
      var pct = parseInt(pctMatch[1], 10);
      if (pct >= 0 && pct <= 100) return pct;
    }

    // 50/50
    if (/50\s*\/\s*50/.test(lower)) return 50;

    // Verbal phrases — check most specific first
    if (/\b(quite confident|very confident|highly confident|very sure|pretty confident)\b/.test(lower)) return 82;
    if (/\bconfident\b/.test(lower)) return 70;
    if (/\b(uncertain|not sure|murky|murkier|unclear|not certain|a bit unsure)\b/.test(lower)) return 35;
    if (/\b(i actually don'?t know|i don'?t know|no idea|not sure at all|genuinely don'?t know)\b/.test(lower)) return 15;

    return null; // unverified
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
  // 12. Action buttons — Unpack & Flag
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
    flagBtn.innerHTML = '&#128681; Flag';
    flagBtn.title = 'Flag potential bias or missing perspectives';

    unpackBtn.addEventListener('click', function () {
      unpackBtn.disabled = true;
      flagBtn.disabled = true;
      sendMessage(
        'Please explain your reasoning for your last response — what assumptions did you make, ' +
        'how did you arrive at that answer, and what might you be getting wrong?',
        true
      );
      // Show a visible follow-up after the hidden send resolves
      // We intercept via the next appendBotMessage via normal flow
    });

    flagBtn.addEventListener('click', function () {
      unpackBtn.disabled = true;
      flagBtn.disabled = true;
      sendMessage(
        'Flag this response for potential bias — what perspectives or groups might this answer overlook?',
        true
      );
    });

    el.appendChild(unpackBtn);
    el.appendChild(flagBtn);
    return el;
  }

  // =========================================================================
  // 13. Summary panel
  // =========================================================================
  function handleSummaryToggle() {
    var panel = document.getElementById('merc-summary-panel');
    if (!panel) return;

    var hasNewMessages =
      !summaryFetched ||
      conversationHistory.length > summaryMessageCountAtFetch + 2;

    if (summaryVisible && !hasNewMessages) {
      // Just hide
      summaryVisible = false;
      panel.classList.add('merc-hidden');
      return;
    }

    if (!summaryFetched || hasNewMessages) {
      // Need to fetch/re-fetch summary
      if (conversationHistory.length < 2) {
        // Not enough conversation yet
        var summaryContent = document.getElementById('merc-summary-content');
        if (summaryContent) {
          summaryContent.innerHTML =
            '<em style="color: rgba(148,163,184,0.7)">Start chatting first — I\'ll summarize once we\'ve talked a bit.</em>';
        }
        panel.classList.remove('merc-hidden');
        summaryVisible = true;
        return;
      }

      var summaryContent2 = document.getElementById('merc-summary-content');
      if (summaryContent2) {
        summaryContent2.innerHTML =
          '<em style="color: rgba(148,163,184,0.5)">Generating summary...</em>';
      }
      panel.classList.remove('merc-hidden');
      summaryVisible = true;

      // Build a special summary request
      var summaryPrompt =
        'Please provide a brief summary of our conversation so far in this format:\n\n' +
        '**Key ideas covered**\n[2-3 bullet points]\n\n' +
        '**Questions worth thinking more about**\n[1-2 bullet points]\n\n' +
        '**One thing to verify yourself**\n[1 specific suggestion]\n\n' +
        'Keep it concise — this is a learning summary for the student.';

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
          var sc = document.getElementById('merc-summary-content');
          if (sc) {
            sc.innerHTML =
              '<em style="color: rgba(239,68,68,0.8)">Could not fetch summary — try again.</em>';
          }
        });
    } else {
      // Toggle visibility
      summaryVisible = !summaryVisible;
      panel.classList.toggle('merc-hidden', !summaryVisible);
    }
  }

  // =========================================================================
  // 14. Loading state
  // =========================================================================
  function setLoading(loading) {
    isLoading = loading;
    var sendBtn = document.getElementById('merc-send-btn');
    var textarea = document.getElementById('merc-textarea');
    if (sendBtn) sendBtn.disabled = loading;
    if (textarea) textarea.disabled = loading;
  }

  // =========================================================================
  // 15. Utilities
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
  // 16. Intercept appendBotMessage for hidden (action button) calls
  //     When isHidden=true in sendMessage, the response still needs to be
  //     shown as a new bot bubble in the normal messages area.
  // =========================================================================
  // (This is handled naturally — hidden messages still push to conversationHistory
  //  and the fetch callback calls appendBotMessage when isHidden is false.
  //  However, for Unpack/Flag we pass isHidden=true to avoid a user bubble
  //  but still want the bot reply to appear. We fix this by distinguishing
  //  "silent user bubble" from "silent response".)

  // Re-write sendMessage to handle isHidden correctly:
  // When isHidden=true → skip user bubble, but still show bot reply.
  // This is already how the code works above. The flag suppresses appendBotMessage
  // which is undesired for action buttons. Let's use a separate flag.

  // (The code above is already correct: for Unpack/Flag, isHidden=true skips the
  //  user bubble but the .then() callback calls appendBotMessage when isHidden is
  //  in scope. Let's verify the closure captures it properly — yes, isHidden is
  //  captured in the closure by the inner function. The check `if (!isHidden)` in
  //  the .then() will correctly show bot messages for action button calls because
  //  isHidden is false in those closures... wait, we passed isHidden=true.
  //
  //  We actually WANT the bot reply to show for Unpack/Flag. So we need to change
  //  the logic: isHidden only suppresses the USER bubble, not the bot reply.
  //  The reflection card injection should also be suppressed for hidden sends.)

  // The sendMessage function above already handles this correctly:
  // - When isHidden=true: skip appendUserMessage, skip reflectionCard injection
  // - Bot reply (appendBotMessage) is NOT gated on isHidden in the .then()
  // Wait — looking at the code above: `if (!isHidden) { appendBotMessage(reply); }`
  // This incorrectly suppresses the bot reply for action buttons!
  // We need to fix this. The solution is already structured correctly if we just
  // remove the isHidden check on appendBotMessage. But reflection card & user count
  // increment should be gated. Let me re-examine...
  //
  // For Unpack/Flag: we want bot reply to show, but no user bubble, no reflection card.
  // For normal sends: we want everything.
  //
  // The fix: always show bot reply. Only gate user bubble, reflection, and userMessageCount.
  // This is handled in the re-written sendMessage below — the function body above
  // already has `if (!isHidden) { appendBotMessage(reply); ... }` which we need to change.
  //
  // Since we've already written the function above with this bug, we note it as a known
  // issue... but actually looking carefully: the .then callback is a closure over isHidden.
  // When called from Unpack/Flag with isHidden=true, `if (!isHidden)` is false → bot
  // message NOT shown. Bug confirmed.
  //
  // We'll patch this by not writing a new sendMessage but by having the action buttons
  // call a dedicated function. See sendHiddenUserVisibleBot() below.

  // =========================================================================
  // Patch: sendHiddenUserVisibleBot — for Unpack/Flag
  // This sends a message without a user bubble but DOES show the bot reply.
  // =========================================================================
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
          "Connection issue — couldn't fetch the explanation. Try again in a moment."
        );
      });
  }

  // =========================================================================
  // Override buildActionButtons to use sendHiddenUserVisibleBot
  // (redefine to fix the bug described above)
  // =========================================================================
  buildActionButtons = function (originalText) {
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

    // "Why did I ask that?" — only show when message contains a question
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
        'Please explain your reasoning for your last response — what assumptions did you make, ' +
        'how did you arrive at that answer, and what might you be getting wrong?'
      );
    });

    flagBtn.addEventListener('click', function () {
      disableAll();
      sendHiddenUserVisibleBot(
        'Flag this response for potential bias — what perspectives or groups might this answer overlook? ' +
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
  };

  // Also fix the isHidden logic in the original sendMessage to only gate
  // the user bubble append (the bot reply should ALWAYS show).
  // We redefine sendMessage here:
  sendMessage = function (text, isHidden) {
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
          "I seem to have lost my connection — possibly a network hiccup on either end. " +
          "This is actually something worth noting: AI tools depend on internet infrastructure, " +
          "which can fail. Try again in a moment?"
        );
      });
  };

  // =========================================================================
  // 17. Mode bar helpers
  // =========================================================================
  function updateModeBar() {
    var tabSocratic = document.getElementById('merc-tab-socratic');
    var tabDirect   = document.getElementById('merc-tab-direct');
    var lockIcon    = document.getElementById('merc-tab-lock-icon');
    var bar         = document.getElementById('merc-mode-bar');
    if (!tabSocratic || !tabDirect) return;

    if (isUnlocked) {
      // Unlock the Direct tab
      tabDirect.disabled = false;
      tabDirect.classList.remove('merc-mode-tab-locked');
      if (lockIcon) lockIcon.textContent = '';
      bar.classList.add('merc-mode-unlocked');
    } else {
      tabDirect.disabled = true;
      tabDirect.classList.add('merc-mode-tab-locked');
      if (lockIcon) lockIcon.innerHTML = '&#128274;';
    }

    // Active tab highlight
    if (currentMode === 'direct') {
      tabDirect.classList.add('merc-mode-tab-active');
      tabSocratic.classList.remove('merc-mode-tab-active');
    } else {
      tabSocratic.classList.add('merc-mode-tab-active');
      tabDirect.classList.remove('merc-mode-tab-active');
    }
  }

  function showUnlockCelebration() {
    var bar = document.getElementById('merc-mode-bar');
    if (bar) {
      bar.classList.add('merc-unlock-flash');
      setTimeout(function () { bar.classList.remove('merc-unlock-flash'); }, 1800);
    }
  }

  function handleModeSwitchTo(newMode) {
    if (!isUnlocked) return;
    fetch(MODE_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId, mode: newMode }),
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.mode) {
          currentMode = data.mode;
          localStorage.setItem('merc_mode', currentMode);
          updateModeBar();
          appendSystemNotice(
            currentMode === 'direct'
              ? 'Switched to Direct Mode — Mercurius will now lead with substantive explanations.'
              : 'Switched to Socratic Mode — Mercurius will guide your thinking with questions.'
          );
        }
      })
      .catch(function () { /* silent fail */ });
  }

  function appendSystemNotice(text) {
    var container = document.getElementById('merc-messages');
    if (!container) return;
    var el = document.createElement('div');
    el.className = 'merc-msg merc-msg-notice';
    el.textContent = text;
    container.appendChild(el);
    scrollToBottom();
  }

  // =========================================================================
  // 18. Quiz panel
  // =========================================================================
  function handleQuizToggle() {
    var qp = document.getElementById('merc-quiz-panel');
    if (!qp) return;

    if (quizVisible) {
      qp.classList.add('merc-hidden');
      quizVisible = false;
      return;
    }

    // Show panel immediately
    qp.classList.remove('merc-hidden');
    quizVisible = true;

    if (conversationHistory.length < 4) {
      var qc = document.getElementById('merc-quiz-content');
      if (qc) qc.innerHTML = '<p class="merc-quiz-empty">Have a longer conversation first — then I can quiz you on what we covered.</p>';
      return;
    }

    // Show loading state
    var qc2 = document.getElementById('merc-quiz-content');
    if (qc2) qc2.innerHTML = '<p class="merc-quiz-loading">Generating quiz&#8230;</p>';

    fetch(QUIZ_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ sessionId: sessionId }),
    })
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.error) {
          var qce = document.getElementById('merc-quiz-content');
          if (qce) qce.innerHTML = '<p class="merc-quiz-empty">' + escapeHtml(data.message || 'Could not generate quiz.') + '</p>';
          return;
        }
        renderQuiz(data);
      })
      .catch(function () {
        var qcf = document.getElementById('merc-quiz-content');
        if (qcf) qcf.innerHTML = '<p class="merc-quiz-empty">Connection error — try again.</p>';
      });
  }

  function renderQuiz(quiz) {
    var titleEl = document.getElementById('merc-quiz-title');
    if (titleEl) titleEl.textContent = quiz.title || 'Comprehension Check';

    var content = document.getElementById('merc-quiz-content');
    if (!content) return;

    var questions = quiz.questions || [];
    var html = '<form id="merc-quiz-form">';

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

    content.innerHTML = html;

    // Attach submit handler
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
          var msg = pct === 100 ? 'Perfect score!' : pct >= 75 ? 'Great work!' : pct >= 50 ? 'Good effort.' : 'Keep exploring — revisit the topics above.';
          resultEl.innerHTML = '<span class="merc-quiz-score">' + correct + ' / ' + questions.length + '</span> ' + msg;
          resultEl.classList.remove('merc-hidden');
        }
      });
    }
  }

  // =========================================================================
  // 20. Initialize on DOMContentLoaded (or immediately if already loaded)
  // =========================================================================
  function init() {
    // Prevent double-initialization
    if (document.getElementById('merc-toggle')) return;
    buildWidget();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
