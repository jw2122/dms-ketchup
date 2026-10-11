# DMS Ketchup — Project State

## Git

- Repo: `~/.config/DankMaterialShell/plugins/.repos/39b15ac4661f477a/` (branch `main`)
- Remote: https://github.com/virtualwolf-369/dms-ketchup
- Commits: `ebdecf3` (countdown/overlay/pre-warning), `bcf42ee` (statistics dashboard + dms-common), `5d9c474` (fix progress bar staying gray), `45c02ff` (multi-screen countdown, away/lock handling, break-complete button, live stats), `7400424` (slider settings + cycle reset time option), `5cf228b` (cycle reset hour, DND-gated notifications, lock/suspend break flow), `b312036` (code-review cleanup), `c2a9909` (gate lock probe on loginctl signal path), `9c45568` (slow lock probe fallback to 10 s), `18fa5e9` (pause all media players when a break starts), `69c5fc2` (slow lock probe fallback to 30 s), `653bb45` (motivational phrase translations with selectable language)

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
- [x] Settings UI: duration sliders (Work 5–60, Short 1–10, Long 1–30 — take-a-break limits), cycle reset time slider (0–23, default 4), pre-warning lead-time slider; stats now load initially without pressing Refresh (`statsInitTimer` polling fix)
- [x] Cycle reset hour: counter decoupled from daily stats (`cycleCounter` / `cycleResetDate` keys; daily stats incremented per completion; midnight rollover no longer resets the counter; away-reset no longer wipes today's stats; `skipWork` uses the cycle-consistent break type)
- [x] Push notifications gated on `SessionData.doNotDisturb` (send-time check; sounds and in-app UI unaffected)
- [x] Lock/suspend rework: work sessions pause and resume within `shortBreakDuration`; longer absences take the previous break type (session does not count) then restart the session; `>= longBreakDuration` keeps the cycle reset; breaks are not paused by lock and lose away time on suspend (expired breaks finish into the next work session); deferred break modal now opens on unlock
- [x] Lock detection optimized: `SessionService` push signals are the primary path (loginctl integration is on by default); the 10 s `lock isLocked` probe now only runs as a fallback when that integration is disabled and only while a session is active — zero process spawns in the default configuration
- [x] All five away branches verified via simulated away times (30 s restore, 70 s cycle break, 100 s cycle reset, break −30 s continue, break −90 s finish) plus a real work completion (counter + stat persisted correctly)
- [x] Code-review cleanup: removed dead code (`formatTime`, `hasActiveTimer`, redundant boot `initTimer`), simplified `continueWorkingAfterBreak`, `skipWork` now notifies + plays a sound via `startCycleBreak`, interrupted sessions get a neutral notification title, `statePluginId`/`pluginId` constant replaces ~20 inline `"dmsKetchup"` literals, removed the redundant 10 s stats poll in settings (event-driven refresh covers all writers)
- [x] Break-complete: big "Continue working" `DankButton` (56 px, primary color, play icon) + Return/Enter key on the focused modal
- [x] Settings statistics live refresh (event-driven via `pluginStateChanged` / `globalVarChanged`; the 10 s poll was removed — events cover every writer)
- [x] Removed dangling `initGuardTimer.restart()` calls (referenced but never defined — threw ReferenceError on every start)
- [x] Media pause: every playing Mpris player (`isPlaying && canPause`) is paused when a short/long break starts (covers completion, cycle breaks, quick actions, skip); deliberately no resume; `pauseMediaDuringBreaks` toggle (default on) in the Behavior card — verified live ("paused 1 media player(s)")
- [x] Phrase translations: 11 tips in 18 languages under `translations/<lang>.json`; `phraseLanguage` setting (default `system`, candidate chain full locale → hyphen variant → language → en); modal picks a random phrase and hides the line when empty; verified system fallback (de_AT → de.json) and explicit selection (ja.json)

## Known limitations / to verify later

- Away detection (SessionService signals; gated 30 s `lock isLocked` probe fallback) is wired but not yet exercised against a real screen lock — the lock screen was unstable during testing; verify manually by locking during a work session, ideally once with `loginctlLockIntegration` disabled to exercise the probe fallback
- The pre-warning toast still shows only on the primary screen (by design)
- DND gating verified by inspection (live `SessionData.doNotDisturb` property read at send time); toggle DND during a session to observe it end-to-end
- Old string duration values (e.g. `"1,5"`) still drive the timer, but the sliders show a coerced value until moved once
