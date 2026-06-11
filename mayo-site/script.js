// Mayo AI Literacy Club — shared site script.
// Vanilla JS, no dependencies. Page-specific rendering (events, blog)
// lives inline on those pages; this file is only the shared chrome.

// ---- Mobile nav toggle (new header) ----
const navToggle = document.querySelector('.site-header .nav-toggle');
const siteNav = document.getElementById('site-nav');

navToggle?.addEventListener('click', () => {
  const open = siteNav.classList.toggle('is-open');
  navToggle.setAttribute('aria-expanded', String(open));
});

siteNav?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    siteNav.classList.remove('is-open');
    navToggle?.setAttribute('aria-expanded', 'false');
  });
});

// Legacy shim — blog-anthropic-pentagon.html (ported as-is from the
// old site) uses the old .navbar/.nav-links markup and loads this file.
const legacyToggle = document.querySelector('.navbar .nav-toggle');
const legacyLinks = document.querySelector('.navbar .nav-links');
legacyToggle?.addEventListener('click', () => legacyLinks?.classList.toggle('active'));

// ---- Active nav link (aria-current) ----
// Matches by pathname so both /about and /about.html highlight.
const path = (window.location.pathname.split('/').pop() || 'index.html')
  .replace(/\.html$/, '') || 'index';
document.querySelectorAll('.site-nav a').forEach((link) => {
  const target = (link.getAttribute('href') || '')
    .replace(/^\//, '').replace(/\.html$/, '').split('#')[0] || 'index';
  if (target === path) link.setAttribute('aria-current', 'page');
});

// ---- Fade-in on scroll ----
const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) entry.target.classList.add('visible');
    });
  },
  { threshold: 0.05, rootMargin: '0px 0px -40px 0px' }
);

document.querySelectorAll('.fade-in').forEach((el) => observer.observe(el));

// Call after dynamically inserting .fade-in elements.
window.observeFadeIns = (container) => {
  (container || document).querySelectorAll('.fade-in').forEach((el) => observer.observe(el));
};

// ---- Shared data fetch ----
// The same JSON files the Mercurius backend consumes — one source of
// truth for the site, the app, and the tutor's live context.
window.mayoFetch = (file) =>
  fetch(file).then((r) => {
    if (!r.ok) throw new Error(`${file}: ${r.status}`);
    return r.json();
  });

// ---- Footer year ----
const yearEl = document.getElementById('year');
if (yearEl) yearEl.textContent = String(new Date().getFullYear());
