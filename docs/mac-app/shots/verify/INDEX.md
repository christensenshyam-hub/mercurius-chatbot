> **Superseded by step 05.** `../05/` (not committed) has the full set, taken on 2026-10-20 with the display kept awake behind the lock screen, so every window is drawn but inactive; `../../key-shots/` has 11 of them, compressed and committed. `05-review-fixes.md` §3 explains. The commands below still work; on an unlocked Mac drop `ACTIVATE=NO` so the harness photographs the key window.

# Verification screenshots: not taken

**This folder has no pictures yet.** The Mac's screen was locked for the whole verification run, from 00:47 to 01:28 on 2026-10-20 (`CGSSessionScreenIsLocked` = true). While the screen is locked, the window server draws nothing for the app's window. Every capture came back all black, at 2306 × 1442 px instead of 2560 × 1600. I waited 35 minutes for an unlock that didn't come. Blank pictures aren't committed. The step 02 set in `../02/` is still the latest set of real pictures.

Note: `mac-snapshots.sh` reported those blank captures as `ok` (finding 2 in `../../VERIFY.md`). Check that each picture actually shows the window.

## To take the set (screen unlocked, about 12 minutes)

From `ios/`, after a Debug build of `MercuriusMac` into `/private/tmp/merc-mac-dd`:

```bash
# Every main state, light + dark at 1280×800 and at the 860×600 minimum;
# Settings and Help light + dark. Nothing may listen on :3000 here: the
# chat-failed shot relies on the local server being absent.
scripts/mac-snapshots.sh ../docs/mac-app/shots/verify

# The chat in Debate and Discussion: the switch asks the server first, so
# start a local server on :3000 that answers POST /api/mode with
# {"mode": …} (the real one with ANTHROPIC_MOCK=1, or any stub), then:
scripts/mac-snapshots.sh ../docs/mac-app/shots/verify chat-debate chat-discussion
```

Each window state is written four ways: `<state>.png` (1280 × 800, light), `-dark`, `-min` (860 × 600) and `-min-dark`. To keep the repo small, step 02 halved the variants before committing them; do the same here.

## The set

| State | Shot | What it shows |
|---|---|---|
| Gate | `gate-meet`, `gate-age`, `gate-consent` | The first-run flow in the detail column, sidebar hidden: meeting Merc, the age pop-up, the data-use agreement. `.controls.txt` lists the pop-up and checkbox the capture can't draw. |
| Today | `today` | Merc's welcome and the next stop. |
| Path | `path` | The next stop's unit on the learning path, in the 560 pt column. |
| Lesson | `lesson-intro`, `lesson` | Unit 1 Lesson 1: the intro, then the recorded replay (no network). |
| Lesson complete | `lesson-complete` | The centred celebration card (`-ForceCelebrate`; never counts as progress). |
| Chat, Socratic | `chat`, `chat-thread`, `chat-typing`, `chat-failed` | The empty chat, a long thread, Shift-Return typing (`chat-typing.composer.txt`), and a failed send with Retry. |
| Chat, mode switch | `chat-mode-intro` | Debate's one-time description sheet, which a first switch shows (new, `efc17bd`). |
| Chat, Debate / Discussion | `chat-debate`, `chat-discussion` | The chat after the toolbar or ⌘2/⌘3 switch (new, `efc17bd`; needs the local server above). |
| Unit check | `unit-test` | The unit test's review stage. |
| Crisis support | `crisis` | 988, HOME to 741741 and 911 as large selectable numbers with Copy, then the FaceTime/Messages links. |
| Settings | `settings-general`, `settings-privacy`, `settings-about` | The Settings window: General; Privacy with Delete my data and the consent withdrawal; About. |
| Help | `help`, `help-mac`, `help-support` | The Help window's three sections. |

What the run did prove without pictures (see `../../VERIFY.md` §5):

- Every gated launch started, showed its window and quit by itself. The control dump showed the gate, with the sidebar's list hidden.
- Opened on the gate, the Settings window was the 420 × 272 pt placeholder.
- `chat-debate` and `chat-discussion` sent `POST /api/mode` with `debate` and `discussion` to the local server. `chat-mode-intro` sent none, because the description sheet comes first.
