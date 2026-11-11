import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Desktop widget surface, used on the DMS 2.0 lock screen and on the desktop.
// Reads the same plugin globals as the bar widget and drives it through the
// plugin IPC, so there is still exactly one timer engine.
DesktopPluginComponent {
    id: root

    property var lockHost: null
    property var screen: null

    minWidth: 240
    minHeight: 140
    property real defaultWidth: 340
    property real defaultHeight: 180

    readonly property var cfg: instanceData?.config ?? ({})
    readonly property bool active: globalTimerDisplayActive.value
    readonly property bool onLockScreen: lockScreen
    readonly property bool breakComplete: active
        && globalTimerState.value !== "work"
        && globalRemainingSeconds.value <= 0

    // Widget editor / lock-screen demo: render, but never touch the timer.
    readonly property bool interactive: !(onLockScreen && (lockHost?.demoMode ?? false))

    readonly property color contentColor: onLockScreen
        ? (lockHost?.contentColor(cfg.colorMode ?? "default", cfg.customColor ?? "#ffffff") ?? Theme.lockScreenContentColor)
        : Theme.surfaceText

    readonly property color accent: {
        if (!active)
            return contentColor;
        if (breakComplete)
            return Theme.success;
        if (globalTimerState.value === "longBreak")
            return Theme.warning;
        if (globalTimerState.value === "shortBreak")
            return Theme.info;
        return Theme.primary;
    }

    readonly property string labelFont: onLockScreen && SettingsData.lockScreenFontFamily !== ""
        ? SettingsData.lockScreenFontFamily
        : Theme.fontFamily

    // DesktopPluginComponent already keeps `pluginData` live through
    // pluginDataChanged; reading it here (instead of calling loadPluginData
    // once in a binding) also updates the card when settings change.
    readonly property real idleMinutes: {
        const raw = pluginData?.workDuration ?? 25;
        const parsed = parseFloat(String(raw).replace(",", "."));
        return isNaN(parsed) || parsed <= 0 ? 25 : parsed;
    }

    readonly property real sessionsPerLongBreak: {
        const parsed = parseInt(pluginData?.sessionsPerLongBreak ?? 4, 10);
        return isNaN(parsed) || parsed <= 0 ? 4 : parsed;
    }

    readonly property int remainingSeconds: active
        ? globalRemainingSeconds.value
        : Math.round(idleMinutes * 60)

    readonly property int totalSeconds: active && globalTotalSeconds.value > 0
        ? globalTotalSeconds.value
        : Math.round(idleMinutes * 60)

    readonly property real progress: totalSeconds > 0
        ? Math.max(0, Math.min(1, remainingSeconds / totalSeconds))
        : 1

    function tr(en, es) {
        const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
        return localeName.toLowerCase().startsWith("es") ? es : en;
    }

    function stateLabel() {
        if (!active)
            return tr("Ready", "Listo");
        if (breakComplete)
            return tr("Break complete", "Descanso completado");
        if (!globalIsRunning.value)
            return tr("Paused", "Pausado");
        if (globalTimerState.value === "work")
            return tr("Focus", "Enfoque");
        return globalTimerState.value === "longBreak"
            ? tr("Long break", "Descanso largo")
            : tr("Short break", "Descanso corto");
    }

    function countdownText() {
        const mins = Math.floor(remainingSeconds / 60);
        const secs = remainingSeconds % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    function detailText() {
        if (!active)
            return tr("No session running", "No hay sesión activa");
        const done = globalCompletedPomodoros.value % sessionsPerLongBreak;
        const cycle = done === 0
            ? (globalCompletedPomodoros.value > 0 ? sessionsPerLongBreak : 1)
            : done;
        return tr("Session " + cycle + " of " + sessionsPerLongBreak, "Sesión " + cycle + " de " + sessionsPerLongBreak);
    }

    function minutesLabel() {
        return Math.round(totalSeconds / 60) + " " + tr("min", "min");
    }

    // ── Session controls ──────────────────────────────────────────────
    function primaryAction() {
        if (!active)
            return "lockStart";
        if (breakComplete)
            return "lockContinue";
        return globalIsRunning.value ? "lockPause" : "lockResume";
    }

    function primaryIcon() {
        if (!active || breakComplete)
            return "play_arrow";
        return globalIsRunning.value ? "pause" : "play_arrow";
    }

    function primaryLabel() {
        if (!active)
            return tr("Start session", "Iniciar sesión");
        if (breakComplete)
            return tr("Continue working", "Seguir trabajando");
        return globalIsRunning.value ? tr("Pause", "Pausar") : tr("Resume", "Reanudar");
    }

    function canSkip() {
        return active && !breakComplete && globalTimerState.value !== "work";
    }

    function sendAction(action) {
        if (!interactive)
            return;
        Quickshell.execDetached(["dms", "ipc", "call", "pomodoroTimer", action]);
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
        id: globalTimerDisplayActive
        varName: "timerDisplayActive"
        defaultValue: false
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadiusL
        color: Theme.readableSurface
        border.width: Theme.layerOutlineWidth
        border.color: Theme.outlineMedium
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - Theme.spacingXL * 2
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.accent
            }

            StyledText {
                id: stateText
                text: root.stateLabel()
                font.family: root.labelFont
                font.pixelSize: Theme.fontSizeSmall
                font.letterSpacing: 1.2
                font.capitalization: Font.AllUppercase
                color: root.contentColor
                opacity: 0.72
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                width: Math.max(0, parent.width - stateText.implicitWidth - minutesText.implicitWidth - 8 - parent.spacing * 3)
                height: 1
            }

            StyledText {
                id: minutesText
                text: root.minutesLabel()
                font.family: root.labelFont
                font.pixelSize: Theme.fontSizeSmall
                color: root.contentColor
                opacity: 0.45
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        StyledText {
            text: root.countdownText()
            font.family: "monospace"
            font.pixelSize: Math.max(30, Math.min(52, Math.round(root.widgetHeight * 0.3)))
            font.weight: Font.Bold
            color: root.contentColor
        }

        StyledRect {
            width: parent.width
            height: 5
            radius: 2.5
            color: Theme.withAlpha(root.contentColor, 0.18)

            Rectangle {
                width: parent.width * root.progress
                height: parent.height
                radius: parent.radius
                color: root.accent
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                width: parent.width - controlsRow.width - parent.spacing
                text: root.detailText()
                font.family: root.labelFont
                font.pixelSize: Theme.fontSizeSmall
                color: root.contentColor
                opacity: 0.55
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }

            Row {
                id: controlsRow
                spacing: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter

                // Skip break (only while a break is actually counting down)
                Rectangle {
                    width: visible ? 34 : 0
                    height: 34
                    radius: 17
                    visible: root.canSkip()
                    color: Theme.withAlpha(root.contentColor, skipArea.containsMouse ? 0.24 : 0.12)
                    opacity: root.interactive ? 1 : 0.4

                    DankIcon {
                        anchors.centerIn: parent
                        name: "skip_next"
                        size: 18
                        color: root.contentColor
                    }

                    MouseArea {
                        id: skipArea
                        anchors.fill: parent
                        enabled: root.interactive
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: root.tr("Skip break", "Omitir descanso")
                        onClicked: root.sendAction("lockContinue")
                    }
                }

                // Play / pause / start / continue
                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: Theme.primary
                    opacity: root.interactive ? (primaryArea.containsMouse ? 0.85 : 1) : 0.4

                    DankIcon {
                        anchors.centerIn: parent
                        name: root.primaryIcon()
                        size: 18
                        color: Theme.primaryText
                    }

                    MouseArea {
                        id: primaryArea
                        anchors.fill: parent
                        enabled: root.interactive
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        Accessible.name: root.primaryLabel()
                        onClicked: root.sendAction(root.primaryAction())
                    }
                }
            }
        }
    }
}
