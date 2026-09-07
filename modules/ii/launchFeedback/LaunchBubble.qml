pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One in-flight app launch, drawn as its icon bouncing on the ground next to the pointer.
 *
 * Reads its whole lifecycle off the AppLaunchFeedback.PendingLaunch it is given:
 * bounce while "launching", hop up and vanish once the window appears, sink and shrink
 * if the launch is given up on.
 */
Item {
    id: root

    required property var launch
    /** Position among the launches in flight, so several starting apps fan out. */
    property int slot: 0
    property string screenName: ""
    property real boundsWidth: 0
    property real boundsHeight: 0

    readonly property real iconSize: Config.options?.launchFeedback?.iconSize ?? 40
    readonly property real hopHeight: root.iconSize * 0.45
    readonly property real shadowHeight: Math.max(4, root.iconSize * 0.15)
    readonly property real barHeight: 3
    readonly property real barGap: 5

    readonly property bool launching: root.launch?.phase === "launching"
    readonly property bool resolved: root.launch?.phase === "resolved"
    readonly property bool waitingTooLong: (root.launch?.slow ?? false) && root.launching

    // 0 = resting on the ground, 1 = top of the arc. Squash is the landing deformation.
    property real lift: 0
    property real squash: 0
    property real intro: (root.launch?.introPlayed ?? false) ? 1 : 0
    property real outro: 0

    // Pointer, in this window's coordinates
    readonly property real pointerX: (root.launch?.x ?? 0) - (root.launch?.screenX ?? 0)
    readonly property real pointerY: (root.launch?.y ?? 0) - (root.launch?.screenY ?? 0)

    // Sit clear of the cursor bitmap itself -- XCURSOR_SIZE is 30 here, and an icon
    // tucked under the arrow is exactly what you can't see when launching by keyboard.
    readonly property real pointerGap: Config.options?.launchFeedback?.pointerGap ?? 30
    /** Hotspot to icon centre. */
    readonly property real sideOffset: root.pointerGap + root.iconSize / 2
    /** Near the right edge, go left instead: clamping would put the icon back under the pointer. */
    readonly property bool toTheLeft: !(root.launch?.centered ?? false) && root.boundsWidth > 0 && root.pointerX + root.sideOffset + root.iconSize / 2 + 2 > root.boundsWidth
    readonly property real fanOut: root.slot * (root.iconSize + 8)

    readonly property real anchorX: root.pointerX + (root.toTheLeft ? -1 : 1) * ((root.launch?.centered ? 0 : root.sideOffset) + root.fanOut)
    readonly property real anchorY: root.pointerY + (root.launch?.centered ? 0 : root.iconSize * 0.70)

    implicitWidth: root.iconSize
    implicitHeight: root.hopHeight + root.iconSize + root.shadowHeight + root.barGap + root.barHeight
    width: implicitWidth
    height: implicitHeight

    x: Math.max(2, Math.min(root.anchorX - width / 2, root.boundsWidth - width - 2))
    y: Math.max(2, Math.min(root.anchorY - root.hopHeight - root.iconSize / 2, root.boundsHeight - height - 2))

    visible: (root.launch?.placed ?? false) && root.launch?.screenName === root.screenName
    opacity: root.intro * (1 - root.outro)
    // Blend the intro pop into the exit: grow away when the window appeared, shrink when not
    scale: (0.45 + 0.55 * root.intro) * (1 - root.outro) + (root.resolved ? 1.3 : 0.7) * root.outro
    transformOrigin: Item.Center

    // Following the pointer arrives in ~90 ms steps; ease between them so it glides
    Behavior on x {
        enabled: !(root.launch?.pinned ?? true)
        NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
    }
    Behavior on y {
        enabled: !(root.launch?.pinned ?? true)
        NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
    }

    NumberAnimation on intro {
        // Only the first time this launch is drawn -- see PendingLaunch.introPlayed
        running: !(root.launch?.introPlayed ?? false)
        from: 0
        to: 1
        duration: Appearance.animationCurves.expressiveFastSpatialDuration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        onFinished: {
            if (root.launch)
                root.launch.introPlayed = true;
        }
    }

    NumberAnimation on outro {
        running: !root.launching
        from: 0
        to: 1
        duration: root.resolved ? 240 : 300
        easing.type: root.resolved ? Easing.OutQuad : Easing.InQuad
    }

    SequentialAnimation {
        running: root.launching
        loops: Animation.Infinite
        NumberAnimation { target: root; property: "lift"; from: 0; to: 1; duration: 230; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "lift"; to: 0; duration: 190; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "squash"; to: 1; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "squash"; to: 0; duration: 120; easing.type: Easing.OutBack }
        PauseAnimation { duration: 40 }
    }

    onLaunchingChanged: {
        if (root.launching)
            return;
        // A successful launch leaps off the ground; a given-up one just settles back down
        if (root.resolved)
            leapAway.restart();
        else
            settle.restart();
    }

    ParallelAnimation {
        id: leapAway
        NumberAnimation { target: root; property: "lift"; to: 1.5; duration: 240; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "squash"; to: 0; duration: 110 }
    }

    ParallelAnimation {
        id: settle
        NumberAnimation { target: root; property: "lift"; to: 0; duration: 140; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "squash"; to: 0; duration: 140 }
    }

    Rectangle { // Ground shadow: the cue that sells the hop
        id: groundShadow
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hopHeight + root.iconSize
        implicitWidth: root.iconSize * 0.62
        implicitHeight: root.shadowHeight
        width: implicitWidth
        height: implicitHeight
        radius: height / 2
        color: Appearance.m3colors.m3shadow
        opacity: 0.42 * (1 - 0.72 * Math.min(root.lift, 1))
        scale: 1 - 0.32 * Math.min(root.lift, 1) + 0.14 * root.squash
    }

    Item {
        id: iconWrapper
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.hopHeight * (1 - root.lift)
        width: root.iconSize
        height: root.iconSize

        transform: Scale {
            origin.x: iconWrapper.width / 2
            origin.y: iconWrapper.height
            xScale: 1 + 0.18 * root.squash
            yScale: 1 - 0.18 * root.squash
        }

        AppIcon {
            anchors.fill: parent
            source: root.launch?.iconSource ?? ""
        }
    }

    Item { // "Still working on it", once a launch stops feeling instant
        id: slowBar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        implicitWidth: root.iconSize * 0.72
        width: implicitWidth
        height: root.barHeight
        opacity: root.waitingTooLong ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.7)
        }

        Rectangle {
            id: slowBarHead
            width: parent.width * 0.42
            height: parent.height
            radius: height / 2
            color: Appearance.colors.colPrimary

            SequentialAnimation on x {
                running: slowBar.opacity > 0.01
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: slowBar.width - slowBarHead.width; duration: 680; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0; duration: 680; easing.type: Easing.InOutQuad }
            }
        }
    }
}
