import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

Item {
    id: rootOverlay

    property var pluginRoot: null
    property bool isOpen: false
    property string phase: "hidden"
    property string timerState: "work"
    property int remainingSeconds: 0
    property int totalSeconds: 0
    property real barProgress: totalSeconds > 0 ? remainingSeconds / totalSeconds : 1

    visible: isOpen

    // Motivational phrases, translated per the user's phrase-language setting
    // (loaded by the widget from translations/<lang>.json)
    readonly property var tips: (pluginRoot && pluginRoot.phraseTips && pluginRoot.phraseTips.length > 0)
        ? pluginRoot.phraseTips
        : []

    property string currentTip: ""

    function pickTip() {
        if (tips.length > 0)
            currentTip = tips[Math.floor(Math.random() * tips.length)];
    }

    Component.onCompleted: pickTip()

    onTipsChanged: pickTip()

    function breakTitle() {
        if (phase === "complete")
            return pluginRoot.tr("Break complete", "Descanso completo");
        return timerState === "longBreak" ? pluginRoot.tr("Long Break", "Descanso largo") : pluginRoot.tr("Short Break", "Descanso corto");
    }

    function breakSubtitle() {
        if (phase === "complete")
            return pluginRoot.tr("Press continue to begin a new work session.", "Pulsa continuar para empezar una nueva sesión de trabajo.");
        return pluginRoot.tr("Focus is paused until the break ends or you skip it.", "El enfoque está en pausa hasta que termine el descanso o lo omitas.");
    }

    function actionLabel() {
        return phase === "complete" ? pluginRoot.tr("Continue working", "Seguir trabajando") : pluginRoot.tr("Skip break", "Omitir descanso");
    }

    function breakIcon() {
        if (phase === "complete")
            return "check_circle";
        return timerState === "longBreak" ? "weekend" : "coffee";
    }

    function getCountdownText(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    function onEscape() {
        if (!pluginRoot)
            return;
        if (phase === "complete")
            pluginRoot.continueWorkingAfterBreak();
        else
            pluginRoot.closeBreakModal();
    }

    function onAction() {
        if (!pluginRoot)
            return;
        if (phase === "complete")
            pluginRoot.continueWorkingAfterBreak();
        else
            pluginRoot.stopBreakAndContinue();
    }

    Repeater {
        model: Quickshell.screens

        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: rootOverlay.visible

            anchors {
                top: true; bottom: true; left: true; right: true
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore

            color: Theme.surface

            Item {
                id: safeArea
                property int _refreshTrigger: 0
                anchors.fill: parent
                anchors.topMargin: { safeArea._refreshTrigger; return getOffset("top"); }
                anchors.bottomMargin: { safeArea._refreshTrigger; return getOffset("bottom"); }
                anchors.leftMargin: { safeArea._refreshTrigger; return getOffset("left"); }
                anchors.rightMargin: { safeArea._refreshTrigger; return getOffset("right"); }
                focus: true

                    Keys.onEscapePressed: (event) => {
                        rootOverlay.onEscape();
                        event.accepted = true;
                    }

                    Keys.onReturnPressed: (event) => {
                        if (rootOverlay.phase === "complete") {
                            rootOverlay.onAction();
                            event.accepted = true;
                        }
                    }

                    Keys.onEnterPressed: (event) => {
                        if (rootOverlay.phase === "complete") {
                            rootOverlay.onAction();
                            event.accepted = true;
                        }
                    }

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.spacingL

                    DankIcon {
                        name: rootOverlay.breakIcon()
                        size: 80
                        color: Theme.primary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: rootOverlay.breakTitle()
                        font.pixelSize: Theme.fontSizeExtraLarge * 2
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                         text: rootOverlay.getCountdownText(rootOverlay.remainingSeconds)
                        font.pixelSize: 120
                        font.weight: Font.Bold
                        font.family: "monospace"
                        color: Theme.primary
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: rootOverlay.phase !== "complete"
                    }

                    Rectangle {
                        width: 240
                        height: 8
                        radius: 4
                        color: Theme.withAlpha(Theme.surfaceContainerHighest, 0.85)
                        clip: true
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: rootOverlay.phase !== "complete"

                        Rectangle {
                            width: parent.width * rootOverlay.barProgress
                            height: parent.height
                            radius: 4
                            color: Theme.primary
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                        }
                    }

                    StyledText {
                        text: rootOverlay.breakSubtitle()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    StyledText {
                        text: rootOverlay.currentTip
                        font.pixelSize: Theme.fontSizeLarge
                        color: Theme.surfaceVariantText
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: rootOverlay.currentTip !== ""
                    }
                }

                MouseArea {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Theme.spacingXL
                    width: actionText.width + 40
                    height: actionText.height + 40
                    visible: rootOverlay.phase !== "complete"
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    onClicked: rootOverlay.onAction()

                    StyledText {
                        id: actionText
                        anchors.centerIn: parent
                        text: rootOverlay.actionLabel()
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        opacity: parent.containsMouse ? 0.6 : 0.2
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                DankButton {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Theme.spacingXL
                    visible: rootOverlay.phase === "complete"
                    buttonHeight: 56
                    horizontalPadding: Theme.spacingXL * 2
                    iconSize: 28
                    iconName: "play_arrow"
                    text: rootOverlay.actionLabel()
                    backgroundColor: Theme.primary
                    textColor: Theme.primaryText
                    onClicked: rootOverlay.onAction()
                }
            }

            function getOffset(edge) {
                if (typeof SettingsData === "undefined") return 0;
                let offset = 0;
                if (SettingsData.barConfigs) {
                    SettingsData.barConfigs.forEach(cfg => {
                        if (!cfg.enabled || !cfg.visible) return;
                        let onThisScreen = (!cfg.screenPreferences || cfg.screenPreferences.includes("all")) ? true : cfg.screenPreferences.includes(modelData.name);
                        if (!onThisScreen) return;
                        let edgeMatch = (edge === "top" && cfg.position === 0) || (edge === "bottom" && cfg.position === 1) || (edge === "left" && cfg.position === 2) || (edge === "right" && cfg.position === 3);
                        if (edgeMatch) {
                            let thickness = SettingsData.frameEnabled ? SettingsData.frameBarSize : Math.max(20, 26 + (cfg.innerPadding ?? 4) * 0.6) + (cfg.innerPadding ?? 4) + 4 + (cfg.spacing ?? 4) + ((typeof Theme !== "undefined" && Theme.isConnectedEffect) ? 0 : (cfg.bottomGap ?? 0));
                            offset = Math.max(offset, thickness);
                        }
                    });
                }
                if (SettingsData.dockEnabled && modelData === Quickshell.screens[0]) {
                    let edgeMatch = (edge === "top" && SettingsData.dockPosition === 0) || (edge === "bottom" && SettingsData.dockPosition === 1) || (edge === "left" && SettingsData.dockPosition === 2) || (edge === "right" && SettingsData.dockPosition === 3);
                    if (edgeMatch) {
                        let thickness = (SettingsData.dockIconSize ?? 40) + (SettingsData.dockSpacing ?? 4) * 2 + (SettingsData.dockBorderEnabled ? (SettingsData.dockBorderThickness ?? 1) : 0) * 2 + (SettingsData.dockBottomGap ?? 0) + ((typeof Theme !== "undefined" && Theme.isConnectedEffect) ? 0 : (SettingsData.dockMargin ?? 0)) + 8;
                        offset = Math.max(offset, thickness);
                    }
                }
                return offset;
            }

            Connections {
                target: (typeof SettingsData !== "undefined") ? SettingsData : null
                ignoreUnknownSignals: true
                function onBarConfigsChanged() { safeArea._refreshTrigger++; }
                function onDockEnabledChanged() { safeArea._refreshTrigger++; }
                function onDockPositionChanged() { safeArea._refreshTrigger++; }
            }
        }
    }
}
