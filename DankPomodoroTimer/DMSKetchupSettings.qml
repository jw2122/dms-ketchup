import QtQuick
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "."

PluginSettings {
    function tr(en, es) {
        const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
        return localeName.toLowerCase().startsWith("es") ? es : en;
    }

    id: root
    pluginId: "dmsKetchup"

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
