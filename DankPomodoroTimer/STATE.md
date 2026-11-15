# DMS Ketchup — Project State

## Git

- Repo: `~/.config/DankMaterialShell/plugins/.repos/39b15ac4661f477a/` (branch `main`)
- Published fork (`origin`): https://github.com/jw2122/dms-ketchup
- Upstream/original (`upstream`): https://github.com/virtualwolf-369/dms-ketchup
- Community registry PR: https://github.com/duxlabs-dev/dux-plugin-registry/pull/1185 (entry `plugins/jw2122-dms-ketchup.json`)
- Commits: `ebdecf3` (countdown/overlay/pre-warning), `bcf42ee` (statistics dashboard + dms-common), `5d9c474` (fix progress bar staying gray), `45c02ff` (multi-screen countdown, away/lock handling, break-complete button, live stats), `7400424` (slider settings + cycle reset time option), `5cf228b` (cycle reset hour, DND-gated notifications, lock/suspend break flow), `b312036` (code-review cleanup), `c2a9909` (gate lock probe on loginctl signal path), `9c45568` (slow lock probe fallback to 10 s), `18fa5e9` (pause all media players when a break starts), `69c5fc2` (slow lock probe fallback to 30 s), `653bb45` (motivational phrase translations with selectable language), `befab25` (auto-start on unlock), `6b7b0f2` (auto-start at shell startup), `51efe61` (preserve the break-modal phase at lock time), `0929e21` (lock-screen widget, system fonts, modal/popout refresh), `3d8b276` (lock-screen session controls, shared away state, one-shot unlock handling)

## Environment

- `dmsKetchup` enabled in `~/.config/DankMaterialShell/plugin_settings.json`
  - Current values: `workDuration: 25`, `shortBreakDuration: 5`, `longBreakDuration: 15`, `sessionsPerLongBreak: 4`, `cycleResetHour: 4`, `phraseLanguage: "en"`, both auto-start toggles on, media pause on
  - Plugin version: 1.4.3
- `dankPomodoroTimer` (Avenge Media v1.1.6, installed first-party at `plugins/DankPomodoroTimer/`) — disabled; reference implementation for multi-screen display
- `dmsPomodoro` and `pomodoroCopy` also enabled (other pomodoro plugins)
- dmsKetchup and dankPomodoroTimer share the IPC target `pomodoroTimer` — only one may be enabled at a time

## Reference paths (running shell)

`/run/user/1000/dms-shell/<hash>/` — live DMS 2.0 shell sources:

- `Services/PluginService.qml` — PluginGlobalVar storage (`globalVars[pluginId][varName]`), plugin state cache
- `Services/SessionService.qml` — lock / suspend signals
- `Widgets/PluginGlobalVar.qml`, `Modules/Plugins/PluginSettings.qml`
- `PLUGINS/README.md` — plugin API docs

## Commands

- QML changes require a shell restart: `dms restart` (plugins do NOT hot-reload)
- Lint: `qmllint <file>` (v1.0 — old; `DMSKetchupWidget.qml` and `DMSKetchupLockWidget.qml` exit 255 with no message (the old linter cannot resolve `qs.Modules.Plugins` / `PluginGlobalVar`); settings + modal exit 0)
- Logs: `journalctl --user -u '*dms*'`
- Manual test: `dms ipc call pomodoroTimer startWork`

## Review & stabilization pass (2026-11-10, v1.4.1)

Everything below was implemented and verified live in this working tree (uncommitted):

- [x] **Break modal rendered nothing**: `Repeater` was used for `PanelWindow` delegates ("Delegate must be of Item type"); replaced with Quickshell `Variants`. Verified on eDP-1: card, icon, countdown, progress, phrase, pills.
- [x] **Lock-time phase loss**: both lock paths captured `breakModalPhase` *after* `closeBreakModal()` (always `"hidden"`). Phase is now captured before closing.
- [x] **Startup suppression was a time window that dropped the open**: single-shot 20 s `bootGuardTimer` + `armStartupSuppression()` / `endStartupSuppression()`; a deferred modal is opened after boot instead of being dropped.
- [x] **Lock probe overrode `running`**: `lockStateProbeTimer.restart()` calls removed; the probe is bound to `timerDisplayActive && !SettingsData.loginctlLockIntegration`, 30 s, one-shot at a time.
- [x] **Double unlock handling**: shared `unlockHandledAt` stamp (2 s window) stops the second bar instance from re-opening the modal / starting work twice.
- [x] **Break refactor**: `startShortBreak` / `startLongBreak` delegate to one `startBreak(kind, autoStart, openModal, playSoundNow)`; the modal opens only in fullscreen mode; `startCycleBreak` no longer duplicates the decision.
- [x] **Break overlay pause/resume**: "Pause break" / "Resume break" pill + `Space` key; resuming re-pauses media that started during the pause. README already claimed pause support; `toggleBreakPause()` was unused.
- [x] **Pre-warning toast**: cached component; toast closes on pause/toggle; countdown refreshed on creation; fixed invalid `Quickshell.primaryScreen` (now `screens[0]`) and `implicitWidth/Height`; shared `BarInsets.js` offsets.
- [x] **Sound/notification cost**: player resolved once (`pw-play` → `paplay` → `aplay` → `ffplay` → `play`); pending first chime; `notify-send -u normal <title> <body>` as direct argv (no shell, no quoting).
- [x] **Multi-instance safety**: `initAt` stamp + `initializationOwner`; duration-change handlers only re-base when the instance owns the session. Fixed second-instance reset that left a paused timer after auto-start.
- [x] **Settings**: single 365-day stats pass (top-5 contributors), 150 ms debounced refresh, `clearPluginState` reset with fallback loop, capped init retries, removed unused import; removed the `onPluginServiceChanged` override that shadowed `PluginSettings`' value reload (toggles showed defaults because of it).
- [x] **About card said "undefined minutes"**: it read non-existent `PluginSettings.workDuration` / `…BreakDuration` properties. It now reads the live slider values (`workSlider.value`, …) and updates as the sliders move. Verified live (25 / 5 / 15 / 4).
- [x] **`autoStartWorkOnUnlock` now really starts work** (superseded by v1.4.3 — idle/paused now starts a **fresh full-length** session, live sessions continue): a work session paused before locking stayed paused after unlock. `handleUnlocked()` now resumes it (remaining time kept) when the toggle is on, in addition to the existing break-finished and no-session paths. Verified live: pause → lock 6 s → unlock → `running:true`.
- [x] **Removed dead code / log spam**: `cleanupOldData`, `pauseCurrentTimer`, redundant today-only branch, debug `console.log`s.
- [x] **`status()` IPC** added (JSON: state, remaining, total, displayActive, completed, modal phase, lock/deferred state); fixed `POMDORO` typo.
- [x] **Lock widget** reads reactive `pluginData` for `workDuration` / `sessionsPerLongBreak`.
- [x] Live verification: modal on eDP-1 with pause/resume (`running:false/true`, label switch) and skip (work session started); pre-warning at 10 s with Snooze (+300 s) and Skip (break start); lock/unlock during a break re-opens the modal, break continues, one `handleUnlocked`, no duplicate starts; settings page renders with stored values; auto-start work 25 min after a clean restart.
- [x] Lint: Qt6 `qmllint` (no parse errors), `BarInsets.js` passes `node --check`.
- [x] Test durations temporarily set to 1 min, then restored to 25/5; temporary no-accessibility systemd drop-in removed and `dms` restarted cleanly.

## Done in this session

- [x] Statistics dashboard + Reset Stats
- [x] Direct-binding progress bar in the break modal
- [x] Multi-screen bar-pill fix (`timerDisplayActive` / `showSecondsOnly` → PluginGlobalVar; wall-clock blink)
- [x] Settings UI: duration sliders (Work 5–60, Short 1–10, Long 1–30 — take-a-break limits), cycle reset time slider (0–23, default 4), pre-warning lead-time slider; stats now load initially without pressing Refresh (`statsInitTimer` polling fix)
- [x] Cycle reset hour: counter decoupled from daily stats (`cycleCounter` / `cycleResetDate` keys; daily stats incremented per completion; midnight rollover no longer resets the counter; away-reset no longer wipes today's stats; `skipWork` uses the cycle-consistent break type)
- [x] Push notifications gated on `SessionData.doNotDisturb` (send-time check; sounds and in-app UI unaffected)
- [x] Lock/suspend rework: work sessions pause and resume within `shortBreakDuration`; longer absences take the previous break type (session does not count) then restart the session; `>= longBreakDuration` keeps the cycle reset; breaks are not paused by lock and lose away time on suspend (expired breaks finish into the next work session); deferred break modal now opens on unlock
- [x] Lock detection optimized: `SessionService` push signals are the primary path (loginctl integration is on by default); the 30 s `lock isLocked` probe now only runs as a fallback when that integration is disabled and only while a session is active — zero process spawns in the default configuration
- [x] All five away branches verified via simulated away times (30 s restore, 70 s cycle break, 100 s cycle reset, break −30 s continue, break −90 s finish) plus a real work completion (counter + stat persisted correctly)
- [x] Code-review cleanup: removed dead code (`formatTime`, `hasActiveTimer`, redundant boot `initTimer`), simplified `continueWorkingAfterBreak`, `skipWork` now notifies + plays a sound via `startCycleBreak`, interrupted sessions get a neutral notification title, `statePluginId`/`pluginId` constant replaces ~20 inline `"dmsKetchup"` literals, removed the redundant 10 s stats poll in settings (event-driven refresh covers all writers)
- [x] Break-complete: big "Continue working" `DankButton` (56 px, primary color, play icon) + Return/Enter key on the focused modal
- [x] Settings statistics live refresh (event-driven via `pluginStateChanged` / `globalVarChanged`; the 10 s poll was removed — events cover every writer)
- [x] Removed dangling `initGuardTimer.restart()` calls (referenced but never defined — threw ReferenceError on every start)
- [x] Media pause: every playing Mpris player (`isPlaying && canPause`) is paused when a short/long break starts (covers completion, cycle breaks, quick actions, skip); deliberately no resume; `pauseMediaDuringBreaks` toggle (default on) in the Behavior card — verified live ("paused 1 media player(s)")
- [x] Media pause refined: now fires only when the break countdown actually starts (auto-started breaks + the popout play button via `toggleTimer`), not when the quick-action buttons merely arm a paused countdown (`startShortBreak(false)`); verified both the autoStart path and the toggleTimer resume path in the journal
- [x] Media pause is now enforced for the whole running break (v1.4.2): an `Instantiator` watches every `MprisController.availablePlayers` entry and pauses it whenever it (re)starts playing while `breakRunning` is true, including players that appear after the break began and delegates created with the player already playing; a paused break and work sessions leave media alone. Verified live with Brave's MPRIS: break start paused it, manual `Play` mid-break was paused again, pausing the break kept it playing, resuming the break paused it again, and a work session let it play
- [x] Published public fork `jw2122/dms-ketchup` (upstream `virtualwolf-369/dms-ketchup` remains on the old commits; local credentials are for `jw2122`, so pushing to the upstream owner was denied) and opened the Dux Shell registry PR #1185 with `plugins/jw2122-dms-ketchup.json` (`dankbar-widget` + `desktop-widget`, `path: DankPomodoroTimer`, screenshot `docs/screenshots/lock-screen.png`). Registry validators pass for the single changed entry (`CHANGED_PLUGINS=... python3 .github/validate_links.py`); the full 412-plugin link scan was not run.
- [x] Lock-screen study mode (v1.4.3): with `autoStartWorkOnUnlock` on, locking no longer pauses/snapshots a work session — the countdown keeps running so the lock card is a live study timer. Unlock leaves a live work/break session untouched and starts a **fresh** 25:00 work session only when nothing is live (idle, paused, break finished). The lock screen never auto-starts a work block: idle shows READY / 25:00 / "Start a 25 min session" and the play button starts a full session. Suspend still snapshots and pauses. The card now shows the live finish time ("ends HH:MM"), fixes the session number during a focus block (was always the last completed session; now `completed % N + 1`), and shows whether the next break is short or long. Verified live on both monitors: locked focus stayed running (25:00 → 24:49 after 11 s, "FOCUS · ends 11:29 · Session 2/4 · short break next"); paused → lock → unlock restarted at 25:00 (total 1500, remaining 1499); reset → lock showed READY/25:00/Start, `lockStart` ran it at 25:00, unlock kept it running; a break kept running while locked and unlock re-opened its modal
- [x] Auto-start work on unlock (`autoStartWorkOnUnlock`, default off, enabled in the user's settings): `handleUnlocked()` starts the next work session when a break finished while locked (catches both the deferred-modal path and the modal-opened-behind-lock-screen default path), and starts a fresh session when none was running (boot/reset); verified live alongside the lock-controls work (single choke point for all unlock signals)
- [x] Auto-start work on startup (`autoStartWorkOnStartup`, default off, enabled in the user's settings): a fresh work session starts when the shell boots/logins/`dms restart` with none running; the check is deferred via `Qt.callLater` because the base `PluginComponent` populates `pluginData` only in its own (later) `Component.onCompleted` — the first inline version silently never fired; verified live in the journal ("auto-starting work session at startup", exactly once despite the double bar-instance load)
- [x] Lock-time modal phase preservation: `onSessionLocked` and the probe path deferred every open break modal as "running" — a break that had already finished (modal showing "Continue working") re-opened as a 0:00 running overlay with only Skip after unlock. Now the actual phase is preserved at lock, and `handleUnlocked()` upgrades a stale "running" phase when the modal re-opened as "complete" behind the lock screen; with `autoStartWorkOnUnlock` on, unlock then goes straight to the next work session. Verified live: continuing from the lock screen leaves no stale modal and does not double-start on unlock
- [x] DMS 2.0 pill buttons: the popout quick actions stay on one row with intrinsic widths instead of three equal columns; `horizontalPadding: Theme.spacingS` leaves enough room for the full "Short break" / "Long break" labels. Verified by rendering DButton at the live 368 px popout content width with the JetBrains Mono theme font: the labels no longer touch the pill edges and the row still fits with a small margin.
- [x] Phrase translations: 11 tips in 18 languages under `translations/<lang>.json`; `phraseLanguage` setting (default `system`, candidate chain full locale → hyphen variant → language → en); modal picks a random phrase and hides the line when empty; verified system fallback (de_AT → de.json) and explicit selection (ja.json)
- [x] Sessions-per-long-break slider (`sessionsPerLongBreak`, 1–10, default 4) replacing the hardcoded `% 4` in the completion path, `cycleBreakIsLong()` and the popout "Next long break after N more" text; About card now shows live values instead of hardcoded numbers; fixed stale `"longBreakDuration": "1,5"` in plugin_settings.json (slider can't represent comma decimals — it was running 1.5 min long breaks while the UI implied 15)
- [x] Typography: bar pill explicitly uses the DMS system font (`Theme.fontFamily`, `Theme.fontWeightMedium`); the break-modal quote and all big countdowns (modal, popout, lock widget) use the fontconfig system monospace (`font.family: "monospace"`; `qs.Common` does not export `Fonts.systemMono`)
- [x] Visual refresh (simple/modern): break modal is now a centered card with a tinted state badge, state-colored 96 px countdown, progress track, primary continue button, subtle skip pill and a soft gradient; popout got a rounded-cap ring, filled primary play/pause and tonal reset buttons
- [x] Lock-screen widget (`DMSKetchupLockWidget.qml`, new `desktop` surface): READY/FOCUS/PAUSED/BREAK state, monospace countdown, progress bar, "Session N of M" and session length; reads the bar widget's globals instead of running its own timer. Verified live on both monitors via `dms ipc call lock lock` (PAUSED/24:51, READY/25:00, Session 1 of 4); instance + position stored in `settings.json` / `session.json`
- [x] Lock-screen session controls (v1.4.0): play/pause + skip/continue row on the lock card, mapped to new `lockStart` / `lockPause` / `lockResume` / `lockContinue` IPC actions on the bar engine (one session owner). Pause while locked restarts the away snapshot at that moment ("as if I locked now"); play cancels it; unlocking applies the away reset/repeat logic only when the session is still paused. READY→start, break pause/play, break skip→work, break-complete→continue (clears the deferred modal, no stale modal or double start on unlock); the row is inert in the editor/demo and the card is 340×180
- [x] Away bookkeeping moved to shared `PluginGlobalVar`s (`awayActive` / `awayStartMs` / `awaySnapshot` / `awayCause`): both bar instances receive lock/unlock signals, so the first one acts and the other no-ops — a lock/unlock pair is applied exactly once (verified in the journal: one `beginAway`, one `endAway`). Also set `sessionLocked` immediately from the lock signal, and suppressed the pre-warning toast + desktop notifications while locked (sounds still play)
- [x] Live lock verification (real `dms ipc call lock lock|unlock`, v1.3-era behavior; lock no longer pauses work under `autoStartWorkOnUnlock` since v1.4.3): work lock→PAUSED→unlock restores; resume from lock→unlock keeps running with no away reset; pause from lock→fresh snapshot→short unlock restores and resumes; READY→start; break pause/resume/skip; break-complete→continue. Screenshots taken on both monitors
- [x] Manifest/registry: `plugin.json` 1.3.0 keeps the legacy `"component"` and adds `"components": { "widget", "desktop" }`; `qmldir` lists the new component (DMS 2.0 `_resolveComponentPaths` prefers `components`)
- [x] Fixed the quote never appearing: `Proc.runCommand` keys callbacks by id, so both bar instances shared `dmsKetchup.readPhrases` and only one received the table. The id is now per-instance and the modal re-picks on open — verified live (monospace tip renders under the subtitle)
- [x] Replaced the non-existent DMS 2.0 token `Theme.fontSizeExtraLarge` (was logging "Unable to assign double to int" at the modal title); all other Theme tokens used by the plugin were checked against the live `Theme.qml`

## Known limitations / to verify later

- Away detection (SessionService signals; gated 30 s `lock isLocked` probe fallback) is verified live on the signal path. The probe fallback (only used when `loginctlLockIntegration` is disabled) is still unverified — exercise it once with the integration off
- Do not restart `dms` while the session is locked: the dying lock client poisons Hyprland's `ext-session-lock` state and every later lock dies with `wl_display: invalid object N` until the compositor/session is restarted (this happened during testing; not a plugin bug — reproduces with the previous commit and with the lock widget removed)
- The pre-warning toast still shows only on the primary screen (by design)
- DND gating verified by inspection (live `SessionData.doNotDisturb` property read at send time); toggle DND during a session to observe it end-to-end
- Old string duration values (e.g. `"1,5"`) still drive the timer, but the sliders show a coerced value until moved once
- Cosmetic, pre-existing in `dms-common/SliderSettingPlus.qml` (not modified): in the narrow plugin settings panel the long labels elide to "Wor… / Sho… / Lon…". The value and slider work; widening the panel or shortening the labels fixes it
- Statistics dashboard verified live after the single-pass rewrite (Today 0 / This Week 16 / Total 101 / Best Day 13, top-5 list, Refresh + Reset Stats). The same check found the About card printing "undefined minutes"; fixed by reading the live slider values (pre-existing bug).
