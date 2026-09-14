import qs.modules.common
import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

/**
 * Own-colour bloom for a dock icon.
 *
 * Instead of tinting everything with the accent colour, this draws blurred
 * copies of the icon *itself* behind the real one, so Spotify glows green, Zen
 * glows orange, and so on, with no per-app colour table to maintain.
 *
 * The copies are stacked widest-to-narrowest with falling opacity and rising
 * brightness, which is what reads as a soft "heavenly" bloom rather than a
 * neon outline: the app's colour stays near the glyph while the outer air
 * washes toward white. Nothing in the stack is tight — a small blur radius
 * piles light right at the glyph's edge and visibly muddies thin-stroke icons
 * (the Claude asterisk being the worst case), so the innermost layer is still
 * more than twice the icon's size.
 *
 * Each copy sits in a cell deliberately larger than the icon, because
 * `layer.effect` output is clipped to the item's own bounds: that padding is
 * the only thing giving the blur room to bleed. The radius is therefore derived
 * from the padding rather than hardcoded, so it stays consistent at any spread.
 *
 * Anchor it centred on the icon it belongs to and give it a negative z.
 */
Item {
    id: root

    /// Icon to bloom. Usually just `theIconImage.source`.
    property url iconSource
    /// Rendered size of the icon being bloomed, in px.
    property real iconSize: 33
    /// How much this app deserves attention: 0 = not running, 0.5 = has
    /// windows, 1 = focused. Drives the resting brightness.
    property real emphasis: 0
    /// Hover ramp, set from the button's `hovered`.
    property bool boosted: false

    readonly property var opts: Config.options?.dock?.iconGlow ?? null
    readonly property bool glowEnabled: root.opts?.enable ?? true
    readonly property real strength: (root.opts?.strength ?? 100) / 100
    readonly property real spread: (root.opts?.spread ?? 100) / 100
    readonly property real extraSaturation: (root.opts?.saturation ?? 45) / 100
    readonly property bool pulseEnabled: root.opts?.pulse ?? true
    readonly property bool activeOnly: root.opts?.activeOnly ?? false

    readonly property bool shouldGlow: root.glowEnabled
        && root.strength > 0
        && root.iconSize > 0
        && String(root.iconSource).length > 0
        && (!root.activeOnly || root.emphasis > 0)

    /**
     * The bloom stack, innermost first.
     *  size:   cell size as a multiple of the icon
     *  alpha:  share of the current glow level
     *  sat:    share of the configured extra saturation
     *  bright: push toward white, so outer air reads as light not paint
     *  rise:   upward offset (multiple of icon size) — light drifts up, and it
     *          keeps bloom out of the screen edge below the dock
     *  swell:  how much of the breathing pulse this layer picks up
     *
     * The outermost layer's reach comes from DockGlow because the dock window
     * sizes its transparent headroom from the same numbers.
     */
    readonly property var layers: [
        { size: 2.55, alpha: 0.60, sat: 1.00, bright: 0.04, rise: 0.00, swell: 0.06 },
        { size: 3.80, alpha: 0.32, sat: 0.70, bright: 0.10, rise: 0.06, swell: 0.13 },
        {
            size: DockGlow.outerSizeFactor,
            alpha: 0.17,
            sat: 0.40,
            bright: 0.16,
            rise: DockGlow.outerRiseFactor,
            swell: 0.20
        },
    ]

    readonly property real outerSize: root.iconSize * DockGlow.outerSizeFactor * root.spread

    // Resting glow by emphasis, ramping up on hover.
    readonly property real targetLevel: !root.shouldGlow ? 0
        : root.boosted ? 0.92
        : 0.34 + 0.26 * root.emphasis
    property real level: root.targetLevel
    Behavior on level {
        NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
    }

    // Breathing, staggered by icon so a row of them doesn't pulse in unison.
    readonly property int pulseDelay: {
        const s = String(root.iconSource);
        let h = 0;
        for (let i = 0; i < s.length; i++)
            h = (h * 31 + s.charCodeAt(i)) % 1800;
        return h;
    }
    property real pulse: 0
    SequentialAnimation on pulse {
        running: root.pulseEnabled && root.shouldGlow
        loops: Animation.Infinite
        PauseAnimation { duration: root.pulseDelay }
        NumberAnimation { to: 1; duration: 2100; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 2100; easing.type: Easing.InOutSine }
    }

    implicitWidth: root.outerSize
    implicitHeight: root.outerSize
    visible: root.level > 0.005

    scale: root.boosted ? 1.06 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }

    Repeater {
        model: root.layers

        delegate: Item {
            id: bloomLayer
            required property var modelData

            // Hoisted so the layer effect can reach them by id — bindings
            // inside layer.effect cannot see the delegate's model scope.
            readonly property real satShare: bloomLayer.modelData.sat
            readonly property real brightness: bloomLayer.modelData.bright
            readonly property real blurRadius: Math.max(2, Math.min(64,
                Math.round((bloomLayer.width - root.iconSize) / 2)))

            anchors.centerIn: parent
            anchors.verticalCenterOffset: -root.iconSize * bloomLayer.modelData.rise * root.spread
            width: root.iconSize * bloomLayer.modelData.size * root.spread
            height: bloomLayer.width

            opacity: Math.min(1, root.level
                * bloomLayer.modelData.alpha
                * root.strength
                * (1 + bloomLayer.modelData.swell * root.pulse))

            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 1.0
                blurMax: bloomLayer.blurRadius
                saturation: root.extraSaturation * bloomLayer.satShare
                brightness: bloomLayer.brightness + 0.20 * Math.max(0, root.strength - 1)
            }

            IconImage {
                anchors.centerIn: parent
                source: root.iconSource
                implicitSize: root.iconSize
            }
        }
    }
}
