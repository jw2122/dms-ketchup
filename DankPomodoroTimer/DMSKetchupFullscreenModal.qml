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
    property real barProgress: 1
    property int lastSecondMs: 0

    visible: isOpen

    // Tips 1-7 are from "take a break" (TakeABreakOverlay.qml); the rest are pomodoro/mindfulness tips added for dmsKetchup
    property var tips: [
        I18n.tr("Look at something 20 feet away for 20 seconds."),
        I18n.tr("Blink 10-20 times quickly to moisten your eyes."),
        I18n.tr("Close your eyes tightly for 2 seconds, then open them."),
        I18n.tr("Roll your eyes clockwise, then counter-clockwise."),
        I18n.tr("Stretch your arms and neck."),
        I18n.tr("Drink a glass of water."),
        I18n.tr("Look out a window to relax your eye muscles."),
        I18n.tr("Breathe in for 4 seconds, hold for 4, breathe out for 4."),
        I18n.tr("Stand up and walk a few steps."),
        I18n.tr("Shake your hands and wiggle your fingers."),
        I18n.tr("Name three things you can see, hear and feel.")
    ]

    property string currentTip: tips[0]

    Component.onCompleted: {
        currentTip = tips[Math.floor(Math.random() * tips.length)];
        lastSecondMs = Date.now();
    }

    Timer {
        id: progressUpdateTimer
        interval: 33
        repeat: true
        running: rootOverlay.visible && rootOverlay.phase !== "complete"
        onRunningChanged: {
            if (running) {
                lastSecondMs = Date.now();
            }
        }
        onTriggered: {
            var total = rootOverlay.totalSeconds;
            if (total <= 0) {
                rootOverlay.barProgress = 1;
                return;
            }
            if (rootOverlay.lastSecondMs > 0) {
                var elapsed = (Date.now() - rootOverlay.lastSecondMs) / 1000;
                var cur = rootOverlay.remainingSeconds - elapsed;
                if (cur < 0) cur = 0;
                rootOverlay.barProgress = cur / total;
            } else {
                rootOverlay.barProgress = rootOverlay.remainingSeconds / total;
            }
        }
    }

    onRemainingSecondsChanged: {
        lastSecondMs = Date.now();
    }

    function breakTitle() {
        if (phase === "complete")
            return I18n.tr("Break complete");
        return timerState === "longBreak" ? I18n.tr("Long Break") : I18n.tr("Short Break");
    }

    function breakSubtitle() {
        if (phase === "complete")
            return I18n.tr("Press continue to begin a new work session.");
        return I18n.tr("Focus is paused until the break ends or you skip it.");
    }

    function actionLabel() {
        return phase === "complete" ? I18n.tr("Continue working") : I18n.tr("Skip break");
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
                    }
                }

                MouseArea {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: Theme.spacingXL
                    width: actionText.width + 40
                    height: actionText.height + 40
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
