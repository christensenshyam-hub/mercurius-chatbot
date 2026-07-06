# Handoff: Mercurius — "Merc" Mascot & Playful Lesson Screen

## Overview
This package covers two things for the **Mercurius** learning app:
1. **Merc** — an animated, winged-helmet mascot character (a stylized Hermes/Mercury) who lives on screen and reacts to events. He is the centerpiece.
2. The **Playful lesson-chat screen** that he lives on (a redesign of the existing lesson view, in the "Duolingo-warmth + Apple-restraint" direction).

## About the Design Files
The files in this bundle are **design references built in HTML/CSS** — prototypes that show the intended look, geometry, and motion. They are **not production code to copy verbatim.** Your task is to **recreate these designs in the target app's existing environment** (React Native / SwiftUI / React web / whatever Mercurius is built in), using its established components, theming, and animation tooling. If no environment exists yet, choose the most appropriate stack for the platform and implement there.

The mascot in particular is drawn with absolutely-positioned `<div>`s + CSS gradients/clip-paths purely so it could be prototyped quickly. **Do not ship the div-soup.** See "Implementing Merc" below for the recommended production approaches (SVG component or Lottie).

> ⚠️ These `.dc.html` files are "Design Component" prototypes and need `support.js` (included) to render. Open them in a browser from this folder. They are for visual reference; the README is the source of truth for specs.

## Fidelity
**High-fidelity.** Final colors, gradient, proportions, typography, and animation timings are specified exactly below. Recreate pixel-faithfully, then swap in your codebase's design-system primitives where they exist (type ramp, spacing, surfaces).

---

## Design Tokens

### Brand color — the Mercurius gradient
A blue → violet → magenta diagonal, taken from the app logo. Used on the send button, progress bar, and the mascot's skin/head.
```
--merc-gradient: linear-gradient(135deg, #3D5AFF 0%, #7C3AED 56%, #B53BE8 100%);
--merc-blue:    #3D5AFF
--merc-violet:  #7C3AED   /* primary accent */
--merc-magenta: #B53BE8
```

### Accent / UI
```
--accent:            #6C5CE7   /* light-mode indigo accent (labels, "Done", icons) */
--accent-dark:       #A99BFF   /* dark-mode accent (raise lightness for contrast) */
--accent-soft-bg:    rgba(108,92,231,.09)   /* tinted callout fill, light */
--accent-soft-bg-dk: rgba(124,108,255,.16)  /* tinted callout fill, dark */
--gold:              linear-gradient(90deg,#e9c768,#caa23a)  /* Merc's belt cord */
```

### Surfaces
```
LIGHT  bg #F3F4FF · card/bubble #FFFFFF · text #1C1B2E · subtext #7D7A93
DARK   bg #0E0F1E · card/bubble #1A1B30 · text #ECEBFA · subtext #8B88A8
        dark also has a top-right radial glow: radial-gradient(circle, rgba(124,58,237,.3), transparent 70%)
```

### Mascot ink / detail colors
```
ink (eyes, brows, mouth):  #241B5E   (brows slightly lighter: #2A1F63)
helmet dome:               linear-gradient(150deg,#5a23c9,#8d2fd6)
wings:                     blue→white feathers, e.g. linear-gradient(120deg,#2f56f5,#86a6ff)
toga / chiton:             linear-gradient(165deg,#ffffff,#ece8ff)
sparkle:                   linear-gradient(135deg,#8fb3ff,#cf8bff)
```

### Typography
- **Font family:** `Nunito` (Google Fonts), weights 400/600/700/800/900. This screen leans on the heavy weights — titles 800–900, body 700.
- Lesson title: 22px / weight 900 / line-height 1.18 / letter-spacing −0.01em
- Eyebrow (UNIT 01 · LESSON 1): 11px / 800 / uppercase / letter-spacing .3px / accent color
- Subtitle: 13px / 700 / subtext color
- Message body: 13px / 700 / line-height 1.55
- Callout (check-question): 12.5px / 800 / italic / `#4a3fb0` (light)

### Radius / spacing
```
phone screen radius 42px · message bubble 8px 24px 24px 24px (speech-tail top-left)
callout card 16px · composer pill 24px · progress bar 5px
input/CTA height 42px · send button 42px circle
```

---

## Merc — the mascot

### Character
A chibi-but-**teenaged** (not baby) Hermes: composed posture, leaner build, a winged petasos helmet with a white brim, a white toga (chiton) draped over one shoulder as a diagonal sash, a gold cord belt, bare arms/legs, and a twinkling 4-point sparkle. Skin is the brand gradient. Face is the **"Stoic"** treatment: thin flat eyebrows, solid dark almond/oval eyes with a single catch-light, and a small neutral line mouth — calm and serious.

### Proportions (intrinsic art box 160 × 180, top-left origin)
- **Head:** x52 y26, 56×62, border-radius `48% 48% 44% 44% / 50% 50% 52% 52%`, brand gradient
- **Helmet dome:** x55 y17, 50×34, `linear-gradient(150deg,#5a23c9,#8d2fd6)`
- **Helmet brim:** x46 y45, 68×10, white, rotated −4°
- **Wings:** one per side at the helmet, 4 stacked feather "teardrops" each (`border-radius:50% 50% 50% 5px`), blue→white, fanning up-and-out; left origin bottom-right, right origin bottom-left
- **Eyes (stoic):** two solid `#241B5E` rounded ovals 7×11 (radius 5px) at x64/x89, y56, each with a 2.6px white catch-light top-right
- **Brows:** flat bars 11×3, `#2A1F63`, at x61/x88, y53
- **Mouth:** neutral line 9×3, `#241B5E`, centered, y76
- **Neck → torso:** white chiton x52 y94, 56×62; diagonal himation sash (rotated 24°); bare shoulder (gradient) peeking top-left; gold belt at y128 with a round knot; two bare arms (left static, right state-driven); two legs + feet at the bottom
- **Sparkle:** 4-point star via `clip-path:polygon(50% 0,59% 41%,100% 50%,59% 59%,50% 100%,41% 59%,0 50%,41% 41%)`, top-right, twinkles

### Idle ambient motion (always on)
- **Body bob:** `translateY 0 → −7px` + `rotate −1° → 1°`, 3.4s ease-in-out, infinite
- **Wings flutter:** rotate ±~15–17°, 1.6s ease-in-out, infinite (mirrored per side)
- **Blink:** `scaleY 1 → .1` briefly at ~95% of a ~5s loop
- **Sparkle twinkle:** scale .55 ↔ 1.05 + rotate 45° + opacity .3 ↔ 1, ~2.6s

### States (the `state` prop)
Merc takes one prop, `state`, one of: `idle | wave | happy | thinking | celebrate | sleep`. Each sets a body animation, the right-arm animation, the eye shape, the mouth, and optional effects:

| state | body motion | right arm | eyes | mouth | effect |
|---|---|---|---|---|---|
| **idle** | gentle bob 3.4s | rest (down) | solid ovals | neutral line | — |
| **wave** | quicker bob 1.8s | wave, rotate 14°↔−22° @0.7s | solid ovals | neutral line | — |
| **happy** | bounce −12px @0.9s | small wave @1.1s | upward arcs ∩ | open grin (pink tongue) | — |
| **thinking** | slow lean/tilt −6°↔−8° @3.4s | rest | solid ovals | small "o" | 3 pulsing dots above head (stagger .2s) |
| **celebrate** | jump −18px @0.7s | cheer, rotate −32°↔−98° @0.5s | upward arcs ∩ | open grin | confetti + sparkle "pop" burst (7 chips, stagger) |
| **sleep** | droop + slow sway @4.2s | rest | closed downward arcs ∪ | tiny "o" | rising "z z z" (stagger .8s) |

Exact keyframes are in `Merc.dc.html` (`@keyframes merc-bob / merc-bounce / merc-jump / merc-lean / merc-snooze / merc-wave / merc-cheer / merc-dot / merc-zzz / merc-pop / merc-blink / merc-twinkle / merc-wingL / merc-wingR`).

### Implementing Merc in production (recommended)
Pick ONE:
1. **SVG + CSS/JS animation (recommended for web/React):** Re-draw the shapes as an SVG (or keep them as positioned elements) inside one `<Merc state="...">` component. Drive ambient loops with CSS keyframes; switch `state` to swap expression layers and the per-state body/arm animation. Expose `state` as the only prop. This matches the prototype 1:1 and stays crisp at any size.
2. **Lottie (recommended for native / richest motion):** Have the geometry + timings here animated into a Lottie JSON (one comp with markers per state, or one file per state). Mounts identically on web and native; designers can iterate without code. Use this if you want the celebrate/sleep effects to feel more organic than CSS allows.
3. **Sprite/asset set:** least flexible; only if your platform can't do 1 or 2.

Keep it as a **single component with a `state` enum** regardless of approach. Size it by scaling the 160×180 box (`transform: scale()` or width/height); it scales cleanly.

### Wiring states to app events (intended behavior)
- App open / lesson enter → `wave` (~1.8s) then settle to `idle`
- Assistant reply is generating/streaming → `thinking`
- User answers a check-question correctly → `celebrate` (~2s) then `idle`
- No interaction for ~60s → `sleep` until next input (tapping Merc or typing wakes him → `idle`)
- Default at all other times → `idle`

**A working reference implementation of exactly this logic is in `Mercurius Lesson.dc.html`** — see its logic class for the full state machine: `componentDidMount` (wave→idle), `send()`/`streamMerc()` (thinking while a reply types out, then idle), `answer(correct)` (celebrate then idle, with a wrong-answer retry path), and `resetIdle()`/`wake()` (the inactivity→sleep timer; demo uses 12s, production should use ~60s via `IDLE_MS`). Recreate this state machine in your app; the mascot component just consumes the resulting `state`.

---

## Screen — Playful Lesson Chat

### Purpose
The lesson view where the learner reads Merc's tutoring messages and replies. Merc is a persistent presence at the top.

### Layout (top → bottom, full-height phone screen)
1. **Status bar** (system).
2. **Header** (padding 22px): eyebrow `UNIT 01 · LESSON 1` (accent) with a **Done** text button (accent) right-aligned; lesson **title** (22/900); **subtitle** (13/700 subtext); then a **progress bar** — a 8px-tall track (`rgba(108,92,231,.16)`) with a gradient fill (the brand gradient) at the current %, and a `5/8` count label (12/800 accent) to its right.
3. **Merc hero zone:** Merc centered over a soft radial halo (`radial-gradient(ellipse, rgba(124,58,237,.16), transparent 70%)`), `state="idle"`, scaled to ~150px tall.
4. **Message:** a small presence line — green dot (`#22C55E`, with a soft ring) + `Merc · just now` (11.5/800 subtext) — above a chat bubble. Bubble: white (light) / `#1A1B30` (dark), radius `8px 24px 24px 24px`, padding 16px, soft shadow. Body text 13/700. Inside, the **check-question callout**: a tinted rounded card (radius 16, fill `--accent-soft-bg`) with italic 12.5/800 text in `#4a3fb0` (light) / `#c3b8ff` (dark).
5. **Composer** (padding 16px, fades into bg): a photo/attach icon (stroked, accent), an input pill ("Ask Mercurius…", 13.5/700 placeholder, inset 1.5px accent ring), and a **send button** — 42px circle filled with the brand gradient, white up-arrow.

### Light & dark
Both are specified in `Mercurius Playful.dc.html`. Dark adds the top-right violet glow and swaps to the dark surface/accent tokens above. Support both via your theme system.

### Interactions & behavior
- **Done** → exits the lesson.
- Tapping send → submits the input; while the assistant responds, Merc → `thinking`.
- Progress bar reflects lesson completion (`completed/total`).
- All Merc ambient animation runs continuously; respect `prefers-reduced-motion` (drop the loops, keep static poses).

### State management (screen)
- `messages[]` (role, text, timestamp)
- `isGenerating` (drives Merc `thinking`)
- `lessonProgress { completed, total }`
- `idleTimer` (drives Merc `sleep`)
- `mercState` derived from the above

---

## Mascot Placements (Duolingo-inspired)
Merc changes *where* he sits per moment. Build these as positioning variants of the one `<Merc>` component (it just renders into a differently-placed/scaled container):

| Placement | When | How |
|---|---|---|
| **Speech bubble** | Lesson intro | Merc grounded bottom-left, a tailed white bubble above-right delivering copy, primary CTA bottom-right. |
| **Bottom anchor** | Live chat | Merc peeks up from *behind* the composer (clipped at its top), persistent while messaging. |
| **Corner peek** | Reading long content | Small Merc tucked into the header's top-right corner, out of the way. |
| **Celebration takeover** | Correct answer / milestone | A bottom sheet slides up over a dimmed screen; Merc (`state="celebrate"`) overflows its top edge. |
| **Floating helper** | Exercises / quizzes | A 64px circular FAB (Merc clipped to a circle) bottom-right with a "Need a hint?" tag; tap toggles a hint bubble. |

These are **not exclusive** — the intended system is: corner-peek while reading → bottom-anchor in chat → floating-helper during exercises → celebration-takeover on a win → speech-bubble for intros. See `Merc Positions.dc.html` for all five laid out, and `Mercurius Flow.dc.html` for them sequenced in a real lesson.

---

## Assets
- **No raster assets.** The mascot, icons (photo, send arrow), sparkle, and progress bar are all vector/CSS. Recreate the mascot per "Implementing Merc"; the photo & send-arrow are simple stroked SVG icons (use your icon set's equivalents).
- **Font:** Nunito (Google Fonts) — or your app's nearest rounded-sans if you standardize elsewhere.
- **Logo** (source inspiration for Merc): the Mercurius winged-helmet bust in the brand gradient. Use your existing brand asset; Merc should feel like its friendly mascot cousin, not a copy.

## Files in this bundle
- `Merc.dc.html` — the mascot component (all 6 states, all keyframes). **Primary visual reference.**
- `Mercurius Flow.dc.html` — **the full playable lesson**: intro → chat → exercise → celebrate → done, moving Merc through every placement with live reactions (wave / thinking-while-streaming / hint / wrong-answer / celebrate). **This is the primary reference** — its logic class is the complete screen-flow + mascot state machine to mirror.
- `Mercurius Lesson.dc.html` — a tighter single-screen prototype (chat + check-question) focused on the event→state wiring (open→wave, streaming→thinking, correct→celebrate, idle→sleep).
- `Merc Positions.dc.html` — the five placements laid out side by side for reference.
- `Merc Reactions.dc.html` — interactive showcase: tap buttons to see each state; also a 6-up reference grid.
- `Mercurius Playful.dc.html` — the lesson screen in light + dark, with Merc embedded.
- `support.js` — runtime required to open the `.dc.html` files in a browser.

To preview: open any `.dc.html` from this folder in a browser (they load `support.js` from the same folder).
