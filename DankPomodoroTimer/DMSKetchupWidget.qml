import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "."

PluginComponent {
    id: root

    function toDuration(value, fallback) {
        if (value === undefined || value === null || value === "")
            return fallback;
        const normalized = String(value).replace(",", ".");
        const parsed = parseFloat(normalized);
        return isNaN(parsed) || parsed < 0 ? fallback : parsed;
    }

    function toIntSetting(value, fallback, minValue, maxValue) {
        const raw = (typeof value === "number") ? value : parseFloat(String(value).replace(",", "."));
        if (isNaN(raw))
            return fallback;
        return Math.max(minValue, Math.min(maxValue, Math.round(raw)));
    }

    property real workDuration: toDuration(pluginData.workDuration, 25)
    property real shortBreakDuration: toDuration(pluginData.shortBreakDuration, 5)
    property real longBreakDuration: toDuration(pluginData.longBreakDuration, 15)
    property int sessionsPerLongBreak: toIntSetting(pluginData.sessionsPerLongBreak, 4, 1, 10)
    property bool autoStartBreaks: pluginData.autoStartBreaks ?? false
    property bool autoStartPomodoros: pluginData.autoStartPomodoros ?? false
    property bool autoSetDND: pluginData.autoSetDND ?? false
    property var last7DaysData: []
    property string currentDateKey: ""
    property bool fullscreenBreakModalEnabled: pluginData.fullscreenBreakModalEnabled ?? true
    property bool requireManualContinueAfterBreak: pluginData.requireManualContinueAfterBreak ?? true
    property bool autoStartWorkOnUnlock: pluginData.autoStartWorkOnUnlock ?? false
    property bool autoStartWorkOnStartup: pluginData.autoStartWorkOnStartup ?? false
    property bool soundsEnabled: pluginData.soundsEnabled ?? true
    property bool enablePreWarning: pluginData.enablePreWarning ?? true
    property int preWarningTime: pluginData.preWarningTime ?? 10
    property int cycleResetHour: toIntSetting(pluginData.cycleResetHour, 4, 0, 23)
    property bool pauseMediaDuringBreaks: pluginData.pauseMediaDuringBreaks ?? true
    property string phraseLanguage: pluginData.phraseLanguage ?? "system"
    property var phraseTips: []
    property var phraseCandidates: []
    property int phraseCandidateIndex: 0
    property real preWarningOpacity: (pluginData.preWarningOpacity ?? 100) / 100
    property bool isPreWarning: false
    property var preWarningWindow: null
    property var preWarningComponent: null
    property int preWarningCountdown: 0
    property string startWorkSoundUrl: pluginData.startWorkSoundUrl ?? "file:///usr/share/sounds/freedesktop/stereo/message.oga"
    property string endWorkSoundUrl: pluginData.endWorkSoundUrl ?? "file:///usr/share/sounds/freedesktop/stereo/message.oga"
    property string soundPlayer: ""
    property string pendingSoundPath: ""
    property bool soundPlayerResolved: false
    property bool blinkVisible: true

    Timer {
        id: blinkTimer
        interval: 200
        repeat: true
        running: globalShowSecondsOnly.value
        onTriggered: {
            blinkVisible = Math.floor(Date.now() / 200) % 5 < 4;
        }
    }

    // Resolve the first available audio player once instead of spawning a
    // shell + probe loop for every chime.
    Process {
        id: soundPlayerProbe
        command: ["sh", "-c", "command -v pw-play || command -v paplay || command -v aplay || command -v ffplay || command -v play"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const path = data.trim();
                if (!path)
                    return;
                root.soundPlayer = path;
                if (root.pendingSoundPath !== "") {
                    const pending = root.pendingSoundPath;
                    root.pendingSoundPath = "";
                    root.playSoundFile(pending);
                }
            }
        }
        onExited: root.soundPlayerResolved = true
    }

    function tr(en, es) {
        const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
        return localeName.toLowerCase().startsWith("es") ? es : en;
    }
    property bool breakModalOpen: false
    property string breakModalPhase: "hidden"
    property bool startupGuard: true
    property bool sessionLocked: false
    property bool lockProbeBusy: false
    property bool breakModalArmed: false
    property int bootModalSuppressUntil: 0
    property string deferredBreakModalPhase: ""

    function armStartupSuppression() {
        root.startupGuard = true;
        root.bootModalSuppressUntil = Date.now() + 20000;
        root.deferredBreakModalPhase = "";
        root.closeBreakModal();
        bootGuardTimer.restart();
    }

    function endStartupSuppression() {
        root.startupGuard = false;
        root.bootModalSuppressUntil = 0;
        const phase = root.deferredBreakModalPhase;
        root.deferredBreakModalPhase = "";
        // A break that finished while the shell was still starting up must
        // not be silently dropped.
        if (phase !== "")
            root.openBreakModal(phase);
    }

    onPluginServiceChanged: {
        if (!pluginService)
            return;
        // Let exactly one of the two bar instances initialise the session.
        // The other one used to reset the globals barely after the first had
        // auto-started, which left the timer paused with no display.
        const initNow = Date.now();
        if (initNow - globalInitAt.value < 5000) {
            root.initializationOwner = false;
            return;
        }
        globalInitAt.set(initNow);
        root.initializationOwner = true;
        root.armStartupSuppression();
        root.sessionLocked = false;
        root.breakModalArmed = false;
        Qt.callLater(loadPhrases);
        root.currentDateKey = formatDateKey(new Date());
        let savedCounter = pluginService.loadPluginState(statePluginId, "cycleCounter", -1);
        if (savedCounter === null || savedCounter === undefined || savedCounter < 0)
            savedCounter = pluginService.loadPluginState(statePluginId, "completedPomodoros-" + root.currentDateKey, 0) || 0;
        globalCompletedPomodoros.set(savedCounter);
        root.loadLast7Days();
        root.closePreWarning();
        globalTimerDisplayActive.set(false);
        globalTimerState.set("work");
        globalTotalSeconds.set(root.workDuration * 60);
        globalRemainingSeconds.set(globalTotalSeconds.value);
        globalTimerOwnerId.set(root.instanceId);
        globalIsRunning.set(false);
        root.checkCycleReset();
    }

    Component.onCompleted: {
        root.closeBreakModal();
        root.closePreWarning();
        root.sessionLocked = false;
        root.breakModalArmed = false;
        root.armStartupSuppression();
        Qt.callLater(loadPhrases);
        // Deferred: PluginComponent populates pluginData in its own
        // Component.onCompleted, which runs after this one.
        Qt.callLater(() => {
            if (root.initializationOwner && root.autoStartWorkOnStartup && !globalTimerDisplayActive.value) {
                // No session running (fresh boot / login) — start one
                console.info("[dms-ketchup] auto-starting work session at startup");
                root.startWork(true, true);
            }
        });
    }

    onFullscreenBreakModalEnabledChanged: {
        if (!root.fullscreenBreakModalEnabled)
            root.closeBreakModal();
    }

    onBreakModalOpenChanged: {
        if (breakModalOpen && (startupGuard || Date.now() < root.bootModalSuppressUntil)) {
            breakModalOpen = false;
            breakModalPhase = "hidden";
            return;
        }
        if (!breakModalOpen)
            breakModalPhase = "hidden";
    }

    Process {
        id: lockStateProbeProcess
        command: ["dms", "ipc", "call", "lock", "isLocked"]
        running: false
        stdout: SplitParser {
            splitMarker: "
"
            onRead: function(data) {
                const locked = data.trim() === "true";
                const changed = locked !== root.sessionLocked;
                root.sessionLocked = locked;
                if (locked) {
                    if (root.breakModalOpen) {
                        root.deferredBreakModalPhase = root.breakModalPhase;
                        root.closeBreakModal();
                    }
                    beginAway("lock");
                } else if (changed) {
                    handleUnlocked();
                }
            }
        }
        onExited: {
            root.lockProbeBusy = false;
        }
    }

    Timer {
        id: lockStateProbeTimer
        // Safety net only (SessionService signals are the primary path) —
        // 30 s is plenty and cuts the IPC spawns 3x.
        interval: 30000
        repeat: true
        running: globalTimerDisplayActive.value && !SettingsData.loginctlLockIntegration
        onTriggered: {
            if (!root.lockProbeBusy) {
                root.lockProbeBusy = true;
                lockStateProbeProcess.running = true;
            }
        }
    }

    Connections {
        target: SessionService
        ignoreUnknownSignals: true
        function onPreparingForSleepChanged() {
            if (SessionService.preparingForSleep)
                beginAway("suspend");
        }
        function onSessionLocked() {
            root.sessionLocked = true;
            if (root.breakModalOpen) {
                root.deferredBreakModalPhase = root.breakModalPhase;
                root.closeBreakModal();
            }
            beginAway("lock");
        }
        function onSessionUnlocked() {
            handleUnlocked();
        }
        function onSessionResumed() {
            if (!SessionService.locked && !SettingsData.lockBeforeSuspend)
                handleUnlocked();
        }
    }

    // Single-shot: the old 250 ms poll fired 80 times per shell start just to
    // clear a pair of booleans.
    Timer {
        id: bootGuardTimer
        interval: 20000
        repeat: false
        onTriggered: root.endStartupSuppression()
    }

    Timer {
        id: dateCheckTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            const newDateKey = formatDateKey(new Date());
            if (newDateKey !== root.currentDateKey) {
                root.currentDateKey = newDateKey;
                if (pluginService)
                    loadLast7Days();
            }
            checkCycleReset();
        }
    }

    function formatDateKey(date) {
        const year = date.getFullYear();
        const month = (date.getMonth() + 1).toString().padStart(2, '0');
        const day = date.getDate().toString().padStart(2, '0');
        return year + "-" + month + "-" + day;
    }

    function loadLast7Days() {
        if (!pluginService)
            return;
        let data = [];
        const today = new Date();

        for (let i = 6; i >= 0; i--) {
            const date = new Date(today);
            date.setDate(today.getDate() - i);
            const dateKey = formatDateKey(date);

            const count = pluginService.loadPluginState(statePluginId, "completedPomodoros-" + dateKey, 0) || 0;

            data.push({
                date: dateKey,
                count: count,
                dayLabel: i === 0 ? root.tr("Today", "Hoy") : [root.tr("Sun", "Dom"), root.tr("Mon", "Lun"), root.tr("Tue", "Mar"), root.tr("Wed", "Mié"), root.tr("Thu", "Jue"), root.tr("Fri", "Vie"), root.tr("Sat", "Sáb")][date.getDay()]
            });
        }

        last7DaysData = data;
    }

    // Only the instance that owns the running session may re-base the
    // countdown. A second bar instance loading with its fallback duration
    // used to rewrite the globals and cut the session short.
    onWorkDurationChanged: {
        if (globalTimerOwnerId.value !== root.instanceId)
            return;
        if (globalTimerState.value === "work" && globalTotalSeconds.value > 0) {
            const newTotal = workDuration * 60;
            const elapsed = globalTotalSeconds.value - globalRemainingSeconds.value;
            globalTotalSeconds.set(newTotal);
            globalRemainingSeconds.set(Math.max(1, newTotal - elapsed));
        }
    }

    onShortBreakDurationChanged: {
        if (globalTimerOwnerId.value !== root.instanceId)
            return;
        if (globalTimerState.value === "shortBreak" && globalTotalSeconds.value > 0) {
            const newTotal = shortBreakDuration * 60;
            const elapsed = globalTotalSeconds.value - globalRemainingSeconds.value;
            globalTotalSeconds.set(newTotal);
            globalRemainingSeconds.set(Math.max(1, newTotal - elapsed));
        }
    }

    onLongBreakDurationChanged: {
        if (globalTimerOwnerId.value !== root.instanceId)
            return;
        if (globalTimerState.value === "longBreak" && globalTotalSeconds.value > 0) {
            const newTotal = longBreakDuration * 60;
            const elapsed = globalTotalSeconds.value - globalRemainingSeconds.value;
            globalTotalSeconds.set(newTotal);
            globalRemainingSeconds.set(Math.max(1, newTotal - elapsed));
        }
    }

    PluginGlobalVar {
        id: globalRemainingSeconds
        varName: "remainingSeconds"
        defaultValue: 0
    }

    PluginGlobalVar {
        id: globalTotalSeconds
        varName: "totalSeconds"
        defaultValue: 0
    }

    PluginGlobalVar {
        id: globalIsRunning
        varName: "isRunning"
        defaultValue: false
    }

    PluginGlobalVar {
        id: globalTimerState
        varName: "timerState"
        defaultValue: "work"
    }

    PluginGlobalVar {
        id: globalCompletedPomodoros
        varName: "completedPomodoros"
        defaultValue: 0
    }

    PluginGlobalVar {
        id: globalTimerOwnerId
        varName: "timerOwnerId"
        defaultValue: ""
    }

    PluginGlobalVar {
        id: globalTimerDisplayActive
        varName: "timerDisplayActive"
        defaultValue: false
    }

    // Away bookkeeping is shared: both bar instances receive the lock/unlock
    // signals, so the first one to act wins and the other becomes a no-op.
    PluginGlobalVar {
        id: globalAwayActive
        varName: "awayActive"
        defaultValue: false
    }

    PluginGlobalVar {
        id: globalAwayStartMs
        varName: "awayStartMs"
        defaultValue: 0
    }

    PluginGlobalVar {
        id: globalAwaySnapshot
        varName: "awaySnapshot"
        defaultValue: null
    }

    PluginGlobalVar {
        id: globalAwayCause
        varName: "awayCause"
        defaultValue: "lock"
    }

    PluginGlobalVar {
        id: globalShowSecondsOnly
        varName: "showSecondsOnly"
        defaultValue: false
    }

    // One bar instance per screen loads this plugin. Without a shared stamp
    // the second instance re-ran the session reset a moment after the first
    // had auto-started, leaving a paused, invisible timer.
    PluginGlobalVar {
        id: globalInitAt
        varName: "initAt"
        defaultValue: 0
    }

    property bool initializationOwner: false

    // Both bar instances receive every unlock signal. Without this stamp each
    // of them replayed the deferred modal / auto-start logic on its own.
    PluginGlobalVar {
        id: globalUnlockHandledAt
        varName: "unlockHandledAt"
        defaultValue: 0
    }

    property string instanceId: Math.random().toString(36).substring(2)
    readonly property string statePluginId: "dmsKetchup"

    // PluginService.setGlobalVar always rebuilds the global object and emits
    // globalVarChanged, even for an identical value. Only write on changes.
    function setShowSecondsOnly(value) {
        if (globalShowSecondsOnly.value !== value)
            globalShowSecondsOnly.set(value);
    }

    Timer {
        id: pomodoroTimer
        interval: 1000
        repeat: true
        running: globalIsRunning.value && globalTimerOwnerId.value === root.instanceId
        onTriggered: {
            if (globalRemainingSeconds.value > 0) {
                globalRemainingSeconds.set(globalRemainingSeconds.value - 1);
                if (root.preWarningWindow)
                    root.preWarningCountdown = globalRemainingSeconds.value;
                if (globalRemainingSeconds.value < 60) {
                    if (!globalShowSecondsOnly.value) {
                        globalShowSecondsOnly.set(true);
                        root.blinkVisible = true;
                    }
                } else {
                    root.setShowSecondsOnly(false);
                }
                if (root.enablePreWarning && !root.isPreWarning && globalTimerState.value === "work" && globalRemainingSeconds.value === root.preWarningTime) {
                    root.showPreWarning();
                }
            } else {
                root.timerComplete();
            }
        }
    }

    function timerComplete() {
        globalIsRunning.set(false);
        root.closePreWarning();

        if (globalTimerState.value === "work") {
            globalCompletedPomodoros.set(globalCompletedPomodoros.value + 1);
            if (pluginService) {
                const dateKey = formatDateKey(new Date());
                const statKey = "completedPomodoros-" + dateKey;
                const todayCount = (pluginService.loadPluginState(statePluginId, statKey, 0) || 0) + 1;
                pluginService.savePluginState(statePluginId, statKey, todayCount);
                pluginService.savePluginState(statePluginId, "cycleCounter", globalCompletedPomodoros.value);
                root.loadLast7Days();
            }
            const isLongBreak = globalCompletedPomodoros.value % root.sessionsPerLongBreak === 0;
            root.startCycleBreak(isLongBreak);
        } else {
            root.finishBreak();
        }
    }

    function notify(title, body) {
        // Direct argv: no shell, no quote escaping, one fewer process.
        if (!SessionData.doNotDisturb && !root.sessionLocked)
            Quickshell.execDetached(["notify-send", "-u", "normal", title, body]);
    }

    function startCycleBreak(isLongBreak, interrupted) {
        const notifTitle = interrupted
            ? root.tr("DMS Ketchup", "DMS Ketchup")
            : root.tr("DMS Ketchup Complete", "DMS Ketchup completo");
        const notifBody = root.tr("Time for a " + (isLongBreak ? "long" : "short") + " break!", "¡Es hora de un descanso " + (isLongBreak ? "largo" : "corto") + "!");
        // No desktop notification over the lock screen: the lock widget
        // shows the state and the sound still plays.
        root.notify(notifTitle, notifBody);
        root.playTimerSound("end");

        if (root.autoSetDND)
            SessionData.setDoNotDisturb(false);

        root.breakModalArmed = true;
        const autoStart = root.fullscreenBreakModalEnabled ? true : root.autoStartBreaks;
        root.startBreak(isLongBreak ? "longBreak" : "shortBreak", autoStart, false, true);
    }

    function finishBreak() {
        // No desktop notification over the lock screen: the lock widget
        // shows the state and the sound still plays.
        root.notify(root.tr("Break Complete", "Descanso completo"), root.tr("Ready for another pomodoro?", "¿Listo para otro ciclo?"));
        root.playTimerSound("end");
        if (root.fullscreenBreakModalEnabled && root.requireManualContinueAfterBreak) {
            breakModalPhase = "complete";
            if (root.sessionLocked || root.startupGuard) {
                root.deferredBreakModalPhase = "complete";
            } else {
                breakModalOpen = true;
            }
        } else {
            root.breakModalArmed = false;
            root.startWork(root.autoStartPomodoros, true);
        }
    }

    function playSoundFile(localPath) {
        if (!localPath)
            return;
        if (!root.soundPlayer) {
            // Probe still running (or no player found): play it as soon as
            // the probe reports a binary.
            if (!root.soundPlayerResolved)
                root.pendingSoundPath = localPath;
            return;
        }
        Quickshell.execDetached([root.soundPlayer, localPath]);
    }

    function playTimerSound(kind) {
        if (!root.soundsEnabled)
            return;

        const soundUrl = kind === "start" ? root.startWorkSoundUrl : root.endWorkSoundUrl;
        if (!soundUrl)
            return;

        const localPath = soundUrl.startsWith("file://") ? soundUrl.substring(7) : soundUrl;
        root.playSoundFile(localPath);
    }

    function closeBreakModal() {
        breakModalOpen = false;
        breakModalPhase = "hidden";
    }

    function openBreakModal(phase) {
        if (!root.fullscreenBreakModalEnabled)
            return;
        if (!root.breakModalArmed)
            return;
        if (Date.now() < root.bootModalSuppressUntil)
            return;
        if (root.sessionLocked || root.startupGuard) {
            root.deferredBreakModalPhase = phase;
            return;
        }
        breakModalPhase = phase;
        breakModalOpen = true;
    }

    function continueWorkingAfterBreak() {
        closeBreakModal();
        if (globalTimerState.value === "work")
            return;
        root.startWork(true, true);
    }

    function toggleBreakPause() {
        if (globalTimerState.value !== "shortBreak" && globalTimerState.value !== "longBreak")
            return;
        const resume = !globalIsRunning.value;
        globalTimerOwnerId.set(root.instanceId);
        globalIsRunning.set(resume);
        if (resume)
            root.pauseMediaPlayers();
    }

    function stopBreakAndContinue() {
        closeBreakModal();
        root.startWork(true, true);
    }

    function showPreWarning() {
        if (root.isPreWarning || !root.enablePreWarning)
            return;
        // Off-screen sessions keep running behind the lock screen; an OSD
        // there would land on top of the lock layer.
        if (root.sessionLocked)
            return;
        root.isPreWarning = true;
        root.preWarningCountdown = globalRemainingSeconds.value;
        if (root.preWarningWindow) {
            root.preWarningWindow.destroy();
            root.preWarningWindow = null;
        }
        if (!root.preWarningComponent)
            root.preWarningComponent = Qt.createComponent("DMSKetchupPreWarningToast.qml");
        if (root.preWarningComponent.status === Component.Ready) {
            root.preWarningWindow = root.preWarningComponent.createObject(root, { "pluginRoot": root });
            if (!root.preWarningWindow) {
                console.warn("[dms-ketchup] failed to create pre-warning toast");
                root.isPreWarning = false;
            }
        } else {
            console.warn("[dms-ketchup] pre-warning toast error:", root.preWarningComponent.errorString());
            root.isPreWarning = false;
        }
    }

    function closePreWarning() {
        if (root.preWarningWindow) {
            root.preWarningWindow.destroy();
            root.preWarningWindow = null;
        }
        root.isPreWarning = false;
    }

    function snoozeWork() {
        root.closePreWarning();
        if (globalTimerState.value === "work") {
            globalTotalSeconds.set(globalTotalSeconds.value + 300);
            globalRemainingSeconds.set(globalRemainingSeconds.value + 300);
        }
    }

    function skipWork() {
        root.closePreWarning();
        if (globalTimerState.value !== "work")
            return;
        globalIsRunning.set(false);
        root.startCycleBreak(cycleBreakIsLong());
    }

    function beginAway(cause) {
        if (globalAwayActive.value) {
            if (cause === "suspend" && globalAwayCause.value !== "suspend")
                globalAwayCause.set("suspend");
            return;
        }
        const state = globalTimerState.value;
        if (state === "work") {
            const snapshot = {
                kind: "work",
                remaining: globalRemainingSeconds.value,
                total: globalTotalSeconds.value,
                wasRunning: globalIsRunning.value
            };
            globalAwaySnapshot.set(snapshot);
            globalAwayActive.set(true);
            globalAwayStartMs.set(Date.now());
            globalAwayCause.set(cause);
            globalIsRunning.set(false);
            root.closePreWarning();
            console.info("[dms-ketchup] beginAway", "cause=", cause, "remaining=", snapshot.remaining, "total=", snapshot.total, "wasRunning=", snapshot.wasRunning);
        } else if ((state === "shortBreak" || state === "longBreak") && cause === "suspend") {
            const snapshot = {
                kind: "break",
                remaining: globalRemainingSeconds.value,
                total: globalTotalSeconds.value,
                wasRunning: globalIsRunning.value
            };
            globalAwaySnapshot.set(snapshot);
            globalAwayActive.set(true);
            globalAwayStartMs.set(Date.now());
            globalAwayCause.set(cause);
            globalIsRunning.set(false);
            root.closePreWarning();
            console.info("[dms-ketchup] beginAway", "cause=", cause, "break=", state, "remaining=", snapshot.remaining);
        }
    }

    function endAway() {
        if (!globalAwayActive.value)
            return;
        const awayMs = Date.now() - globalAwayStartMs.value;
        const snapshot = globalAwaySnapshot.value;
        const cause = globalAwayCause.value;
        globalAwayActive.set(false);
        globalAwayStartMs.set(0);
        globalAwaySnapshot.set(null);
        globalAwayCause.set("lock");
        console.info("[dms-ketchup] endAway", "awayMs=", awayMs, "cause=", cause);
        applyAwayLogic(awayMs, snapshot);
    }

    // The user took over from the lock screen — the pending away bookkeeping is
    // stale and must not reset/repeat the session on unlock.
    function cancelAway() {
        if (!globalAwayActive.value)
            return;
        globalAwayActive.set(false);
        globalAwayStartMs.set(0);
        globalAwaySnapshot.set(null);
        globalAwayCause.set("lock");
        console.info("[dms-ketchup] cancelAway");
    }

    function applyAwayLogic(awayMs, snapshot) {
        if (!snapshot)
            return;
        if (snapshot.kind === "work") {
            if (awayMs >= longBreakDuration * 60 * 1000) {
                console.info("[dms-ketchup] applyAwayLogic", ">= long break: reset cycle + fresh session");
                resetPomodoroCycle();
                root.startWork(true, true);
            } else if (awayMs >= shortBreakDuration * 60 * 1000) {
                console.info("[dms-ketchup] applyAwayLogic", ">= short break: cycle break, session does not count");
                root.startCycleBreak(cycleBreakIsLong(), true);
            } else {
                console.info("[dms-ketchup] applyAwayLogic", "< short break: restore countdown");
                globalTotalSeconds.set(snapshot.total);
                globalRemainingSeconds.set(snapshot.remaining);
                if (snapshot.wasRunning)
                    globalTimerOwnerId.set(root.instanceId);
                globalIsRunning.set(snapshot.wasRunning);
            }
        } else if (snapshot.kind === "break") {
            const awaySecs = Math.floor(awayMs / 1000);
            const remaining = snapshot.remaining - awaySecs;
            if (remaining <= 0) {
                console.info("[dms-ketchup] applyAwayLogic", "break expired during away: finish break");
                root.finishBreak();
            } else {
                console.info("[dms-ketchup] applyAwayLogic", "continue break, remaining=", remaining);
                globalTotalSeconds.set(snapshot.total);
                globalRemainingSeconds.set(remaining);
                root.setShowSecondsOnly(remaining < 60);
                if (snapshot.wasRunning)
                    globalTimerOwnerId.set(root.instanceId);
                globalIsRunning.set(snapshot.wasRunning);
            }
        }
    }

    function cycleBreakIsLong() {
        return globalCompletedPomodoros.value > 0 && globalCompletedPomodoros.value % root.sessionsPerLongBreak === 0;
    }

    function checkCycleReset() {
        if (!pluginService)
            return;
        const now = new Date();
        const resetMoment = new Date(now);
        resetMoment.setHours(root.cycleResetHour, 0, 0, 0);
        if (now < resetMoment)
            return;
        const todayKey = formatDateKey(now);
        const lastReset = pluginService.loadPluginState(statePluginId, "cycleResetDate", "");
        if (lastReset === todayKey)
            return;
        globalCompletedPomodoros.set(0);
        pluginService.savePluginState(statePluginId, "cycleCounter", 0);
        pluginService.savePluginState(statePluginId, "cycleResetDate", todayKey);
        console.info("[dms-ketchup] cycle counter reset at", root.cycleResetHour + ":00");
    }

    function handleUnlocked() {
        root.sessionLocked = false;
        // Both bar instances receive the unlock signals. Only the first one
        // may replay the away/deferred-modal logic; otherwise the modal is
        // opened twice and the next work session is started twice.
        const now = Date.now();
        if (now - globalUnlockHandledAt.value < 2000)
            return;
        globalUnlockHandledAt.set(now);

        // Only apply the away reset/repeat logic when the session is still
        // paused. A session that was resumed from the lock screen is a
        // deliberate "I'm working" signal, so it simply continues.
        if (globalIsRunning.value)
            root.cancelAway();
        else
            root.endAway();
        // A break that finished while the screen was locked either deferred its
        // modal (probe/startup path) or opened it directly behind the lock
        // screen (default loginctl-signal path) — catch both.
        const breakFinished = root.deferredBreakModalPhase === "complete"
            || (root.breakModalOpen && root.breakModalPhase === "complete");
        if (root.autoStartWorkOnUnlock && breakFinished) {
            root.deferredBreakModalPhase = "";
            root.breakModalArmed = false;
            root.closeBreakModal();
            root.startWork(true, true);
            return;
        }
        if (root.deferredBreakModalPhase !== "") {
            let phase = root.deferredBreakModalPhase;
            root.deferredBreakModalPhase = "";
            // Don't let a stale "running" phase downgrade a break that
            // actually finished behind the lock screen.
            if (root.breakModalOpen && root.breakModalPhase === "complete")
                phase = "complete";
            openBreakModal(phase);
        } else if (root.autoStartWorkOnUnlock && !globalTimerDisplayActive.value) {
            // No session running at all (fresh boot or reset) — start one
            root.startWork(true, true);
        } else if (root.autoStartWorkOnUnlock
                   && globalTimerState.value === "work"
                   && !globalIsRunning.value) {
            // The user paused the work session before locking. "Start
            // pomodoro on unlock" means the session must be running again;
            // resume it (keeping the remaining time) instead of leaving a
            // paused timer behind the unlock.
            root.toggleTimer();
        }
    }

    function resetPomodoroCycle() {
        globalCompletedPomodoros.set(0);
        if (pluginService) {
            pluginService.savePluginState(statePluginId, "cycleCounter", 0);
        }
    }

    // ── Lock-screen controls ──────────────────────────────────────────
    // The lock widget has no engine of its own: it drives the timer through
    // these IPC functions, so there is still exactly one session owner.
    function lockStart() {
        root.cancelAway();
        root.deferredBreakModalPhase = "";
        root.breakModalArmed = false;
        root.startWork(true, true);
    }

    function lockResume() {
        root.cancelAway();
        if (!globalIsRunning.value)
            root.toggleTimer();
    }

    function lockPause() {
        if (!globalIsRunning.value)
            return;
        if ((root.sessionLocked || SessionService.locked) && !globalAwayActive.value && globalTimerState.value === "work") {
            // "As if I locked the screen now": snapshot + pause from this point
            root.beginAway("lock");
            return;
        }
        globalIsRunning.set(false);
        root.closePreWarning();
    }

    function lockContinue() {
        // Same session outcome as unlocking after a finished break: clear the
        // deferred modal so unlocking later does not handle it twice.
        root.cancelAway();
        root.deferredBreakModalPhase = "";
        root.breakModalArmed = false;
        root.closeBreakModal();
        root.startWork(true, true);
    }

    // ── Motivational phrases ──────────────────────────────────────────
    // Loaded from translations/<lang>.json so the phrase language can be
    // chosen independently of the system language. The candidate chain
    // (full locale → hyphen variant → language → en) is walked with
    // `cat` because FileView does not report missing files reliably.
    function phraseFilePath(lang) {
        const dir = pluginService ? pluginService.getPluginPath(statePluginId) : "";
        if (!dir)
            return "";
        return dir + "/translations/" + lang + ".json";
    }

    function phraseLoadCandidate() {
        if (phraseCandidateIndex >= phraseCandidates.length) {
            console.warn("[dms-ketchup] no phrase translations found for", phraseLanguage);
            return;
        }
        const path = phraseFilePath(phraseCandidates[phraseCandidateIndex]);
        // Proc.runCommand keys callbacks by id, so a shared id makes the two
        // bar instances overwrite each other and only one loads phrases.
        Proc.runCommand("dmsKetchup.readPhrases." + root.instanceId, ["sh", "-c",
            "cat \"" + path + "\" 2>/dev/null || true"
        ], (stdout) => {
            let ok = false;
            const content = (stdout || "").trim();
            if (content) {
                try {
                    const table = JSON.parse(content);
                    const tips = table && table.tips ? Object.values(table.tips) : [];
                    if (tips.length > 0) {
                        phraseTips = tips;
                        ok = true;
                        console.info("[dms-ketchup] phrases loaded from", path, "count=", tips.length);
                    }
                } catch (e) {
                    console.warn("[dms-ketchup] bad phrase translations", path, e);
                }
            }
            if (!ok) {
                phraseCandidateIndex++;
                phraseLoadCandidate();
            }
        });
    }

    function loadPhrases() {
        phraseTips = [];
        phraseCandidateIndex = 0;
        if (phraseLanguage === "system") {
            const full = I18n.locale().name;
            const lang = full ? full.split(/[_-]/)[0] : "en";
            phraseCandidates = [full, full.replace("_", "-"), lang, "en"].filter((value, index, self) => self.indexOf(value) === index);
        } else {
            phraseCandidates = [phraseLanguage, "en"];
        }
        phraseLoadCandidate();
    }

    onPhraseLanguageChanged: Qt.callLater(loadPhrases)

    function startWork(autoStart, playSoundNow = true) {
        const running = autoStart ?? false;
        globalTimerState.set("work");
        const total = root.workDuration * 60;
        globalTotalSeconds.set(total);
        globalRemainingSeconds.set(total);
        root.setShowSecondsOnly(total < 60);
        root.preWarningCountdown = total;
        root.closePreWarning();
        globalTimerOwnerId.set(root.instanceId);
        globalIsRunning.set(running);
        if (running || playSoundNow)
            globalTimerDisplayActive.set(true);
        if (root.autoSetDND)
            SessionData.setDoNotDisturb(running);
        if (playSoundNow)
            root.playTimerSound("start");
        root.breakModalArmed = false;
        root.closeBreakModal();
    }

    function pauseMediaPlayers() {
        if (!root.pauseMediaDuringBreaks)
            return;
        let paused = 0;
        const players = (typeof MprisController !== "undefined" && MprisController) ? (MprisController.availablePlayers || []) : [];
        for (let i = 0; i < players.length; i++) {
            const player = players[i];
            if (player && player.isPlaying && player.canPause) {
                player.pause();
                paused++;
            }
        }
        if (paused > 0)
            console.info("[dms-ketchup] paused", paused, "media player(s) for the break");
    }

    function startBreak(kind, autoStart, openModal, playSoundNow) {
        const running = autoStart ?? false;
        root.closePreWarning();
        if (root.autoSetDND)
            SessionData.setDoNotDisturb(false);
        root.breakModalArmed = true;
        globalTimerState.set(kind);
        const total = (kind === "longBreak" ? root.longBreakDuration : root.shortBreakDuration) * 60;
        globalTotalSeconds.set(total);
        globalRemainingSeconds.set(total);
        root.setShowSecondsOnly(total < 60);
        globalTimerOwnerId.set(root.instanceId);
        globalIsRunning.set(running);
        if (running)
            root.pauseMediaPlayers();
        if (running || playSoundNow)
            globalTimerDisplayActive.set(true);
        if (playSoundNow)
            root.playTimerSound("start");
        if (root.fullscreenBreakModalEnabled && (openModal || running)) {
            if (root.sessionLocked || root.startupGuard)
                root.deferredBreakModalPhase = "running";
            else
                root.openBreakModal("running");
        }
    }

    function startShortBreak(autoStart, openModal = false, playSoundNow = true) {
        root.startBreak("shortBreak", autoStart, openModal, playSoundNow);
    }

    function startLongBreak(autoStart, openModal = false, playSoundNow = true) {
        root.startBreak("longBreak", autoStart, openModal, playSoundNow);
    }

    function toggleTimer() {
        if (!globalIsRunning.value) {
            globalTimerOwnerId.set(root.instanceId);
            globalTimerDisplayActive.set(true);
            if (root.fullscreenBreakModalEnabled && globalTimerState.value !== "work" && !root.sessionLocked)
                root.openBreakModal("running");
        } else {
            // A paused session must not leave a stale pre-warning toast behind.
            root.closePreWarning();
        }
        globalIsRunning.set(!globalIsRunning.value);
        if (globalIsRunning.value && globalTimerState.value !== "work")
            root.pauseMediaPlayers();
        if (root.autoSetDND && globalTimerState.value === "work")
            SessionData.setDoNotDisturb(globalIsRunning.value);
    }

    function resetTimer() {
        globalIsRunning.set(false);
        root.closePreWarning();
        if (root.autoSetDND && globalTimerState.value === "work")
            SessionData.setDoNotDisturb(false);
        globalRemainingSeconds.set(globalTotalSeconds.value);
        root.setShowSecondsOnly(globalRemainingSeconds.value < 60);
        globalTimerDisplayActive.set(false);
        root.closeBreakModal();
    }

    function getCountdownText(seconds, isVertical = false, barOnlyMinutes = false) {
        if (!globalIsRunning.value && seconds === 0) {
            const totalSecs = root.workDuration * 60;
            const totalMins = Math.floor(totalSecs / 60);
            const secs = totalSecs % 60;
            return isVertical ? totalMins + "\n" + (secs < 10 ? "0" : "") + secs : totalMins + ":" + (secs < 10 ? "0" : "") + secs;
        }
        if (seconds < 60 && globalShowSecondsOnly.value) {
            return seconds.toString();
        }
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        if (seconds >= 60 && barOnlyMinutes) {
            return mins.toString();
        }
        if (isVertical) {
            return mins + "\n" + (secs < 10 ? "0" : "") + secs;
        } else {
            return mins + ":" + (secs < 10 ? "0" : "") + secs;
        }
    }

    function getStateColor() {
        if (!globalIsRunning.value && globalRemainingSeconds.value === 0 && globalTotalSeconds.value === 0)
            return Theme.surfaceText;
        if (globalTimerState.value === "work")
            return Theme.primary;
        if (globalTimerState.value === "shortBreak")
            return Theme.info;
        return Theme.warning;
    }

    function getStateIcon() {
        if (globalTimerState.value === "work")
            return "work";
        if (globalTimerState.value === "longBreak")
            return "weekend";
        return "coffee";
    }

    IpcHandler {
        function resetTimer(): string {
            root.resetTimer();
            return "POMODORO_TIME_RESET_SUCCESS";
        }

        function status(): string {
            return JSON.stringify({
                state: globalTimerState.value,
                running: globalIsRunning.value,
                remaining: globalRemainingSeconds.value,
                total: globalTotalSeconds.value,
                displayActive: globalTimerDisplayActive.value,
                completed: globalCompletedPomodoros.value,
                modalOpen: root.breakModalOpen,
                modalPhase: root.breakModalPhase,
                locked: root.sessionLocked,
                deferredPhase: root.deferredBreakModalPhase
            });
        }

        function toggleTimer(): string {
            root.toggleTimer();
            return globalIsRunning.value ? "Timer is running" : "Timer is paused";
        }

        function startWork(): string {
            root.startWork(true, true);
            return "POMODORO_WORK_STARTED";
        }

        function startShortBreak(): string {
            root.startShortBreak(true, false, true);
            return "POMODORO_SHORT_BREAK_STARTED";
        }

        function startLongBreak(): string {
            root.startLongBreak(true, false, true);
            return "POMODORO_LONG_BREAK_STARTED";
        }

        // Lock-screen widget actions (see DMSKetchupLockWidget.qml)
        function lockStart(): string {
            root.lockStart();
            return "LOCK_WORK_STARTED";
        }

        function lockPause(): string {
            root.lockPause();
            return globalIsRunning.value ? "LOCK_PAUSE_IGNORED" : "LOCK_TIMER_PAUSED";
        }

        function lockResume(): string {
            root.lockResume();
            return globalIsRunning.value ? "LOCK_TIMER_RESUMED" : "LOCK_RESUME_IGNORED";
        }

        function lockContinue(): string {
            root.lockContinue();
            return "LOCK_WORK_CONTINUED";
        }

        target: "pomodoroTimer"
    }

    horizontalBarPill: Component {
         Row {
             spacing: Theme.spacingXS

              DankIcon {
                  name: globalTimerDisplayActive.value ? root.getStateIcon() : "timer"
                  size: Theme.barIconSize(root.barThickness)
                  color: globalTimerDisplayActive.value ? root.getStateColor() : Theme.widgetIconColor
                  anchors.verticalCenter: parent.verticalCenter
              }

              StyledText {
                  visible: globalTimerDisplayActive.value
                  text: root.getCountdownText(globalRemainingSeconds.value, false, true)
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                  font.weight: Theme.fontWeightMedium
                  color: globalShowSecondsOnly.value ? Theme.primary : Theme.surfaceVariantText
                  opacity: globalShowSecondsOnly.value ? (root.blinkVisible ? 1.0 : 0.0) : 1.0
                  anchors.verticalCenter: parent.verticalCenter
              }
         }
     }

     verticalBarPill: Component {
         Column {
             spacing: Theme.spacingXS

              DankIcon {
                  name: globalTimerDisplayActive.value ? root.getStateIcon() : "timer"
                  size: Theme.barIconSize(root.barThickness)
                  color: globalTimerDisplayActive.value ? root.getStateColor() : Theme.widgetIconColor
                  anchors.horizontalCenter: parent.horizontalCenter
              }

              StyledText {
                  visible: globalTimerDisplayActive.value
                  text: root.getCountdownText(globalRemainingSeconds.value, true, true)
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale)
                  font.weight: Theme.fontWeightMedium
                  color: globalShowSecondsOnly.value ? Theme.primary : Theme.surfaceVariantText
                  opacity: globalShowSecondsOnly.value ? (root.blinkVisible ? 1.0 : 0.0) : 1.0
                  anchors.horizontalCenter: parent.horizontalCenter
              }
         }
     }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            headerText: root.tr("DMS Ketchup", "DMS Ketchup")
            detailsText: {
                if (globalTimerState.value === "work")
                    return root.tr("Focus session • " + globalCompletedPomodoros.value + " completed", "Sesión de enfoque • " + globalCompletedPomodoros.value + " completadas");
                if (globalTimerState.value === "shortBreak")
                    return root.fullscreenBreakModalEnabled ? root.tr("Break running in fullscreen", "Descanso en pantalla completa") : root.tr("Short break", "Desc. corto");
                return root.fullscreenBreakModalEnabled ? root.tr("Break running in fullscreen", "Descanso en pantalla completa") : root.tr("Long break", "Desc. largo");
            }
            showCloseButton: true

            Column {
                id: popoutContentColumn
                width: parent.width
                spacing: Theme.spacingM

                Item {
                    width: parent.width
                    height: 180

                    Rectangle {
                        width: 180
                        height: 180
                        radius: 90
                        anchors.centerIn: parent
                        color: "transparent"
                        border.width: 8
                        border.color: Qt.rgba(root.getStateColor().r, root.getStateColor().g, root.getStateColor().b, 0.2)

                        Canvas {
                            id: progressCanvas
                            width: parent.width - 16
                            height: parent.height - 16
                            anchors.centerIn: parent

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                ctx.lineWidth = 8;
                                ctx.lineCap = "round";
                                ctx.strokeStyle = root.getStateColor();
                                ctx.beginPath();
                                const centerX = width / 2;
                                const centerY = height / 2;
                                const radius = (width - 8) / 2;
                                const progress = (globalTotalSeconds.value > 0) ? globalRemainingSeconds.value / globalTotalSeconds.value : 0;
                                const startAngle = -Math.PI / 2;
                                const endAngle = startAngle + (2 * Math.PI * progress);
                                ctx.arc(centerX, centerY, radius, startAngle, endAngle, false);
                                ctx.stroke();
                            }

                            Connections {
                                target: globalRemainingSeconds
                                function onValueChanged() {
                                    progressCanvas.requestPaint();
                                }
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            StyledText {
                                text: root.getCountdownText(globalRemainingSeconds.value)
                                font.family: "monospace"
                                font.pixelSize: 36
                                font.weight: Font.Bold
                                color: root.getStateColor()
                                anchors.horizontalCenter: parent.horizontalCenter
                                horizontalAlignment: Text.AlignHCenter
                                width: 120
                            }

                            StyledText {
                                text: {
                                    if (globalTimerState.value === "work")
                                        return root.tr("Work", "Trabajo");
                                    if (globalTimerState.value === "shortBreak")
                                        return root.tr("Short break", "Desc. corto");
                                    return root.tr("Long break", "Desc. largo");
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.spacingM

                    Rectangle {
                        width: 64
                        height: 64
                        radius: 32
                        color: root.getStateColor()
                        opacity: playArea.containsMouse ? 0.88 : 1

                        DankIcon {
                            anchors.centerIn: parent
                            name: globalIsRunning.value ? "pause" : "play_arrow"
                            size: 32
                            color: Theme.primaryText
                        }

                        MouseArea {
                            id: playArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleTimer()
                        }
                    }

                    Rectangle {
                        width: 56
                        height: 56
                        radius: 28
                        anchors.verticalCenter: parent.verticalCenter
                        color: resetArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainer

                        DankIcon {
                            anchors.centerIn: parent
                            name: "refresh"
                            size: 22
                            color: Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: resetArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetTimer()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: root.tr("Quick Actions", "Acciones rápidas")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    // Keep the three actions on one line, sized to their
                    // labels. The reduced padding leaves enough room for the
                    // full "Short break" / "Long break" text at the default
                    // 400 px popout width, even with a wide theme font.
                    Item {
                        width: parent.width
                        height: quickActionsRow.implicitHeight

                        Row {
                            id: quickActionsRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingS

                            DankButton {
                                text: root.tr("Work", "Trabajo")
                                iconName: "work"
                                horizontalPadding: Theme.spacingS
                                onClicked: root.startWork(true)
                            }

                            DankButton {
                                text: root.tr("Short break", "Desc. corto")
                                iconName: "coffee"
                                horizontalPadding: Theme.spacingS
                                onClicked: root.startShortBreak(false)
                            }

                            DankButton {
                                text: root.tr("Long break", "Desc. largo")
                                iconName: "weekend"
                                horizontalPadding: Theme.spacingS
                                onClicked: root.startLongBreak(false)
                            }
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: statsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: statsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS

                        Row {
                            spacing: Theme.spacingM

                            DankIcon {
                                name: "check_circle"
                                size: Theme.iconSize
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: root.tr(globalCompletedPomodoros.value + " sessions completed", globalCompletedPomodoros.value + " sesiones completadas")
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            text: root.tr("Next long break after " + (root.sessionsPerLongBreak - (globalCompletedPomodoros.value % root.sessionsPerLongBreak)) + " more", "El siguiente descanso largo después de " + (root.sessionsPerLongBreak - (globalCompletedPomodoros.value % root.sessionsPerLongBreak)) + " más")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            leftPadding: Theme.iconSize + Theme.spacingM
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: last7DaysColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        id: last7DaysColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        StyledText {
                            text: root.tr("Last 7 Days", "Últimos 7 días")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingXS
                            height: 60

                            Repeater {
                                model: root.last7DaysData

                                Item {
                                    width: (parent.width - (parent.spacing * 6)) / 7
                                    height: parent.height

                                    Column {
                                        anchors.fill: parent
                                        spacing: Theme.spacingXS

                                        Item {
                                            width: parent.width
                                            height: 40

                                            Rectangle {
                                                width: parent.width
                                                height: 2
                                                anchors.bottom: parent.bottom
                                                radius: 1
                                                color: Qt.rgba(root.getStateColor().r, root.getStateColor().g, root.getStateColor().b, 0.2)
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: {
                                                    let maxCount = 1;
                                                    for (let i = 0; i < root.last7DaysData.length; i++) {
                                                        if (root.last7DaysData[i].count > maxCount) {
                                                            maxCount = root.last7DaysData[i].count;
                                                        }
                                                    }
                                                    const barHeight = (modelData.count / maxCount) * (parent.height - 2);
                                                    return Math.max(barHeight, modelData.count > 0 ? 4 : 0);
                                                }
                                                anchors.bottom: parent.bottom
                                                radius: 2
                                                color: modelData.dayLabel === root.tr("Today", "Hoy") ? root.getStateColor() : Qt.rgba(root.getStateColor().r, root.getStateColor().g, root.getStateColor().b, 0.6)

                                                StyledText {
                                                    text: modelData.count > 0 ? modelData.count : ""
                                                    font.pixelSize: Theme.fontSizeSmall
                                                    color: Theme.primaryText
                                                    anchors.centerIn: parent
                                                    visible: modelData.count > 0 && parent.height > 12
                                                }
                                            }
                                        }

                                        StyledText {
                                            text: modelData.dayLabel
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: modelData.dayLabel === root.tr("Today", "Hoy") ? Theme.surfaceText : Theme.surfaceVariantText
                                            horizontalAlignment: Text.AlignHCenter
                                            width: parent.width
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    DMSKetchupFullscreenModal {
        id: breakModal
        pluginRoot: root
        isOpen: root.breakModalOpen
        phase: root.breakModalPhase
        running: globalIsRunning.value
        timerState: globalTimerState.value
        remainingSeconds: globalRemainingSeconds.value
        totalSeconds: globalTotalSeconds.value
    }
}
