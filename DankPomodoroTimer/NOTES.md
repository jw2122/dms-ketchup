# DMS Ketchup — Notes & Gotchas

## PluginGlobalVar

- Namespaced by plugin id (`globalVars[pluginId][varName]`) — the same `varName` in different plugins is safe
- **In-memory only** — never persisted to disk; the per-day `completedPomodoros-YYYY-MM-DD` keys are the durable store
- Reactive via `PluginService.globalVarChanged(pluginId, varName)`
- `setGlobalVar` always rebuilds the `globalVars` object and emits `globalVarChanged`, **even for an identical value** — guard write loops (the countdown display only writes when the formatted value changes)
- `pluginData` is populated in the base `PluginComponent`'s own `Component.onCompleted`, after the derived widget's — read it from `Qt.callLater` / bindings, never inline during construction

## Inherited signal handlers (QML)

- A signal handler declared in a derived type (`onPluginServiceChanged:` in `DMSKetchupSettings.qml`) **replaces** the base type's handler instead of chaining. `PluginSettings` uses that handler to re-run `loadValue()` on its children, so overriding it made every setting widget keep its default while the stored values were ignored. Do not redeclare inherited handlers unless you replicate the base behaviour.
- `PluginSettings` exposes only `pluginId`, `pluginService`, `settingChanged`, `variants` and the `settingChanged()` helper — it has **no** duration/data properties (`workDuration`, …). Read stored values via `pluginService.loadPluginData()`, or bind to the setting widgets' `value` (the About card uses the slider values).

## Quickshell API

- `Quickshell.primaryScreen` does not exist — use `Quickshell.screens[0]` (guard the empty list)
- `Repeater` cannot host `PanelWindow` delegates — use `Variants` (see Multi-screen)
- `Proc.runCommand` keys callbacks by id; per-instance ids avoid collisions between the two bar instances

## Known upstream/dms-common issues (not changed)

- `dms-common/SliderSettingPlus.qml` logs `Binding loop detected for property "width"` once per slider when the settings page opens (its label width is derived from the parent row width). Harmless, bounded to page open.
- The same file elides long labels to "Wor… / Sho… / Lon…" in the narrow plugin settings pane; values and sliders still work.

## Plugin state

- `savePluginState`: in-memory cache updated **immediately**, disk write debounced 150 ms -> in-process readers always see fresh values
- `loadPluginState(pluginId, key, default)` returns `default` when the key is missing
- `removePluginStateKey` no-ops if the plugin's cache was never loaded — call `loadPluginState` once first to warm the cache
- State file: `~/.local/state/DankMaterialShell/plugins/dmsKetchup_state.json`

## Multi-screen

- Each screen instantiates its own `PluginComponent`; **local properties are per-instance** — anything display-related that must match across screens must be a `PluginGlobalVar`
- A shared blink counter would advance N× faster with N screens — derive blink phase from `Date.now()` instead
- The fullscreen modal spans all screens with `Variants { model: Quickshell.screens }`, one `PanelWindow` each; the pre-warning toast is primary-screen only by design
- **Use `Variants`, never `Repeater`, for `PanelWindow` delegates.** `PanelWindow` is a `Window`, not an `Item`, so a `Repeater` delegate fails with "Delegate must be of Item type" and silently renders nothing (the overlay never appeared). `Variants` is the Quickshell container for non-`Item` delegates (the shell itself uses it for `Variants { model: Quickshell.screens }`).
- Bar/dock insets are computed in `dms-common/BarInsets.js` (`edgeOffset()`), shared by the modal and the toast; the modal uses the same inset on left and right (`max(left, right)`) so an asymmetric bar layout cannot push the card off-centre.

## Multi-instance initialisation

- Each screen's plugin instance receives `onPluginServiceChanged`; without coordination the second instance re-ran the session reset a moment after the first had auto-started, leaving a paused timer and no display.
- The fix is a shared `initAt` `PluginGlobalVar` stamp: the first instance within 5 s becomes `initializationOwner` and runs init + auto-start; the others bail out.
- Similarly, `onWorkDurationChanged` / `onShortBreakDurationChanged` / `onLongBreakDurationChanged` only re-base the countdown when `globalTimerOwnerId.value === root.instanceId`. A second instance loading with fallback durations used to rewrite a running session's totals.

## SessionService (lock / suspend)

- Signals (`sessionLocked`, `sessionUnlocked`, `sessionResumed`) and `preparingForSleep` only work when `SettingsData.loginctlLockIntegration` is enabled and loginctl is available — always pair with the 30 s `dms ipc call lock isLocked` probe as fallback (only while `timerDisplayActive`)
- `onSessionLocked` must also set the local `sessionLocked` mirror immediately: the probe can lag by up to 30 s, and the lock-control pause path and the notification/pre-warning gates depend on it. Also use `SessionService.locked` as a fallback in the pause guard for the first click after locking.
- `sessionResumed` is deduplicated (1 s window); on wake with lock-before-suspend, wait for `sessionUnlocked` instead (check `SessionService.locked && SettingsData.lockBeforeSuspend`)
- Wall-clock time (`Date.now()`) keeps running during suspend, so it measures the full away duration

## Away state and lock controls

- Both bar instances receive every lock/unlock signal, so per-instance away properties caused double `beginAway` and double reset/repeat. Away bookkeeping lives in shared `PluginGlobalVar`s (`awayActive`, `awayStartMs`, `awaySnapshot`, `awayCause`); the first instance to act wins and the second no-ops.
- `PluginService.setGlobalVar` updates `globalVars` synchronously, so the check-and-set inside `beginAway`/`endAway` is race-free within one signal dispatch. Snapshots are plain JS objects — fine as `var`.
- Unlock rule: `handleUnlocked()` cancels the snapshot when `isRunning` is true and runs `endAway()` only when the session is still paused. A session resumed from the lock screen therefore continues untouched.
- With `autoStartWorkOnUnlock` on, a work session that the user had paused before locking is resumed after the away restore (remaining time kept, DND reapplied). Without this, the toggle kept the session paused even though its label promises "make sure a work session is running".
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
- `console.trace()` produced no output in this shell build

## Reloading during development

- `dms ipc call plugin-scan reload dmsKetchup` re-runs the plugin but can serve a **stale cached component**; a structural QML change (new file, delegate type, imports) needs a full `dms restart` before it takes effect
- `dms ipc call plugin-scan rescan dmsKetchup` invalidates the manifest/component revisions, but the running component objects may still be cached — verify in the journal and with a screenshot

## Misc

- Timer durations are stored as numbers by the sliders, but old `plugin_settings.json` files may contain strings; always sanitize with `toDuration()`
- The system `qmllint` may be Qt 5.15 (fails on `?.` and other modern syntax). Use `/usr/lib/qt6/bin/qmllint -I /run/user/1000/dms-shell/<hash> <file>`; parse errors are what matter (missing type warnings are expected for `qs.*` imports)
- The widget's `onPluginServiceChanged` resets all globals on shell start — now only for the `initializationOwner` instance (see Multi-instance initialisation)
