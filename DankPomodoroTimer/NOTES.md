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

- Signals (`sessionLocked`, `sessionUnlocked`, `sessionResumed`) and `preparingForSleep` only work when `SettingsData.loginctlLockIntegration` is enabled and loginctl is available — always pair with the 1 s `dms ipc call lock isLocked` probe as fallback
- `sessionResumed` is deduplicated (1 s window); on wake with lock-before-suspend, wait for `sessionUnlocked` instead (check `SessionService.locked && SettingsData.lockBeforeSuspend`)
- Wall-clock time (`Date.now()`) keeps running during suspend, so it measures the full away duration

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
