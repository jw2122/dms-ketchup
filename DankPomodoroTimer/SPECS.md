# DMS Ketchup — Specifications

DMS Ketchup is a pomodoro timer plugin for DankMaterialShell.

- Plugin id: `dmsKetchup` (author: Virtual Wolf 369, version 1.4.1, MIT)
- Source repo: `~/.config/DankMaterialShell/plugins/.repos/39b15ac4661f477a/DankPomodoroTimer/`

## Files

| File | Role |
| --- | --- |
| `DMSKetchupWidget.qml` | Widget: bar pill (horizontal/vertical), popout, timer engine |
| `DMSKetchupSettings.qml` | Settings page + statistics dashboard |
| `DMSKetchupFullscreenModal.qml` | Break modal — one `PanelWindow` per screen (`Variants { model: Quickshell.screens }`) |
| `DMSKetchupLockWidget.qml` | Desktop/lock-screen widget (`desktop` surface, DMS 2.0 lock screen) |
| `DMSKetchupPreWarningToast.qml` | Pre-warning toast (primary screen only) |
| `translations/` | Motivational phrases, one `<lang>.json` per language (18 languages) |
| `dms-common/` | Design-system components copied from takeABreak (SettingsCard, SectionTitle, InfoTile, DankButton, ...) |
| `dms-common/BarInsets.js` | Shared bar/dock inset maths for the modal and the toast (plain JS library) |
| `plugin.json` / `qmldir` | Plugin manifest / QML module |

`plugin.json` declares both surfaces: the legacy `"component"` (bar widget, older DMS fallback) and `"components": { "widget": ..., "desktop": ... }`, which DMS 2.0's `_resolveComponentPaths` prefers. The `desktop` surface makes the timer available in both the desktop-widget and lock-screen-widget libraries (plugin desktop surfaces are listed in both; there is no lock-only flag).

## Timer model

- States: `work`, `shortBreak`, `longBreak` (stored in the `timerState` global var)
- Durations come from settings; the sliders store numbers, and every value goes through `toDuration()` (replaces `,` with `.`, `parseFloat`, rejects NaN/negative) so old string values (`"25"`, `"1,5"`) keep working
- Cross-instance / cross-screen state lives in `PluginGlobalVar`s (namespaced per plugin id, in-memory, reactive via `globalVarChanged`):
  - `remainingSeconds`, `totalSeconds`, `isRunning`, `timerState`, `completedPomodoros`, `timerOwnerId`
- Only the instance whose `instanceId` matches `timerOwnerId` runs the 1s `Timer`; every instance renders the shared values, so all screens show the same countdown
- Duration settings are only re-based by the owner instance: a second bar instance that loads with fallback durations must not rewrite a running session's `totalSeconds`/`remainingSeconds`
- Startup initialisation (session reset + auto-start) is claimed by exactly one instance through the shared `initAt` stamp; the other instance skips it. Without this the second instance reset the globals right after the first had auto-started, leaving a paused timer with no display

## Countdown display

- >= 60 s: minutes only (`MM`)
- < 60 s: seconds only, blinking — 800 ms on / 200 ms off; blink phase derived from `Date.now()` so all screens blink in sync

## Design & typography

- **Bar pill** text uses the DMS system font (`Theme.fontFamily`) and `Theme.fontWeightMedium`, so it matches every other bar widget instead of inheriting the plugin font.
- **Countdown numerals** (break modal, popout, lock widget) use `font.family: "monospace"` — the fontconfig system default monospace; `qs.Common` does not export `Fonts.systemMono` to plugins.
- **Modal quote / tip** also uses the system monospace font, one size below the subtitle.
- Break modal: centered card (`Theme.cornerRadiusXL`, `Theme.foregroundColor(Theme.cardSurface)`, 1 px `outlineMedium`), tinted state-icon badge, state-colored 96 px countdown, rounded progress track, primary "Continue working" button, subtle "Skip break" pill, and a soft top gradient tinted by the state color.
- State colors: `Theme.primary` (work), `Theme.info` (short break), `Theme.warning` (long break), `Theme.success` (break complete).
- Popout: monospace countdown with a rounded-cap Canvas ring, filled primary play/pause circle, tonal reset circle, intrinsic-width quick-action pills in a centered row.

## Break overlay controls

- The fullscreen break card has a pause/resume pill ("Pause break" / "Resume break") next to "Skip break"; `Space` toggles it and `Esc` closes/handles the card
- Pause/resume calls the engine's `toggleBreakPause()`; resuming after a pause re-pauses any media player that started playing in the meantime
- `Skip break` runs `stopBreakAndContinue()`: closes the modal and starts a running work session
- The overlay only opens when `fullscreenBreakModalEnabled` is on; otherwise the break runs as a background countdown

## Lock-screen / desktop widget

- `DMSKetchupLockWidget.qml` extends `DesktopPluginComponent` and renders a glass-style card: state dot + label (READY / FOCUS / PAUSED / BREAK COMPLETE / SHORT|LONG BREAK), large monospace countdown, progress bar, "Session N of M" footer, session length and a two-button control row. Default/minimum size is 340×180 / 240×140.
- It owns no timer: it reads the bar widget's shared `PluginGlobalVar`s (`remainingSeconds`, `totalSeconds`, `isRunning`, `timerState`, `completedPomodoros`, `timerDisplayActive`), so the lock screen always mirrors the live session.
- Controls call the bar widget's IPC target (`lockStart`, `lockPause`, `lockResume`, `lockContinue`) through `Quickshell.execDetached(["dms", "ipc", "call", "pomodoroTimer", ...])`, so there is still exactly one engine and one session owner. The primary 34 px circle is play/pause/start/continue in `Theme.primary` with `Theme.primaryText`; the tonal 34 px circle skips a running break.
- Button mapping: READY → start a running work session; work running → pause (= "as if the screen had just locked", see Away); work paused → resume and drop the away snapshot; break running → pause/resume the break; break running + skip → jump to the next work session; break complete → continue (clear the deferred modal, start work).
- The row is inert in the widget editor / lock-screen demo (`lockHost.demoMode`), so previews cannot drive the timer.
- On the lock screen it uses `lockHost.contentColor(...)`, `SettingsData.lockScreenFontFamily` for labels, and `Theme.readableSurface` / `Theme.outlineMedium` for the card; on the desktop it uses `Theme.surfaceText` and `Theme.fontFamily`.
- Idle state (no session) shows the configured work duration and "No session running"; session numbering starts at 1 and wraps to `sessionsPerLongBreak` after a full cycle.
- The user instance lives in `settings.json` → `lockScreenWidgetInstances` (`widgetType: "dmsKetchup"`); its position is stored in `session.json` → `desktopWidgetInstancePositions.lock_ketchup` (`_synced`, top-right, 340×180).

## Session flow

1. Work session completes -> `completedPomodoros` +1 -> `cycleCounter` saved **and** `completedPomodoros-YYYY-MM-DD` incremented by 1 -> notification (only when DND is off) + sound
2. Short break (every Nth is a long break, N = `sessionsPerLongBreak` setting, default 4; long iff `completedPomodoros % N === 0` after the increment) -> fullscreen modal on all screens
3. Manual continue (`requireManualContinueAfterBreak`) -> `startWork()`
4. Pre-warning toast `preWarningTime` (default 10 s) before a session ends

## Unlock behavior (`autoStartWorkOnUnlock`, default off)

All unlock paths (`SessionService` `sessionUnlocked` / `sessionResumed` signals, plus the loginctl probe fallback) funnel into `handleUnlocked()`. With the toggle on:

- Break finished while the screen was locked (deferred `"complete"` modal, or the modal opened behind the lock screen in the default loginctl-signal config) -> next work session starts immediately as a **running** session (the unlock toggle is the explicit user choice), no modal
- Break still counting down while locked -> modal re-opens as before (a live break is not cut short)
- Work session was **running** (e.g. resumed from the lock screen) -> it simply keeps running; the stale away snapshot is discarded (`cancelAway()`), so no reset/repeat happens
- Work session was **paused** -> today's away restore/repeat/reset logic applies; with `autoStartWorkOnUnlock` on, a paused work session is then resumed (remaining time kept) instead of staying paused. With the toggle off it stays paused.
- No session running at all (fresh boot, or after Reset) -> a fresh work session starts — "whenever I want to use the device"

## Startup behavior (`autoStartWorkOnStartup`, default off)

- When the shell starts (boot, SDDM login, `dms restart`) and no session is running (`timerDisplayActive` false), a fresh work session starts
- Deferred via `Qt.callLater` — the base `PluginComponent` populates `pluginData` in its own `Component.onCompleted`, which runs after the widget's, so an inline check reads empty settings
- The second bar instance skips auto-start: the first one claims the shared `initAt` stamp (`initializationOwner`) before it initialises or starts anything — no double start, no double sound

## Media pause

- Media is paused when a break countdown **actually starts running**: auto-started breaks (natural completion, cycle break, IPC) and the manual start (popout play button → `toggleTimer`)
- Every Mpris player with `isPlaying && canPause` is paused via `MprisController.availablePlayers`
- The quick-action buttons only **arm** a break (countdown at full duration, not running) — they do not pause media; the pause happens when the user presses play
- There is deliberately **no resume**: players stay paused until the user resumes them
- Setting `pauseMediaDuringBreaks` (default on) disables the pause entirely

## Motivational phrases

- The 11 break tips shown in the fullscreen modal are loaded from `translations/<lang>.json` (I18n table format: `{ "tips": { "<english>": "<translation>" } }`)
- 18 languages ship: en, de, es, fr, it, pt, nl, pl, ru, uk, bg, zh_CN, zh_TW, ja, ko, tr, hu, sv; anything else falls back to English
- Setting `phraseLanguage` (default `system`): `system` resolves the system locale through a candidate chain (full locale → hyphen variant → language → en); an explicit language loads `translations/<lang>.json` with an en fallback
- The chain is walked with `cat` via `Proc.runCommand`, because `FileView` does not report missing files reliably (it fires neither `onLoaded` nor `onLoadFailed` for a nonexistent path)
- `Proc.runCommand` keys callbacks by id: the id is suffixed with the widget `instanceId`, otherwise the two bar instances overwrite each other and only one loads the table
- The modal picks a random phrase when it opens (and again when the table changes) and hides the tip line when nothing loaded

## Cycle reset hour

- Setting `cycleResetHour` (slider 0–23, default 4): time of day when the break-cycle counter resets
- The counter persists under the `cycleCounter` state key (loaded at startup; migrated from `completedPomodoros-<today>` on first run)
- A 60 s check (plus the startup path) resets the counter once per day once the hour has passed; tracked by the `cycleResetDate` state key, so a shell started after the hour also resets
- Daily statistics still reset at midnight: sessions completed between midnight and the reset hour count toward the new calendar day but continue the previous day's cycle

## Notifications

- Push notifications (`notify-send -u normal <title> <body>`) are sent with a direct argv — no shell and no quote escaping; only when `SessionData.doNotDisturb` is off and the session is not locked — checked at send time, so manually enabled, scheduled (`doNotDisturbUntil`), or app-set DND suppresses them
- With `autoSetDND` on, the shell's own DND is cleared at session end (before the check), so the break notification still fires
- Sounds and in-app UI (pre-warning toast, fullscreen modal) are unaffected

## Sounds

- The player is resolved once per shell start (`pw-play` → `paplay` → `aplay` → `ffplay` → `play`) with one `Process` probe; sounds are then played by direct argv
- A sound requested while the probe is still running is kept in `pendingSoundPath` and played as soon as a player is known (no dropped chime)
- No shell string, no `which`, and no per-chime process tree beyond the player itself

## IPC

Target `pomodoroTimer`: `resetTimer`, `toggleTimer`, `startWork`, `startShortBreak`, `startLongBreak`, `status`, plus the lock-widget actions `lockStart`, `lockPause`, `lockResume`, `lockContinue`.

- `status` returns JSON with `state`, `running`, `remaining`, `total`, `displayActive`, `completed`, `modalOpen`, `modalPhase`, `locked`, `deferredPhase` — used for live verification and scripting
- `lockPause` pauses a work session that has no away snapshot yet and, when the session is locked, starts a fresh away snapshot first (same effect as locking at that moment). Breaks are only paused.
- `lockResume` cancels the away snapshot and (re)starts the countdown.
- `lockContinue` clears `deferredBreakModalPhase` / `breakModalArmed`, closes the break modal and starts a running work session, so unlocking afterwards cannot handle the break-complete state twice.

## Persistence

- Daily stats: `completedPomodoros-YYYY-MM-DD` keys — incremented by 1 on each completion (true daily counts; keys roll over at midnight)
- Cycle counter: `cycleCounter` (break-cycle position) and `cycleResetDate` (last daily reset) keys
- All in `~/.local/state/DankMaterialShell/plugins/dmsKetchup_state.json` (single JSON file; cache updated immediately, disk write debounced 150 ms)
- The `completedPomodoros` global var is the live cycle counter; the 7-day chart reads every day from disk

## Away / lock / suspend behavior

Departure (screen lock or lid close):

- **Work session**: timer pauses, state snapshotted (cause `lock`)
- **Break + screen lock**: nothing — breaks keep running while the machine stays on; a break completing while locked defers its modal to unlock
- **Break + suspend**: the break's remaining time is snapshotted — breaks are not paused, the away time counts against them
- **Pause from the lock screen**: treated as locking *again* at that moment — a fresh snapshot with a fresh timestamp replaces the old one (if no away snapshot exists yet, one is created)

Return:

| Phase | Time away | On return |
| --- | --- | --- |
| work | < `shortBreakDuration` | Countdown resumes where it left off |
| work | `shortBreakDuration` – `longBreakDuration` | Interrupted session does **not** count; the previous break type repeats (`counter > 0 && counter % 4 === 0` → long, else short), then a fresh work session starts ("session N again") |
| work | >= `longBreakDuration` | Cycle counter reset to 0 + fresh work session |
| break (suspend) | remaining − away > 0 | Break continues with the reduced remaining time |
| break (suspend) | remaining − away <= 0 | Break treated as finished -> break-complete flow (next work session) |

- Screen unlock / resume consumes the deferred break modal (the old `deferredBreakModalPhase` was written but never read — fixed)
- The deferred phase is **preserved** at lock time: a "complete" modal (break finished, waiting for continue) stays "complete" — it used to be hardcoded to "running", which re-opened a 0:00 running overlay with a Skip button instead of the continue screen. `handleUnlocked()` also upgrades a stale "running" phase to "complete" when the modal already re-opened as "complete" behind the lock screen.
- Detection: `SessionService` push signals (`preparingForSleep` → suspend; `sessionLocked` / `sessionUnlocked` / `sessionResumed`, driven by loginctl and on by default via `loginctlLockIntegration`) are the primary path. The 30 s `dms ipc call lock isLocked` probe runs only as a fallback when that integration is disabled, and only while a session is active (`timerDisplayActive`) — zero polling in the default configuration. Lid close while locked upgrades the cause to suspend.
- Away bookkeeping (`awayActive`, `awayStartMs`, `awaySnapshot`, `awayCause`) lives in shared `PluginGlobalVar`s, because both bar instances receive the lock/unlock signals. The first one to act wins and the other becomes a no-op, so a lock/unlock pair is applied exactly once.
- While `sessionLocked`, the pre-warning toast and desktop notifications are suppressed (they would land on the lock layer); sounds still play so an off-screen session/break change remains audible.

## Settings

- Durations use `SliderSettingPlus` sliders (take-a-break style): Work 5–60 min (default 25), Short Break 1–10 min (default 5), Long Break 1–30 min (default 15); stored as integers, sanitized by `toDuration()` (old string values keep working until the slider is moved once)
- Pre-warning lead time: slider 5–60 s
- Cycle reset time: slider 0–23 h (default 4)
- Sessions before long break: slider 1–10 (default 4) — the cycle length; the popout shows "Next long break after N more"
- Start pomodoro on unlock: toggle (default off) — Behavior card
- Start pomodoro on startup: toggle (default off) — Behavior card; starts a session when the shell starts with none running
- Pause media during breaks: toggle (default on) — Behavior card
- Phrase language: selection, "System language" (default) + the 18 shipped languages — Phrases card

## Statistics dashboard (settings)

Today / This Week / Total (365 days) / Best Day / Top 5 days; Refresh and Reset Stats buttons. Reads the same per-day keys as the widget in a **single pass** over the 365-day window; refreshed on `pluginStateChanged` / `globalVarChanged` through a 150 ms debounce timer (a completion writes several keys in one burst). Reset uses `PluginService.clearPluginState` when available instead of hundreds of individual key removals.

## Runtime cost (v1.4.1)

- One global write per second at most while a session is visible; `showSecondsOnly` only writes when the value actually changes (it used to emit `globalVarChanged` every second)
- No polling in the default configuration: the lock probe runs only when `loginctlLockIntegration` is disabled, only while a timer is visible, and every 30 s instead of every 10 s
- No periodic shell spawns: sounds and notifications use one-shot player resolution and direct argv
- The settings statistics page does one 365-key pass per refresh, debounced to 150 ms, instead of a separate pass per metric and per day
- Desktop/lock widget reads reactive `pluginData` instead of duplicating the duration values
