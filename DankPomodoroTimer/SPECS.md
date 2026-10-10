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

1. Work session completes -> `completedPomodoros` +1 -> saved under `completedPomodoros-YYYY-MM-DD` -> notification + sound
2. Short break (every 4th is a long break) -> fullscreen modal on all screens
3. Manual continue (`requireManualContinueAfterBreak`) -> `startWork()`
4. Pre-warning toast `preWarningTime` (default 10 s) before a session ends

## IPC

Target `pomodoroTimer`: `resetTimer`, `toggleTimer`, `startWork`, `startShortBreak`, `startLongBreak`.

## Persistence

- Daily stats: `completedPomodoros-YYYY-MM-DD` keys in `~/.local/state/DankMaterialShell/plugins/dmsKetchup_state.json` (single JSON file; cache updated immediately, disk write debounced 150 ms)
- The `completedPomodoros` global var is the live mirror: loaded at startup and on day rollover (60 s check)

## Away / lock / suspend behavior (work sessions only — running or paused)

| Time away | On return |
| --- | --- |
| < 5 min (`shortBreakDuration`) | Countdown resumes where it left off |
| 5–15 min | Fresh work session, auto-starts; daily counter unchanged |
| >= 15 min (incl. 8 h+) | Daily counter reset to 0 + fresh work session, auto-starts |

Detection: `SessionService` (`preparingForSleep`, `sessionLocked` / `sessionUnlocked` / `sessionResumed`) plus the 1 s `dms ipc call lock isLocked` probe as fallback.

## Statistics dashboard (settings)

Today / This Week / Total (365 days) / Best Day / Top 5 days; Refresh and Reset Stats buttons. Reads the same per-day keys as the widget; refreshed on `pluginStateChanged` / `globalVarChanged` and every 10 s.
