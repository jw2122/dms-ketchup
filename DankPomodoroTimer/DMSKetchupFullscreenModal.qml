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

    // Fresh quote for every break, even if the phrase table finished loading
    // before this overlay switched to visible.
    onIsOpenChanged: {
        if (isOpen)
            pickTip();
    }

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

    function stateColor() {
        if (phase === "complete")
            return Theme.success;
        if (timerState === "longBreak")
            return Theme.warning;
        if (timerState === "shortBreak")
            return Theme.info;
        return Theme.primary;
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

            // Soft tint over the whole surface. This must not live inside
            // safeArea: the bar/dock offsets would start the gradient 40 px
            // from the edge and leave a visible strip on the left.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.withAlpha(rootOverlay.stateColor(), 0.10) }
                    GradientStop { position: 0.55; color: "transparent" }
                }
            }

            Item {
                id: safeArea
                property int _refreshTrigger: 0
                anchors.fill: parent
                anchors.topMargin: { safeArea._refreshTrigger; return getOffset("top"); }
                anchors.bottomMargin: { safeArea._refreshTrigger; return getOffset("bottom"); }
                // Use the same inset on both sides so a left/right bar cannot
                // push the centered card off the middle of the screen.
                anchors.leftMargin: { safeArea._refreshTrigger; return Math.max(getOffset("left"), getOffset("right")); }
                anchors.rightMargin: { safeArea._refreshTrigger; return Math.max(getOffset("left"), getOffset("right")); }
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

                StyledRect {
                    id: breakCard
                    width: Math.min(parent.width - Theme.spacingXL * 2, 560)
                    height: cardContent.implicitHeight + Theme.spacingXL * 2
                    anchors.centerIn: parent
                    radius: Theme.cornerRadiusXL
                    color: Theme.foregroundColor(Theme.cardSurface)
                    border.width: Theme.layerOutlineWidth
                    border.color: Theme.outlineMedium

                    Column {
                        id: cardContent
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.spacingXL
                        spacing: Theme.spacingL

                        StyledRect {
                            width: 88
                            height: 88
                            radius: 44
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Theme.withAlpha(rootOverlay.stateColor(), 0.12)

                            DankIcon {
                                anchors.centerIn: parent
                                name: rootOverlay.breakIcon()
                                size: 44
                                color: rootOverlay.stateColor()
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: rootOverlay.breakTitle()
                            font.pixelSize: Theme.fontSizeXXLarge
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            width: parent.width
                            text: rootOverlay.getCountdownText(rootOverlay.remainingSeconds)
                            font.family: "monospace"
                            font.pixelSize: 96
                            font.weight: Font.Bold
                            color: rootOverlay.stateColor()
                            horizontalAlignment: Text.AlignHCenter
                            visible: rootOverlay.phase !== "complete"
                        }

                        StyledRect {
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Theme.withAlpha(rootOverlay.stateColor(), 0.16)
                            visible: rootOverlay.phase !== "complete"

                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, rootOverlay.barProgress))
                                height: parent.height
                                radius: parent.radius
                                color: rootOverlay.stateColor()
                                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            }
                        }

                        StyledText {
                            width: parent.width
                            text: rootOverlay.breakSubtitle()
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            width: parent.width
                            text: rootOverlay.currentTip
                            font.family: "monospace"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                            opacity: 0.85
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: rootOverlay.currentTip !== "" && rootOverlay.phase !== "complete"
                        }

                        DankButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: rootOverlay.phase === "complete"
                            buttonHeight: 52
                            horizontalPadding: Theme.spacingXL
                            iconSize: 24
                            iconName: "play_arrow"
                            text: rootOverlay.actionLabel()
                            backgroundColor: Theme.primary
                            textColor: Theme.primaryText
                            onClicked: rootOverlay.onAction()
                        }

                        Item {
                            width: parent.width
                            height: skipPill.height
                            visible: rootOverlay.phase !== "complete"

                            StyledRect {
                                id: skipPill
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: skipText.implicitWidth + Theme.spacingXL * 2
                                height: 40
                                radius: 20
                                color: skipArea.containsMouse
                                    ? Theme.withAlpha(Theme.surfaceText, 0.08)
                                    : Theme.withAlpha(Theme.surfaceText, 0.03)

                                StyledText {
                                    id: skipText
                                    anchors.centerIn: parent
                                    text: rootOverlay.actionLabel()
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }

                                MouseArea {
                                    id: skipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: rootOverlay.onAction()
                                }
                            }
                        }
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
