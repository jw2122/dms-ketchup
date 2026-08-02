import QtQuick
import QtQuick.Window
import qs.Common
import qs.Widgets

Window {
    id: root

    property var pluginRoot: null
    property bool isOpen: false
    property string phase: "hidden"
    property string timerState: "work"
    property int remainingSeconds: 0
    property int totalSeconds: 0
    property string breakLabel: "Break"
    property bool pauseToggled: false

    visible: isOpen && pluginRoot && pluginRoot.breakModalArmed
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Dialog
    modality: Qt.ApplicationModal
    color: "transparent"
    opacity: 1.0
    title: root.tr("DMS Ketchup Break", "Descanso de DMS Ketchup")
    width: Screen.width
    height: Screen.height
    visibility: (isOpen && pluginRoot && pluginRoot.breakModalArmed) ? Window.Windowed : Window.Hidden

    onIsOpenChanged: {
        if (isOpen)
            pauseToggled = false;
    }

    onClosing: (close) => {
        if (root.pluginRoot)
            root.pluginRoot.closeBreakModal();
        close.accepted = true;
    }

    function tr(en, es) {
        const localeName = (typeof I18n !== "undefined" && I18n.locale) ? I18n.locale().name : "en-US";
        return localeName.toLowerCase().startsWith("es") ? es : en;
    }

    function formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    function phaseTitle() {
        return phase === "complete" ? root.tr("Break complete", "Descanso completo") : breakLabel;
    }

    function phaseSubtitle() {
        return phase === "complete"
            ? root.tr("Press continue to begin a new work session.", "Pulsa continuar para iniciar una nueva sesión de trabajo.")
            : root.tr("Focus is paused until the break ends or you skip it.", "El enfoque está en pausa hasta que termine el descanso o lo omitas.");
    }

    function pauseButtonText() {
        return root.pauseToggled ? root.tr("Resume", "Reanudar") : root.tr("Pause", "Pausar");
    }

    function closeModalOnly() {
        if (root.pluginRoot)
            root.pluginRoot.closeBreakModal();
    }

    function pauseBreak() {
        root.pauseToggled = !root.pauseToggled;
        if (root.pluginRoot)
            root.pluginRoot.toggleBreakPause();
    }

    function skipBreakAndContinue() {
        if (root.pluginRoot)
            root.pluginRoot.stopBreakAndContinue();
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: (event) => {
            root.closeModalOnly();
            event.accepted = true;
        }

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.closeModalOnly();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
    }

    StyledRect {
        id: card
        width: Math.min(parent.width * 0.60, 640)
        height: mainColumn.implicitHeight + Theme.spacingXL * 2
        anchors.centerIn: parent
        radius: Theme.cornerRadius * 1.1
        color: Theme.withAlpha(Theme.surfaceContainerHigh, Theme.popupTransparency)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.30)

        Rectangle {
            width: 42
            height: 42
            radius: 21
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: Theme.spacingS
            anchors.topMargin: Theme.spacingS
            color: closeArea.containsMouse ? Theme.errorHover : Theme.withAlpha(Theme.surfaceTextHover, 0)
            border.width: 1
            border.color: Theme.withAlpha(Theme.error, closeArea.containsMouse ? 0.42 : 0.16)
            z: 5

            DankIcon {
                anchors.centerIn: parent
                name: "close"
                size: 18
                color: Theme.error
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeModalOnly()
            }
        }

        Column {
            id: mainColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingL

            Row {
                width: parent.width
                spacing: Theme.spacingS

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: phase === "complete" ? Theme.warning : Theme.info

                    DankIcon {
                        anchors.centerIn: parent
                        name: phase === "complete" ? "check_circle" : "coffee"
                        size: 24
                        color: Theme.surfaceText
                    }
                }

                Column {
                    width: parent.width - 64
                    spacing: Theme.spacingXXS

                    StyledText {
                        width: parent.width
                        text: root.phaseTitle()
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: root.phaseSubtitle()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Item {
                    width: parent.width
                    height: 84

                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.formatTime(root.remainingSeconds)
                        font.pixelSize: 72
                        font.weight: Font.Black
                        color: Theme.primary
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 8
                    radius: 4
                    color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.85)
                    clip: true

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.remainingSeconds / Math.max(root.totalSeconds, 1)))
                        height: parent.height
                        radius: 4
                        color: Theme.primary
                        Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                    }
                }
            }

            Item {
                height: Theme.spacingL
                width: 1
            }

            StyledRect {
                width: parent.width
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.withAlpha(Theme.primary, 0.04)
                height: detailsColumn.implicitHeight + Theme.spacingL * 2

                Column {
                    id: detailsColumn
                    anchors.fill: parent
                    anchors.margins: Theme.spacingL
                    spacing: Theme.spacingM

                    StyledText {
                        width: parent.width
                        text: phase === "complete"
                            ? root.tr("You can continue working now.", "Ya puedes continuar trabajando.")
                            : root.tr("If you need to skip the rest, close this modal or use the emergency action below.", "Si necesitas omitir el resto, cierra este modal o usa la acción de emergencia de abajo.")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Item {
                        width: parent.width
                        height: 52

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingM

                            DankButton {
                                text: root.pauseButtonText()
                                iconName: root.pauseToggled ? "play_arrow" : "pause"
                                width: 112
                                onClicked: root.pauseBreak()
                            }

                            DankButton {
                                text: phase === "complete" ? root.tr("Continue working", "Continuar trabajando") : root.tr("Skip break and continue", "Omitir descanso y continuar")
                                iconName: phase === "complete" ? "play_arrow" : "skip_next"
                                width: 220
                                onClicked: root.skipBreakAndContinue()
                            }
                        }
                    }
                }
            }
        }
    }
}
