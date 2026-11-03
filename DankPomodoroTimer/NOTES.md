# DMS Ketchup — Notes & Gotchas

## PluginGlobalVar

- Namespaced by plugin id (`globalVars[pluginId][varName]`) — the same `varName` in different plugins is safe
- **In-memory only** — never persisted to disk; the per-day `completedPomodoros-YYYY-MM-DD` keys are the durable store
- Reactive via `PluginService.globalVarChanged(pluginId, varName)`

## Plugin state

- `savePluginState`: in-memory cache updated **immediately**, disk write debounced 150 ms -> in-process readers always see fresh values
- `loadPluginState(pluginId, key, default)` returns `default` when the key is missing
- `removePluginStateKey` no-ops if the plugin's cache was never loaded — call `loadPluginState` once first to warm the cache
- State file: `~/.local/state/DankMaterialShell/plugins/dmsKetchup_state.json`

## Multi-screen

- Each screen instantiates its own `PluginComponent`; **local properties are per-instance** — anything display-related that must match across screens must be a `PluginGlobalVar`
- A shared blink counter would advance N× faster with N screens — derive blink phase from `Date.now()` instead
- The fullscreen modal already spans all screens (`Repeater { model: Quickshell.screens }`, one `PanelWindow` each); the pre-warning toast is primary-screen only by design

## SessionService (lock / suspend)

- Signals (`sessionLocked`, `sessionUnlocked`, `sessionResumed`) and `preparingForSleep` only work when `SettingsData.loginctlLockIntegration` is enabled and loginctl is available — always pair with the 30 s `dms ipc call lock isLocked` probe as fallback (only while `timerDisplayActive`)
- `onSessionLocked` must also set the local `sessionLocked` mirror immediately: the probe can lag by up to 30 s, and the lock-control pause path and the notification/pre-warning gates depend on it. Also use `SessionService.locked` as a fallback in the pause guard for the first click after locking.
- `sessionResumed` is deduplicated (1 s window); on wake with lock-before-suspend, wait for `sessionUnlocked` instead (check `SessionService.locked && SettingsData.lockBeforeSuspend`)
- Wall-clock time (`Date.now()`) keeps running during suspend, so it measures the full away duration

## Away state and lock controls

- Both bar instances receive every lock/unlock signal, so per-instance away properties caused double `beginAway` and double reset/repeat. Away bookkeeping lives in shared `PluginGlobalVar`s (`awayActive`, `awayStartMs`, `awaySnapshot`, `awayCause`); the first instance to act wins and the second no-ops.
- `PluginService.setGlobalVar` updates `globalVars` synchronously, so the check-and-set inside `beginAway`/`endAway` is race-free within one signal dispatch. Snapshots are plain JS objects — fine as `var`.
- Unlock rule: `handleUnlocked()` cancels the snapshot when `isRunning` is true and runs `endAway()` only when the session is still paused. A session resumed from the lock screen therefore continues untouched.
- `lockPause` is "lock now": when locked, in a work session and no away is pending it calls `beginAway("lock")` (fresh timestamp). Otherwise it just pauses (breaks included).
- `lockContinue` (also used for skip) clears `deferredBreakModalPhase` / `breakModalArmed`, closes the modal and starts a **running** work session — the same outcome as the modal's Continue button, without a second start on unlock.
- Do not open the fullscreen break modal from `toggleTimer` while locked (`!root.sessionLocked`): it would cover the lock screen when resuming a paused break.
- The lock widget drives all of this with `Quickshell.execDetached(["dms", "ipc", "call", "pomodoroTimer", action])`; buttons are disabled (opacity 0.4) in the editor/demo via `lockHost.demoMode`.

## Hyprland lock gotcha

- Never restart the `dms` service while the session is locked during testing. The dying `ext-session-lock` client leaves Hyprland's lock state poisoned; every later `dms ipc call lock lock` then kills the UI with `wl_display#1: error 0: invalid object N` / "Wayland connection experienced a fatal error" until the compositor session is restarted. It reproduces with the previous commit and with the lock widget removed, so it is a compositor/quickshell bug, not this plugin.

## Theme / styling

- No `Theme.errorContainer` — use `Theme.withAlpha(Theme.error, 0.15)`
- `DankButton` supports `iconName` and `buttonHeight`
- `DankIcon` uses `name` / `size` / `color`
- DMS 2.0 `DankButton` is a shim for `DButton`: its radius is a pill (`height / 2`) and its content row is icon + 8 px gap + label + `horizontalPadding` (16 px at the default 40 px height). Buttons that sit in a fixed-width row need enough room for that. The quick actions use intrinsic widths and `horizontalPadding: Theme.spacingS` so the full labels fit on one line at the 400 px popout width; the user's `JetBrainsMono Nerd Font` theme font is much wider than the default, which is what made the old 3-equal-column row overflow.

## IPC (IpcHandler)

- Exposed functions MUST have a return-type annotation (`function foo(): string`) — unannotated functions are not registered (`dms ipc call lock lock` returns "Target not found" for this reason)
- Parameters MUST be typed (`function foo(bar: string): string`) — untyped parameters break registration ("Function not found")
- IPC passes everything as strings — parse numbers with `parseFloat()`
- Plugin QML does NOT hot-reload — `dms restart` is required after every edit

## Logging

- `console.log` is debug-level and filtered out of `journalctl` (invisible!) — use `console.info` / `console.warn` / `console.error` for anything that must appear in the journal

## Misc

- Timer durations in `plugin_settings.json` are strings; always sanitize with `toDuration()`
- `qmllint` is v1.0 (old) — `DMSKetchupWidget.qml` exits 255 with no message (pre-existing)
- The widget's `onPluginServiceChanged` resets all globals on every shell start (fresh paused work session at full duration)
