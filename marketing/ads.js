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
 *   - in the phone/tablet strips, a card scrolls fully into view when
 *     keyboard focus enters it.
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
    if (frame.dataset.captionId) video.setAttribute('aria-describedby', frame.dataset.captionId);
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
  // in. Bring the whole card into the strip instead.
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)');
  document.querySelectorAll('.reel-row').forEach((row) => {
    row.addEventListener('focusin', (e) => {
      if (row.scrollWidth <= row.clientWidth + 1) return;
      const card = e.target.closest('.reel');
      if (!card) return;
      const c = card.getBoundingClientRect();
      const v = row.getBoundingClientRect();
      if (c.left >= v.left - 1 && c.right <= v.right + 1) return;
      card.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: reduce && reduce.matches ? 'auto' : 'smooth' });
    });
  });
})();
