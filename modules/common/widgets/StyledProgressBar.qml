pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls


/**
 * Material 3 progress bar. See https://m3.material.io/components/progress-indicators/overview
 *
 * Set the inherited `indeterminate` property when there is no meaningful fill
 * point, such as a track whose player never published a length: the bar then
 * fills its whole width in the track color, keeping the wave alive while
 * `wavy` is set without reading as "finished".
 */
ProgressBar {
    id: root
    property real valueBarWidth: 120
    property real valueBarHeight: 4
    property real valueBarGap: 4
    // M3 sizes the stop indicator to the track thickness, not to the gap, so it fills the track's
    // rounded end cap instead of floating inside it on the thicker bars.
    property real stopIndicatorSize: valueBarHeight
    // The dot is painted in the highlight color at the far end of the track, so on a bar thick
    // enough for the dot to be as tall as the track it stops reading as an end marker once the fill
    // gets near it: the last of the inactive track disappears underneath it and the bar looks full
    // while it isn't. Turn it off on bars whose whole job is to be read as a level.
    property bool showStopIndicator: true
    property color highlightColor: Appearance?.colors.colPrimary ?? "#685496"
    property color trackColor: Appearance?.m3colors.m3secondaryContainer ?? "#F1D3F9"
    property bool wavy: false // If true, the progress bar will have a wavy fill effect
    property bool animateWave: true
    property real waveAmplitudeMultiplier: wavy ? 0.5 : 0
    property real waveFrequency: 6
    property real waveFps: 60

    Behavior on waveAmplitudeMultiplier {
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Behavior on value {
        animation: Appearance?.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    
    background: Item {
        implicitHeight: valueBarHeight
        implicitWidth: valueBarWidth
    }

    contentItem: Item {
        id: contentItem
        anchors.fill: parent

        Loader {
            anchors {
                left: parent.left
                verticalCenter: parent.verticalCenter
            }
            active: root.wavy
            sourceComponent: WavyLine {
                id: wavyFill
                frequency: root.waveFrequency
                color: root.indeterminate ? root.trackColor : root.highlightColor
                amplitudeMultiplier: root.wavy ? 0.5 : 0
                height: contentItem.height * 6
                width: root.indeterminate ? contentItem.width : contentItem.width * root.visualPosition
                lineWidth: contentItem.height
                fullLength: root.width
                Connections {
                    target: root
                    function onValueChanged() { wavyFill.requestPaint(); }
                    function onHighlightColorChanged() { wavyFill.requestPaint(); }
                }
                FrameAnimation {
                    running: root.animateWave
                    onTriggered: {
                        wavyFill.requestPaint()
                    }
                }
            }
        }

        Loader {
            active: !root.wavy
            sourceComponent: Rectangle {
                anchors.left: parent.left
                width: contentItem.width * root.visualPosition
                height: contentItem.height
                radius: height / 2
                color: root.highlightColor
            }
        }
        
        Rectangle { // Right remaining part fill
            anchors.right: parent.right
            // Clamped: past the point where the gap eats what is left of the track the raw
            // expression goes negative, and a negative width anchored to the right edge is not
            // something Rectangle draws meaningfully.
            width: root.indeterminate
                ? (root.wavy ? 0 : parent.width) // The wave already covers the full track
                : Math.max(0, (1 - root.visualPosition) * parent.width - valueBarGap)
            height: parent.height
            radius: height / 2
            color: root.trackColor
        }

        Rectangle { // Stop point
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.indeterminate && root.showStopIndicator
            width: root.stopIndicatorSize
            height: root.stopIndicatorSize
            radius: height / 2
            color: root.highlightColor
        }
    }
}