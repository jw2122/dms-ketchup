# DMS Ketchup — Specifications

DMS Ketchup is a pomodoro timer plugin for DankMaterialShell.

- Plugin id: `dmsKetchup` (author: Virtual Wolf 369, version 1.2.0, MIT)
- Source repo: `~/.config/DankMaterialShell/plugins/.repos/39b15ac4661f477a/DankPomodoroTimer/`

## Files

| File | Role |
| --- | --- |
| `DMSKetchupWidget.qml` | Widget: bar pill (horizontal/vertical), popout, timer engine |
| `DMSKetchupSettings.qml` | Settings page + statistics dashboard |
| `DMSKetchupFullscreenModal.qml` | Break modal — one `PanelWindow` per screen (`Repeater { model: Quickshell.screens }`) |
| `DMSKetchupPreWarningToast.qml` | Pre-warning toast (primary screen only) |
| `translations/` | Motivational phrases, one `<lang>.json` per language (18 languages) |
| `dms-common/` | Design-system components copied from takeABreak (SettingsCard, SectionTitle, InfoTile, DankButton, ...) |
| `plugin.json` / `qmldir` | Plugin manifest / QML module |

## Timer model

- States: `work`, `shortBreak`, `longBreak` (stored in the `timerState` global var)
- Durations come from settings as **strings** (`"25"`, `"5"`, `"15"`); `toDuration()` sanitizes (replaces `,` with `.`) before `parseFloat`
- Cross-instance / cross-screen state lives in `PluginGlobalVar`s (namespaced per plugin id, in-memory, reactive via `globalVarChanged`):
  - `remainingSeconds`, `totalSeconds`, `isRunning`, `timerState`, `completedPomodoros`, `timerOwnerId`
- Only the instance whose `instanceId` matches `timerOwnerId` runs the 1s `Timer`; every instance renders the shared values, so all screens show the same countdown

## Countdown display

- >= 60 s: minutes only (`MM`)
- < 60 s: seconds only, blinking — 800 ms on / 200 ms off; blink phase derived from `Date.now()` so all screens blink in sync

## Session flow

1. Work session completes -> `completedPomodoros` +1 -> `cycleCounter` saved **and** `completedPomodoros-YYYY-MM-DD` incremented by 1 -> notification (only when DND is off) + sound
2. Short break (every Nth is a long break, N = `sessionsPerLongBreak` setting, default 4; long iff `completedPomodoros % N === 0` after the increment) -> fullscreen modal on all screens
3. Manual continue (`requireManualContinueAfterBreak`) -> `startWork()`
4. Pre-warning toast `preWarningTime` (default 10 s) before a session ends

## Unlock behavior (`autoStartWorkOnUnlock`, default off)

All unlock paths (`SessionService` `sessionUnlocked` / `sessionResumed` signals, plus the loginctl probe fallback) funnel into `handleUnlocked()`. With the toggle on:

- Break finished while the screen was locked (deferred `"complete"` modal, or the modal opened behind the lock screen in the default loginctl-signal config) -> next work session starts immediately (respects `autoStartPomodoros`), no modal
- Break still counting down while locked -> modal re-opens as before (a live break is not cut short)
- Work session was running -> away logic restores/resumes it as before
- No session running at all (fresh boot, or after Reset) -> a fresh work session starts — "whenever I want to use the device"

## Startup behavior (`autoStartWorkOnStartup`, default off)

- When the shell starts (boot, SDDM login, `dms restart`) and no session is running (`timerDisplayActive` false), a fresh work session starts
- Deferred via `Qt.callLater` — the base `PluginComponent` populates `pluginData` in its own `Component.onCompleted`, which runs after the widget's, so an inline check reads empty settings
- The second bar instance skips (the first one sets `timerDisplayActive`) — no double start, no double sound

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
- The modal picks a random phrase from the loaded table (re-picks when the table changes) and hides the tip line when nothing loaded

## Cycle reset hour

- Setting `cycleResetHour` (slider 0–23, default 4): time of day when the break-cycle counter resets
- The counter persists under the `cycleCounter` state key (loaded at startup; migrated from `completedPomodoros-<today>` on first run)
- A 60 s check (plus the startup path) resets the counter once per day once the hour has passed; tracked by the `cycleResetDate` state key, so a shell started after the hour also resets
- Daily statistics still reset at midnight: sessions completed between midnight and the reset hour count toward the new calendar day but continue the previous day's cycle

## Notifications

- Push notifications (`notify-send`) are only sent when `SessionData.doNotDisturb` is off — checked at send time, so manually enabled, scheduled (`doNotDisturbUntil`), or app-set DND suppresses them
- With `autoSetDND` on, the shell's own DND is cleared at session end (before the check), so the break notification still fires
- Sounds and in-app UI (pre-warning toast, fullscreen modal) are unaffected

## IPC

Target `pomodoroTimer`: `resetTimer`, `toggleTimer`, `startWork`, `startShortBreak`, `startLongBreak`.

## Persistence

- Daily stats: `completedPomodoros-YYYY-MM-DD` keys — incremented by 1 on each completion (true daily counts; keys roll over at midnight)
- Cycle counter: `cycleCounter` (break-cycle position) and `cycleResetDate` (last daily reset) keys
- All in `~/.local/state/DankMaterialShell/plugins/dmsKetchup_state.json` (single JSON file; cache updated immediately, disk write debounced 150 ms)
- The `completedPomodoros` global var is the live cycle counter; the 7-day chart reads every day from disk

## Away / lock / suspend behavior

Departure (screen lock or lid close):

- **Work session**: timer pauses, state snapshotted
- **Break + screen lock**: nothing — breaks keep running while the machine stays on; a break completing while locked defers its modal to unlock
- **Break + suspend**: the break's remaining time is snapshotted — breaks are not paused, the away time counts against them

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

Today / This Week / Total (365 days) / Best Day / Top 5 days; Refresh and Reset Stats buttons. Reads the same per-day keys as the widget; refreshed on `pluginStateChanged` / `globalVarChanged` and every 10 s.
