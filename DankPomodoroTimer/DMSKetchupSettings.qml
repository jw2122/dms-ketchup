import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import Quickshell.Io
import "./dms-common"
import "."

PluginSettings {
    function tr(en, es) {
        const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
        return localeName.toLowerCase().startsWith("es") ? es : en;
    }

    id: root
    pluginId: "dmsKetchup"

    property var stats: ({ today: 0, week: 0, total: 0, contributors: [] })

    function formatDateKey(date) {
        const year = date.getFullYear();
        const month = (date.getMonth() + 1).toString().padStart(2, '0');
        const day = date.getDate().toString().padStart(2, '0');
        return year + "-" + month + "-" + day;
    }

    function refreshStats() {
        if (!pluginService)
            return;
        const today = new Date();
        const todayKey = root.formatDateKey(today);
        let weekTotal = 0;
        let contributors = [];

        for (let i = 0; i < 7; i++) {
            const date = new Date(today);
            date.setDate(today.getDate() - i);
            const dateKey = root.formatDateKey(date);
            const count = pluginService.loadPluginState("dmsKetchup", "completedPomodoros-" + dateKey, 0) || 0;
            weekTotal += count;
            if (count > 0) {
                contributors.push({ date: dateKey, count: count });
            }
        }

        contributors.sort((a, b) => b.count - a.count);

        let total = 0;
        for (let d = 0; d < 365; d++) {
            const date = new Date(today);
            date.setDate(today.getDate() - d);
            const dateKey = root.formatDateKey(date);
            const count = pluginService.loadPluginState("dmsKetchup", "completedPomodoros-" + dateKey, 0) || 0;
            total += count;
        }

        root.stats = {
            today: pluginService.loadPluginState("dmsKetchup", "completedPomodoros-" + todayKey, 0) || 0,
            week: weekTotal,
            total: total,
            contributors: contributors
        };
    }

    function resetStats() {
        if (!pluginService)
            return;
        const today = new Date();
        for (let d = 0; d < 400; d++) {
            const date = new Date(today);
            date.setDate(today.getDate() - d);
            const dateKey = root.formatDateKey(date);
            pluginService.removePluginStateKey("dmsKetchup", "completedPomodoros-" + dateKey);
        }
        PluginService.setGlobalVar("dmsKetchup", "completedPomodoros", 0);
        root.refreshStats();
    }

    Timer {
        id: statsRefreshTimer
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refreshStats()
    }

    Timer {
        id: statsInitTimer
        interval: 500
        repeat: true
        running: pluginService === null
        onTriggered: {
            if (pluginService) {
                running = false;
                root.refreshStats();
            }
        }
    }

    Connections {
        target: PluginService
        ignoreUnknownSignals: true
        function onPluginStateChanged(changedPluginId) {
            if (changedPluginId === "dmsKetchup")
                root.refreshStats();
        }
        function onGlobalVarChanged(changedPluginId, varName) {
            if (changedPluginId === "dmsKetchup" && varName === "completedPomodoros")
                root.refreshStats();
        }
    }

    Component.onCompleted: root.refreshStats()

    StyledText {
        width: parent.width
        text: root.tr("DMS Ketchup Settings", "Ajustes de DMS Ketchup")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: root.tr("Configure timer durations and behavior", "Configura las duraciones y el comportamiento")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: durationsColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: durationsColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.tr("Durations", "Duraciones")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            StringSetting {
                settingKey: "workDuration"
                label: root.tr("Work Duration (minutes)", "Duración de trabajo (minutos)")
                description: root.tr("Length of each focus session", "Duración de cada sesión de enfoque")
                placeholder: "25"
                defaultValue: "25"
            }

            StringSetting {
                settingKey: "shortBreakDuration"
                label: root.tr("Short Break (minutes)", "Descanso corto (minutos)")
                description: root.tr("Break after each session", "Descanso después de cada sesión")
                placeholder: "5"
                defaultValue: "5"
            }

            StringSetting {
                settingKey: "longBreakDuration"
                label: root.tr("Long Break (minutes)", "Descanso largo (minutos)")
                description: root.tr("Break after 4 sessions", "Descanso después de 4 sesiones")
                placeholder: "15"
                defaultValue: "15"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: behaviorColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: behaviorColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.tr("Behavior", "Comportamiento")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "fullscreenBreakModalEnabled"
                label: root.tr("Fullscreen break modal", "Modal de descanso a pantalla completa")
                description: root.tr("Show a blocking fullscreen modal when a work session ends", "Muestra un modal bloqueante a pantalla completa cuando termina una sesión de trabajo")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "requireManualContinueAfterBreak"
                label: root.tr("Require manual continue", "Requerir continuación manual")
                description: root.tr("Keep the break modal open until you press continue or skip the break", "Mantén el modal de descanso abierto hasta que pulses continuar o omitir el descanso")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "soundsEnabled"
                label: root.tr("Ketchup sounds", "Sonidos de Ketchup")
                description: root.tr("Play a short sound when sessions start and end", "Reproduce un sonido corto cuando las sesiones empiezan y terminan")
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "autoStartBreaks"
                label: root.tr("Auto-start Breaks", "Inicio automático de descansos")
                description: root.tr("Automatically start break timers after work sessions when fullscreen modal is disabled", "Inicia automáticamente los descansos después de las sesiones de trabajo cuando el modal a pantalla completa está desactivado")
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "autoStartPomodoros"
                label: root.tr("Auto-start sessions", "Inicio automático de sesiones")
                description: root.tr("Automatically start work sessions after breaks when the fullscreen modal is disabled", "Inicia automáticamente las sesiones de trabajo después de los descansos cuando el modal a pantalla completa está desactivado")
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "autoSetDND"
                label: root.tr("Do Not Disturb Work", "No molestar durante el trabajo")
                description: root.tr("Automatically enable Do Not Disturb mode during work sessions", "Activa automáticamente el modo No molestar durante las sesiones de trabajo")
                defaultValue: false
            }
        }
    }

    StyledRect {
        width: parent.width
        height: preWarningColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: preWarningColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: root.tr("Pre-Warning", "Pre-aviso")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            ToggleSetting {
                settingKey: "enablePreWarning"
                label: root.tr("Pre-warning toast", "Aviso previo")
                description: root.tr("Show a toast shortly before a break starts", "Muestra un aviso poco antes de que empiece un descanso")
                defaultValue: true
            }

            SliderSetting {
                settingKey: "preWarningTime"
                label: root.tr("Pre-warning lead time", "Antelación del aviso")
                description: root.tr("Seconds before the break starts", "Segundos antes de que empiece el descanso")
                defaultValue: 10
                minimum: 5
                maximum: 60
                unit: "s"
            }

            SelectionSetting {
                settingKey: "preWarningAlignment"
                label: root.tr("Toast position", "Posición del aviso")
                description: root.tr("Corner where the pre-warning toast appears", "Esquina donde aparece el aviso previo")
                options: [
                    { label: root.tr("Bottom right", "Abajo a la derecha"), value: "bottom-right" },
                    { label: root.tr("Bottom left", "Abajo a la izquierda"), value: "bottom-left" },
                    { label: root.tr("Top right", "Arriba a la derecha"), value: "top-right" },
                    { label: root.tr("Top left", "Arriba a la izquierda"), value: "top-left" },
                    { label: root.tr("Bottom center", "Abajo en el centro"), value: "bottom-center" },
                    { label: root.tr("Top center", "Arriba en el centro"), value: "top-center" }
                ]
                defaultValue: "bottom-right"
            }
        }
    }

    SettingsCard {
        SectionTitle {
            text: root.tr("Statistics", "Statistiken")
            icon: "bar_chart"
        }

        Column {
            width: parent.width - Theme.spacingM * 2
            x: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                InfoTile {
                    width: (parent.width - parent.spacing) / 2
                    label: root.tr("Today", "Hoy")
                    value: root.stats.today + " " + root.tr("sessions", "Sesiones")
                    iconName: "today"
                    accentColor: Theme.primary
                }

                InfoTile {
                    width: (parent.width - parent.spacing) / 2
                    label: root.tr("This Week", "Diese Woche")
                    value: root.stats.week + " " + root.tr("sessions", "Sesiones")
                    iconName: "date_range"
                    accentColor: Theme.info
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                InfoTile {
                    width: (parent.width - parent.spacing) / 2
                    label: root.tr("Total (365 days)", "Gesamt (365 Tage)")
                    value: String(root.stats.total)
                    iconName: "analytics"
                    accentColor: Theme.success
                }

                InfoTile {
                    width: (parent.width - parent.spacing) / 2
                    label: root.tr("Best Day", "Bester Tag")
                    value: root.stats.contributors.length > 0
                        ? root.stats.contributors[0].count + " (" + root.stats.contributors[0].date + ")"
                        : "—"
                    iconName: "emoji_events"
                    accentColor: Theme.warning
                }
            }

            StyledText {
                text: root.tr("Top Days", "Top-Tage")
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: root.stats.contributors.slice(0, 5)

                InfoTile {
                    width: parent.width
                    label: modelData.date
                    value: modelData.count + " " + root.tr("sessions", "Sesiones")
                    iconName: "calendar_month"
                    accentColor: Theme.primary
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: root.tr("Refresh", "Aktualisieren")
                    iconName: "refresh"
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    width: (parent.width - parent.spacing) / 2
                    buttonHeight: 32
                    onClicked: root.refreshStats()
                }

                DankButton {
                    text: root.tr("Reset Stats", "Statistiken zurücksetzen")
                    iconName: "delete_sweep"
                    backgroundColor: Theme.withAlpha(Theme.error, 0.15)
                    textColor: Theme.error
                    width: (parent.width - parent.spacing) / 2
                    buttonHeight: 32
                    onClicked: root.resetStats()
                }
            }
        }
    }

    StyledRect {
        width: parent.width
        height: infoColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DankIcon {
                    name: "info"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.tr("About DMS Ketchup", "Acerca de DMS Ketchup")
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: root.tr("DMS Ketchup squeezes focused work sessions into short bursts, followed by breaks to recharge. After 4 sessions, take a longer break.\n\n• Work: 25 minutes of focused work\n• Short Break: 5 minute rest\n• Long Break: 15 minutes after 4 sessions\n\nNotifications will alert you when each session completes.", "DMS Ketchup exprime las sesiones de trabajo en ráfagas cortas, seguidas de descansos para recargar. Después de 4 sesiones, toma un descanso largo.\n\n• Trabajo: 25 minutos de trabajo concentrado\n• Descanso corto: 5 minutos de pausa\n• Descanso largo: 15 minutos después de 4 sesiones\n\nLas notificaciones te avisarán cuando termine cada sesión.")
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
            }
        }
    }
}
