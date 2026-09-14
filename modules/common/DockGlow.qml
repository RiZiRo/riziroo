import QtQuick
import Quickshell
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Presets for the dock's per-app icon bloom (see
 * modules/common/widgets/IconGlow.qml).
 *
 * Lives here rather than next to either caller because three separate entry
 * points switch between the same looks — the Quick and Interface settings
 * pages, and the `dock glow` IPC command — and the numbers drifting apart
 * between them would be a silent papercut.
 */
Singleton {
    id: root

    /// Rendered size of a dock app icon, in px. All bloom geometry is relative
    /// to this, so the buttons read it from here too.
    readonly property real iconSize: 33

    /// Size and upward drift of the *widest* bloom layer, as multiples of the
    /// icon. These live here rather than only in IconGlow.qml because Dock.qml
    /// has to size the window's transparent headroom from the same numbers the
    /// bloom is drawn with: if the two drift apart the bloom gets clipped
    /// square at the layer-surface edge, and the compositor blurs that
    /// rectangle into what looks like a taller dock panel.
    readonly property real outerSizeFactor: 4.90
    readonly property real outerRiseFactor: 0.12

    readonly property real spread: (Config.options?.dock?.iconGlow?.spread ?? 100) / 100

    /// Transparent headroom the dock window needs above its panel for the
    /// bloom to finish inside the layer surface. Derived, never configured —
    /// it is a constraint, not a preference.
    readonly property real requiredSpill: {
        const glow = Config.options?.dock?.iconGlow ?? null;
        if (!glow || !glow.enable)
            return 0;

        // How far the widest layer reaches above the icon's centre.
        const reach = root.iconSize * root.spread
            * (root.outerSizeFactor / 2 + root.outerRiseFactor);
        // How much room it already has between that centre and the window top.
        const roomInside = (Config.options?.dock?.height ?? 70) / 2
            + Appearance.sizes.elevationMargin;

        return Math.max(0, Math.ceil(reach - roomInside));
    }

    readonly property var presets: ({
        "off": {
            "enable": false
        },
        "normal": {
            "enable": true,
            "strength": 100,
            "spread": 100,
            "saturation": 45
        },
        "thumbnail": {
            "enable": true,
            "strength": 165,
            "spread": 145,
            "saturation": 70
        }
    })

    /// Which preset the current config most looks like, so a segmented
    /// selector can show the right item even after the sliders were touched.
    readonly property string currentPreset: {
        const glow = Config.options?.dock?.iconGlow ?? null;
        if (!glow || !glow.enable)
            return "off";
        return glow.strength >= 140 ? "thumbnail" : "normal";
    }

    /// Returns false for an unknown preset name.
    function apply(name: string): bool {
        const preset = root.presets[name];
        if (!preset)
            return false;

        const glow = Config.options.dock.iconGlow;
        for (const key in preset)
            glow[key] = preset[key];
        return true;
    }
}
