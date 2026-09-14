import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Notifications

/**
 * A group of notifications from the same app.
 * Similar to Android's notifications
 */
MouseArea { // Notification group area
    id: root
    property var notificationGroup
    property var notifications: notificationGroup?.notifications ?? []
    property int notificationCount: notifications.length
    property bool multipleNotifications: notificationCount > 1
    property bool expanded: false
    property bool popup: false
    property real padding: 10
    implicitHeight: background.implicitHeight

    // 0 = size to content. A toast sizes to what it has to say, now that it carries two lines of
    // body and the sender's own actions. The lists keep a cap so one chatty app can't push
    // everything else off the page -- raised from 80 to fit that second line without clipping it.
    property real collapsedMaxHeight: root.popup ? 0 : 100

    // Frosted while it floats over the desktop, flat while it sits inside the sidebar or the
    // island (both of which supply their own surface underneath). The blur behind the translucent
    // fill comes from the quickshell:notificationPopup layer rules in ~/.config/hypr/custom/rules.lua.
    readonly property bool glass: root.popup

    // The group's clock and click target. groupsForList() appends in arrival order, so the last
    // entry is the newest -- the same one the app icon already reads its summary from.
    readonly property var newestNotification: root.notifications[root.notificationCount - 1] ?? null

    // DragManager fills this item and enables hover itself, so on some builds it is the one that
    // sees the pointer rather than this MouseArea. Reading both keeps the pause honest either way.
    readonly property bool hovered: root.containsMouse || dragManager.containsMouse

    property real dragConfirmThreshold: 70 // Drag further to discard notification
    property real dismissOvershoot: 20 // Account for gaps and bouncy animations
    property var qmlParent: root?.parent?.parent // There's something between this and the parent ListView
    property var parentDragIndex: qmlParent?.dragIndex
    property var parentDragDistance: qmlParent?.dragDistance
    property var dragIndexDiff: Math.abs(parentDragIndex - index)
    property real xOffset: dragIndexDiff == 0 ? parentDragDistance :
        Math.abs(parentDragDistance) > dragConfirmThreshold ? 0 :
        dragIndexDiff == 1 ? (parentDragDistance * 0.3) :
        dragIndexDiff == 2 ? (parentDragDistance * 0.1) : 0

    function destroyWithAnimation(left = false) {
        root.qmlParent.resetDrag()
        background.anchors.leftMargin = background.anchors.leftMargin; // Break binding
        destroyAnimation.left = left;
        destroyAnimation.running = true;
    }

    hoverEnabled: true
    onHoveredChanged: {
        if (!root.popup) return;
        if (root.hovered) root.notifications.forEach(notif => {
            Notifications.cancelTimeout(notif.notificationId);
        });
        // Resumes the countdown. This used to call timeoutNotification(), which sets popup = false
        // immediately -- so reading a toast and then moving the mouse away made it vanish on the
        // spot instead of giving back the time it had left.
        else root.notifications.forEach(notif => {
            Notifications.restartTimeout(notif.notificationId);
        });
    }

    ////////////////////////// Countdown //////////////////////////
    // Sampled off the service's timerStartedAt rather than driven by a NumberAnimation. An
    // animation would have to be restart()ed when the timer is, and calling restart() on it
    // destroys the binding on `running` -- whereas a sample of (now - startedAt) is in exact
    // agreement with the real Timer for free, including after a hover restarts it. The tick only
    // runs while a toast is actually on screen and not hovered, so freezing is just not ticking.

    readonly property int timeoutInterval: root.newestNotification?.timerInterval ?? 0
    readonly property bool countdownShown: root.popup && !root.expanded
        && root.timeoutInterval > 0
        && (Config.options.notifications.showProgress ?? true)
    property real timeoutProgress: 1

    function sampleTimeout() {
        const startedAt = root.newestNotification?.timerStartedAt ?? 0;
        if (startedAt <= 0 || root.timeoutInterval <= 0) {
            root.timeoutProgress = 1;
            return;
        }
        const elapsed = Date.now() - startedAt;
        root.timeoutProgress = Math.max(0, Math.min(1, 1 - elapsed / root.timeoutInterval));
        // TEMPORARY diagnostic, remove once the countdown start is confirmed. Throttled to ~4/s.
        if (elapsed - root._lastLoggedAt >= 250) {
            root._lastLoggedAt = elapsed;
            console.log(`[NotifRing] elapsed=${Math.round(elapsed)}ms interval=${root.timeoutInterval} progress=${root.timeoutProgress.toFixed(3)}`);
        }
    }
    property real _lastLoggedAt: -1000

    // The card is built a frame or two after the notification arrives, so the first value has to be
    // measured rather than assumed to be 1 -- otherwise the ring starts full and then jumps.
    Component.onCompleted: root.sampleTimeout()

    Timer {
        running: root.countdownShown && !root.hovered
        interval: 32
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sampleTimeout()
    }

    SequentialAnimation { // Drag finish animation
        id: destroyAnimation
        property bool left: true
        running: false

        NumberAnimation {
            target: background.anchors
            property: "leftMargin"
            to: (root.width + root.dismissOvershoot) * (destroyAnimation.left ? -1 : 1)
            duration: Appearance.animation.elementMove.duration
            easing.type: Appearance.animation.elementMove.type
            easing.bezierCurve: Appearance.animation.elementMove.bezierCurve
        }
        onFinished: () => {
            root.notifications.forEach((notif) => {
                Qt.callLater(() => {
                    Notifications.discardNotification(notif.notificationId);
                });
            });
        }
    }

    function toggleExpanded() {
        if (expanded) implicitHeightAnim.enabled = true;
        else implicitHeightAnim.enabled = false;
        root.expanded = !root.expanded;
    }

    DragManager { // Drag manager
        id: dragManager
        anchors.fill: parent
        interactive: !expanded
        automaticallyReset: false
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton)
                root.toggleExpanded();
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                root.destroyWithAnimation();
                return;
            }
            if (mouse.button !== Qt.LeftButton) return;
            // A MouseArea still emits clicked after a drag, so a swipe that fell short of the
            // dismiss threshold would otherwise also count as a click on the card.
            if (Math.abs(dragManager.dragDiffX) > 8) return;
            if (!(Config.options.notifications.clickToActivate ?? true)) return;
            // A stack from one app is ambiguous -- which of the three would the click open? Expand
            // it instead, and let the click land on a specific card. Same as Android.
            if (root.multipleNotifications) {
                root.toggleExpanded();
                return;
            }
            if (root.newestNotification)
                Notifications.invokeDefault(root.newestNotification.notificationId);
        }

        onDraggingChanged: () => {
            if (dragging) {
                root.qmlParent.dragIndex = root.index ?? root.parent.children.indexOf(root);
            }
        }

        onDragDiffXChanged: () => {
            root.qmlParent.dragDistance = dragDiffX;
        }

        onDragReleased: (diffX, diffY) => {
            if (Math.abs(diffX) > root.dragConfirmThreshold)
                root.destroyWithAnimation(diffX < 0);
            else 
                dragManager.resetDrag();
        }
    }

    // Off on glass. Hyprland blurs any pixel whose alpha clears the layer's ignore_alpha, and the
    // notificationPopup rule drops that floor to 0.02 so the card's own translucent fill frosts.
    // A drop shadow spills ~10px of low-alpha pixels past the card's edge, and every one of them
    // cleared 0.02 too -- so the compositor frosted a halo around the card and it read as a soft
    // smeared line outside it. The hairline on `background` does the separating instead.
    StyledRectangularShadow {
        target: background
        visible: root.popup && !root.glass
    }
    Rectangle { // Background of the notification
        id: background
        anchors.left: parent.left
        width: parent.width
        color: root.glass
            ? ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, Config.options.notifications.transparency ?? 0.55)
            : Appearance.colors.colLayer2
        // The frosted fill alone has no edge against a busy wallpaper. Same hairline the island
        // card uses; off entirely for the lists, which sit on an opaque surface already.
        border.width: root.glass ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.normal
        anchors.leftMargin: root.xOffset

        Behavior on anchors.leftMargin {
            enabled: !dragManager.dragging
            NumberAnimation {
                duration: Appearance.animation.elementMove.duration
                easing.type: Appearance.animation.elementMove.type
                easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
            }
        }
        
        clip: true
        implicitHeight: (root.expanded || root.collapsedMaxHeight <= 0) ?
            row.implicitHeight + padding * 2 :
            Math.min(root.collapsedMaxHeight, row.implicitHeight + padding * 2)

        Behavior on implicitHeight {
            id: implicitHeightAnim
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        RowLayout { // Left column for icon, right column for content
            id: row
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: root.padding
            spacing: 10

            NotificationAppIcon { // Icons
                Layout.alignment: Qt.AlignTop
                Layout.fillWidth: false
                image: root?.multipleNotifications ? "" : notificationGroup?.notifications[0]?.image ?? ""
                appIcon: root.notificationGroup?.appIcon
                summary: root.notificationGroup?.notifications[root.notificationCount - 1]?.summary
                urgency: root.notifications.some(n => n.urgency === NotificationUrgency.Critical.toString()) ? 
                    NotificationUrgency.Critical : NotificationUrgency.Normal
            }

            ColumnLayout { // Content
                Layout.fillWidth: true
                spacing: expanded ? (root.multipleNotifications ? 
                    (notificationGroup?.notifications[root.notificationCount - 1].image != "") ? 35 : 
                    5 : 0) : 0
                // spacing: 00
                Behavior on spacing {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Item { // App name (or summary when there's only 1 notif) and time
                    id: topRow
                    // spacing: 0
                    Layout.fillWidth: true
                    property real fontSize: Appearance.font.pixelSize.smaller
                    property bool showAppName: root.multipleNotifications
                    // The ring sits 3px outside the button on every side, so the row has to reserve
                    // that or the bottom of it would graze the first line of body text.
                    implicitHeight: Math.max(topTextRow.implicitHeight, expandButton.implicitHeight + (root.countdownShown ? 6 : 0))

                    RowLayout {
                        id: topTextRow
                        anchors.left: parent.left
                        anchors.right: expandButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        StyledText {
                            id: appName
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: (topRow.showAppName ?
                                notificationGroup?.appName :
                                notificationGroup?.notifications[0]?.summary) || ""
                            font.pixelSize: topRow.showAppName ?
                                topRow.fontSize :
                                Appearance.font.pixelSize.small
                            color: topRow.showAppName ?
                                Appearance.colors.colSubtext :
                                Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            id: timeText
                            // Layout.fillWidth: true
                            Layout.rightMargin: 10
                            horizontalAlignment: Text.AlignLeft
                            text: NotificationUtils.getFriendlyNotifTimeString(notificationGroup?.time)
                            font.pixelSize: topRow.fontSize
                            color: Appearance.colors.colSubtext
                        }
                    }
                    // Countdown. Wraps the expand button rather than running along the card's
                    // bottom edge, where a straight bar fought the card's own corner radius.
                    NotificationTimeoutRing {
                        id: timeoutRing
                        anchors.centerIn: expandButton
                        // 3px of air on each side: enough to read as a ring around the button
                        // rather than a second border on it, without reaching the time text.
                        width: expandButton.width + 6
                        height: expandButton.height + 6
                        progress: root.timeoutProgress
                        // No fade-in. The ring has to read as already counting the moment the card
                        // lands; easing it up over 200ms is indistinguishable from a late start.
                        opacity: root.countdownShown ? 1 : 0
                        visible: opacity > 0
                    }

                    NotificationGroupExpandButton {
                        id: expandButton
                        compact: root.popup
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        count: root.notificationCount
                        expanded: root.expanded
                        fontSize: topRow.fontSize
                        onClicked: { root.toggleExpanded() }
                        altAction: () => { root.toggleExpanded() }

                        StyledToolTip {
                            text: Translation.tr("Tip: right-clicking a group\nalso expands it")
                        }
                    }
                }

                StyledListView { // Notification body (expanded)
                    id: notificationsColumn
                    implicitHeight: contentHeight
                    Layout.fillWidth: true
                    spacing: expanded ? 5 : 3
                    // clip: true
                    interactive: false
                    Behavior on spacing {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    model: ScriptModel {
                        values: root.expanded ? root.notifications.slice().reverse() : 
                            root.notifications.slice().reverse().slice(0, 2)
                    }
                    delegate: NotificationItem {
                        required property int index
                        required property var modelData
                        notificationObject: modelData
                        expanded: root.expanded
                        onlyNotification: (root.notificationCount === 1)
                        glass: root.glass
                        // Only the newest card in a collapsed stack gets the action row -- the one
                        // underneath is a half-faded preview, not something you can act on.
                        actionsVisible: root.popup && !root.expanded && index === 0
                            && (Config.options.notifications.showActions ?? true)
                        compactActions: root.popup && !root.expanded
                        opacity: (!root.expanded && index == 1 && root.notificationCount > 2) ? 0.5 : 1
                        visible: root.expanded || (index < 2)
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                    }
                }

            }
        }
    }
}
