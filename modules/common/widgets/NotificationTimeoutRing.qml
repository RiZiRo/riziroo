import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes

/**
 * A remaining-time hairline drawn around a control, retracting clockwise from twelve o'clock.
 *
 * Built on Shapes rather than Canvas. The first version traced a stadium on a Canvas, because the
 * control it wraps -- the notification group's expand button -- used to be a pill. That button is
 * square on toasts now, so the path is a plain circle, and a circle needs none of Canvas's
 * imperative repainting: `sweepAngle` is an ordinary property binding that the scene graph redraws
 * like any other item, with no requestPaint() to schedule and no render-thread round trip. Follows
 * CircularProgress.qml, which does the same thing for the Material 3 progress spinner.
 */
Item {
    id: root

    property real progress: 1 // 1 = whole ring, 0 = nothing left
    property real lineWidth: 2
    property color strokeColor: Appearance.colors.colPrimary
    // Faint, so the retracting arc reads as progress rather than as a stray line.
    property color trackColor: ColorUtils.transparentize(Appearance.colors.colOnLayer2, 0.85)

    // Inset by half the stroke, so the ring's outer edge lands on this item's bounds rather than
    // straddling them.
    readonly property real arcRadius: Math.max(0, Math.min(root.width, root.height) / 2 - root.lineWidth / 2)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath { // Track
            strokeColor: root.trackColor
            strokeWidth: root.lineWidth
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: -90
                sweepAngle: 360
            }
        }

        ShapePath { // Remaining
            strokeColor: root.strokeColor
            strokeWidth: root.lineWidth
            // Flat, not round: a round cap adds half a stroke width past each end, so the gap stays
            // hidden until the arc has given back a full stroke width -- most of a second on a long
            // timer, during which the ring looks frozen at full.
            capStyle: ShapePath.FlatCap
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: root.arcRadius
                radiusY: root.arcRadius
                startAngle: -90
                sweepAngle: 360 * root.progress
            }
        }
    }
}
