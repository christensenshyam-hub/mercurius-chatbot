/**
 * Mercurius AI — reel players (homepage "See it in 30 seconds" + /ads)
 *
 * Progressive enhancement. Each reel ships as a poster image, a play button
 * and, inside <noscript>, a native <video controls preload="none">, so with
 * JS off the page shows plain native players (the posters and play buttons
 * are hidden by a <noscript> style in the page head).
 *
 * With JS:
 *   - nothing loads until the visitor presses play; then a <video> is made
 *     (muted, inline, with native controls) and starts;
 *   - one reel plays at a time: starting one pauses the others, and a reel
 *     pauses when it scrolls out of view;
 *   - "Turn sound on / off" under the reel toggles the sound (the native
 *     controls' mute button stays in sync);
 *   - nothing autoplays, ever;
 *   - in the phone/tablet strips, a card scrolls fully into the strip when
 *     keyboard focus enters it, and the focused control stays clear of the
 *     sticky header.
 *
 * No dependencies. Loaded with `defer`.
 */
(() => {
  'use strict';

  const frames = Array.from(document.querySelectorAll('[data-reel]'));
  if (!frames.length) return;

  const videos = [];
  // Pause a reel once its frame has scrolled out of view. The frames are
  // watched from page load (a just-inserted <video> can report "not
  // intersecting" on its first callback, which would pause it at once).
  const watcher = 'IntersectionObserver' in window
    ? new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        const video = entry.target.querySelector('video.reel-video');
        if (video && !entry.isIntersecting && !video.paused) video.pause();
      });
    })
    : null;

  const pauseOthers = (current) => {
    videos.forEach((v) => { if (v !== current && !v.paused) v.pause(); });
  };

  const label = (video) => (video.muted ? 'Turn sound on' : 'Turn sound off');

  function build(frame) {
    const poster = frame.querySelector('.reel-poster');
    const play = frame.querySelector('[data-reel-play]');
    const card = frame.closest('.reel');
    const sound = card ? card.querySelector('[data-reel-sound]') : null;

    const video = document.createElement('video');
    video.className = 'reel-video';
    video.controls = true;
    video.muted = true;
    video.defaultMuted = true;
    video.playsInline = true;
    video.setAttribute('playsinline', '');
    video.preload = 'auto';
    if (frame.dataset.width) video.width = Number(frame.dataset.width);
    if (frame.dataset.height) video.height = Number(frame.dataset.height);
    if (poster) video.poster = poster.currentSrc || poster.src;
    if (frame.dataset.titleId) video.setAttribute('aria-labelledby', frame.dataset.titleId);
    if (frame.dataset.describedby) video.setAttribute('aria-describedby', frame.dataset.describedby);
    const source = document.createElement('source');
    source.src = frame.dataset.src;
    source.type = 'video/mp4';
    video.appendChild(source);

    video.addEventListener('play', () => {
      pauseOthers(video);
      frame.classList.add('is-playing');
    });
    if (sound) {
      video.addEventListener('volumechange', () => { sound.textContent = label(video); });
      sound.addEventListener('click', () => {
        video.muted = !video.muted;
        sound.textContent = label(video);
      });
      sound.textContent = label(video);
      sound.hidden = false;
    }

    frame.appendChild(video);
    if (poster) poster.hidden = true;
    if (play) play.hidden = true;
    videos.push(video);
    return video;
  }

  function start(frame) {
    const video = frame.querySelector('video.reel-video') || build(frame);
    pauseOthers(video);
    const playing = video.play();
    // If the browser refuses (no user gesture), the native controls are there.
    if (playing && typeof playing.catch === 'function') playing.catch(() => {});
    // The play button is gone; keep keyboard users on the player itself.
    video.focus({ preventScroll: true });
  }

  frames.forEach((frame) => {
    const play = frame.querySelector('[data-reel-play]');
    if (play) play.addEventListener('click', () => start(frame));
    if (watcher) watcher.observe(frame);
  });

  // On phones and tablets each row of reels is a horizontal strip. Browsers
  // don't scroll a control into view on focus while any part of it shows, so
  // Tab could land on the next card's play button while only its edge peeks
  // in. Bring the whole card into the strip instead. Only the strip scrolls
  // sideways: a card can be taller than a phone screen, so the page is
  // scrolled just enough to keep the focused control itself clear of the
  // sticky header and the bottom edge.
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');
  const header = document.querySelector('.site-header');
  const keyboard = (el) => {
    try { return el.matches(':focus-visible'); } catch (err) { return true; }
  };
  document.querySelectorAll('.reel-row').forEach((row) => {
    row.addEventListener('focusin', (e) => {
      const behavior = reduce && reduce.matches ? 'auto' : 'smooth';
      const card = e.target.closest('.reel');
      if (card && row.scrollWidth > row.clientWidth + 1) {
        const c = card.getBoundingClientRect();
        const v = row.getBoundingClientRect();
        const pad = parseFloat(getComputedStyle(row).scrollPaddingLeft) || 0;
        if (c.left < v.left + pad - 1) row.scrollBy({ left: c.left - (v.left + pad), behavior });
        else if (c.right > v.right - pad + 1) row.scrollBy({ left: c.right - (v.right - pad), behavior });
      }
      if (!keyboard(e.target)) return;
      const t = e.target.getBoundingClientRect();
      const top = Math.max(0, header ? header.getBoundingClientRect().bottom : 0) + 8;
      const bottom = window.innerHeight - 8;
      if (t.top < top) window.scrollBy({ top: t.top - top, behavior });
      else if (t.bottom > bottom && t.height <= bottom - top) window.scrollBy({ top: t.bottom - bottom, behavior });
    });
  });
})();
