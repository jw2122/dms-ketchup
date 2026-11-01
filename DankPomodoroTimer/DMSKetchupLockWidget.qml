import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Desktop widget surface, used on the DMS 2.0 lock screen and on the desktop.
// Reads the same plugin globals as the bar widget, so it needs no own timer.
DesktopPluginComponent {
    id: root

    property var lockHost: null
    property var screen: null

    minWidth: 220
    minHeight: 110
    property real defaultWidth: 340
    property real defaultHeight: 160

    readonly property var cfg: instanceData?.config ?? ({})
    readonly property bool active: globalTimerDisplayActive.value
    readonly property bool onLockScreen: lockScreen

    readonly property color contentColor: onLockScreen
        ? (lockHost?.contentColor(cfg.colorMode ?? "default", cfg.customColor ?? "#ffffff") ?? Theme.lockScreenContentColor)
        : Theme.surfaceText

    readonly property color accent: {
        if (!active)
            return contentColor;
        if (globalTimerState.value === "longBreak")
            return Theme.warning;
        if (globalTimerState.value === "shortBreak")
            return Theme.info;
        return Theme.primary;
    }

    readonly property string labelFont: onLockScreen && SettingsData.lockScreenFontFamily !== ""
        ? SettingsData.lockScreenFontFamily
        : Theme.fontFamily

    readonly property real idleMinutes: {
        if (!pluginService || !pluginId)
            return 25;
        const raw = pluginService.loadPluginData(pluginId, "workDuration", 25);
        const parsed = parseFloat(String(raw).replace(",", "."));
        return isNaN(parsed) || parsed <= 0 ? 25 : parsed;
    }

    readonly property real sessionsPerLongBreak: {
        if (!pluginService || !pluginId)
            return 4;
        const raw = pluginService.loadPluginData(pluginId, "sessionsPerLongBreak", 4);
        const parsed = parseInt(raw, 10);
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
        if (globalTimerState.value === "work")
            return globalIsRunning.value ? tr("Focus", "Enfoque") : tr("Paused", "Pausado");
        if (globalRemainingSeconds.value <= 0)
            return tr("Break complete", "Descanso completado");
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

        StyledText {
            width: parent.width
            text: root.detailText()
            font.family: root.labelFont
            font.pixelSize: Theme.fontSizeSmall
            color: root.contentColor
            opacity: 0.55
            elide: Text.ElideRight
        }
    }
}
