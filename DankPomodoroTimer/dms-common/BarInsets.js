.pragma library

// Screen-edge insets for plugin layer surfaces (break modal, pre-warning
// toast). This used to be copy-pasted in two files with slightly different
// bar-height math, which made the modal card overlap the bar by a few pixels.

function edgeIndex(edge) {
    if (edge === "top") return 0;
    if (edge === "bottom") return 1;
    if (edge === "left") return 2;
    if (edge === "right") return 3;
    return -1;
}

function edgeOffset(edge, screen, quickshell, settings, theme) {
    if (!settings)
        return 0;

    const index = edgeIndex(edge);
    if (index < 0)
        return 0;

    const screens = quickshell && quickshell.screens ? quickshell.screens : [];
    const primary = screens.length > 0 ? screens[0] : null;
    let offset = 0;

    if (settings.barConfigs) {
        for (let i = 0; i < settings.barConfigs.length; i++) {
            const cfg = settings.barConfigs[i];
            if (!cfg || !cfg.enabled || !cfg.visible)
                continue;
            const prefs = cfg.screenPreferences;
            if (prefs && prefs.indexOf("all") === -1 && screen && prefs.indexOf(screen.name) === -1)
                continue;
            if (cfg.position !== index)
                continue;

            const innerPadding = cfg.innerPadding !== undefined ? cfg.innerPadding : 4;
            const spacing = cfg.spacing !== undefined ? cfg.spacing : 4;
            let thickness;
            if (settings.frameEnabled) {
                thickness = settings.frameBarSize;
            } else if (theme && theme.barThickness) {
                thickness = theme.barThickness(innerPadding, screen && screen.scale ? screen.scale : 1);
            } else {
                thickness = Math.max(20, 26 + innerPadding * 0.6) + innerPadding + 4;
            }
            const connected = theme && theme.isConnectedEffect;
            const bottomGap = connected ? 0 : (cfg.bottomGap !== undefined ? cfg.bottomGap : 0);
            offset = Math.max(offset, thickness + spacing + bottomGap);
        }
    }

    if (settings.dockEnabled && screen === primary && settings.dockPosition === index) {
        const iconSize = settings.dockIconSize !== undefined ? settings.dockIconSize : 40;
        const spacing = settings.dockSpacing !== undefined ? settings.dockSpacing : 4;
        const borderThickness = settings.dockBorderEnabled
            ? (settings.dockBorderThickness !== undefined ? settings.dockBorderThickness : 1)
            : 0;
        const reserveOffset = settings.dockBottomGap !== undefined ? settings.dockBottomGap : 0;
        const connected = theme && theme.isConnectedEffect;
        const effectiveMargin = connected ? 0 : (settings.dockMargin !== undefined ? settings.dockMargin : 0);
        offset = Math.max(offset, iconSize + spacing * 2 + borderThickness * 2 + reserveOffset + effectiveMargin + 8);
    }

    return offset;
}
