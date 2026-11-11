import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import "./dms-common/BarInsets.js" as BarInsets

PanelWindow {
    id: root

    property var pluginRoot

    implicitWidth: 320
    implicitHeight: 140
    color: "transparent"

    // Quickshell has no `primaryScreen`; resolving screens[0] also stops the
    // "Unable to assign [undefined] to QuickshellScreenInfo*" warning.
    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    property string alignment: pluginRoot.pluginData.preWarningAlignment ?? "bottom-right"

    anchors {
        top: alignment.includes("top")
        bottom: alignment.includes("bottom")
        left: alignment.includes("left")
        right: alignment.includes("right")
    }

    property int _refreshTrigger: 0

    WlrLayershell.margins {
        top: {
            root._refreshTrigger;
            let m = alignment.includes("top") ? Theme.spacingL : 0;
            if (alignment.includes("top")) m += getOffset("top");
            return m;
        }
        bottom: {
            root._refreshTrigger;
            let m = alignment.includes("bottom") ? Theme.spacingL : 0;
            if (alignment.includes("bottom")) m += getOffset("bottom");
            return m;
        }
        left: {
            root._refreshTrigger;
            let m = alignment.includes("left") ? Theme.spacingL : 0;
            if (alignment.includes("left")) m += getOffset("left");
            return m;
        }
        right: {
            root._refreshTrigger;
            let m = alignment.includes("right") ? Theme.spacingL : 0;
            if (alignment.includes("right")) m += getOffset("right");
            return m;
        }
    }

    function getOffset(edge) {
        return BarInsets.edgeOffset(
            edge,
            root.screen,
            Quickshell,
            typeof SettingsData !== "undefined" ? SettingsData : null,
            typeof Theme !== "undefined" ? Theme : null
        );
    }

    Connections {
        target: (typeof SettingsData !== "undefined") ? SettingsData : null
        ignoreUnknownSignals: true
        function onBarConfigsChanged() { root._refreshTrigger++; }
        function onDockEnabledChanged() { root._refreshTrigger++; }
        function onDockPositionChanged() { root._refreshTrigger++; }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    StyledRect {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHighest
        opacity: pluginRoot.preWarningOpacity
        border.color: Theme.outline
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            Row {
                spacing: Theme.spacingS
                DankIcon {
                    name: "hourglass_empty"
                    size: 24
                    color: Theme.primary
                }
                StyledText {
                    text: pluginRoot.tr("DMS Ketchup", "DMS Ketchup")
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: pluginRoot.tr("Your break starts in ", "Tu descanso empieza en ") + pluginRoot.preWarningCountdown + "s."
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Item { width: 1; height: Theme.spacingXS }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: pluginRoot.tr("Snooze (5m)", "Posponer (5m)")
                    iconName: "snooze"
                    backgroundColor: Theme.primaryContainer
                    textColor: Theme.primary
                    width: parent.width - skipBtn.width - parent.spacing
                    buttonHeight: 36
                    onClicked: pluginRoot.snoozeWork()
                }

                MouseArea {
                    id: skipBtn
                    width: 60
                    height: 36
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: pluginRoot.skipWork()

                    StyledText {
                        anchors.centerIn: parent
                        text: pluginRoot.tr("Skip", "Omitir")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        opacity: parent.containsMouse ? 1.0 : 0.5
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }
            }
        }
    }
}
