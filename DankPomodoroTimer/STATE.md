# DMS Ketchup — Project State

## Git

- Repo: `~/.config/DankMaterialShell/plugins/.repos/39b15ac4661f477a/` (branch `main`)
- Remote: https://github.com/virtualwolf-369/dms-ketchup
- Commits: `ebdecf3` (countdown/overlay/pre-warning), `bcf42ee` (statistics dashboard + dms-common), `5d9c474` (fix progress bar staying gray)

## Environment

- `dmsKetchup` enabled in `~/.config/DankMaterialShell/plugin_settings.json`
  - Current values are the user's active test values: `workDuration: "1"`, `shortBreakDuration: "1"`, `longBreakDuration: "1,5"` (comma decimal — handled by `toDuration()`)
- `dankPomodoroTimer` (Avenge Media v1.1.6, installed first-party at `plugins/DankPomodoroTimer/`) — disabled; reference implementation for multi-screen display
- `dmsPomodoro` and `pomodoroCopy` also enabled (other pomodoro plugins)
- dmsKetchup and dankPomodoroTimer share the IPC target `pomodoroTimer` — only one may be enabled at a time

## Reference paths (running shell)

`/run/user/1000/danklinux-shell/3f15ae07e999b609/` — live shell sources:

- `Services/PluginService.qml` — PluginGlobalVar storage (`globalVars[pluginId][varName]`), plugin state cache
- `Services/SessionService.qml` — lock / suspend signals
- `Widgets/PluginGlobalVar.qml`, `Modules/Plugins/PluginSettings.qml`
- `PLUGINS/README.md` — plugin API docs

## Commands

- QML changes require a shell restart: `dms restart` (plugins do NOT hot-reload)
- Lint: `qmllint <file>` (v1.0 — old; `DMSKetchupWidget.qml` exits 255 with no message, pre-existing; settings + modal exit 0)
- Logs: `journalctl --user -u '*dms*'`
- Manual test: `dms ipc call pomodoroTimer startWork`

## Done in this session

- [x] Statistics dashboard + Reset Stats
- [x] Direct-binding progress bar in the break modal
- [x] Multi-screen bar-pill fix (`timerDisplayActive` / `showSecondsOnly` → PluginGlobalVar; wall-clock blink)
- [x] Away / lock / suspend handling (see SPECS.md matrix) — branch logic verified via simulated away times:
  - < short break: countdown restored and resumed
  - >= short break, < long break: fresh auto-starting session, counter unchanged
  - >= long break (incl. 8 h): counter reset to 0 (persisted) + fresh auto-starting session
- [x] Break-complete: big "Continue working" `DankButton` (56 px, primary color, play icon) + Return/Enter key on the focused modal
- [x] Settings statistics live refresh (event-driven via `pluginStateChanged` / `globalVarChanged`, 10 s poll kept as fallback)
- [x] Removed dangling `initGuardTimer.restart()` calls (referenced but never defined — threw ReferenceError on every start)

## Known limitations / to verify later

- Away detection triggers (SessionService signals + 1 s `dms ipc call lock isLocked` probe) are wired but not yet exercised against a real screen lock — the lock screen was unstable during testing; verify manually by locking during a work session
- The pre-warning toast still shows only on the primary screen (by design)
