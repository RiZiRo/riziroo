pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

StyledListView { // Scrollable window
    id: root
    property bool popup: false

    // 0 = show every group. The popup caps itself so a burst of notifications can't walk down the
    // whole right edge of the screen; the ones past the cap collapse into the footer pill below.
    property int maxGroups: 0

    readonly property var allAppNames: root.popup ? Notifications.popupAppNameList : Notifications.appNameList
    readonly property int hiddenGroupCount: root.maxGroups > 0 ? Math.max(0, root.allAppNames.length - root.maxGroups) : 0

    spacing: 3

    model: ScriptModel {
        values: root.maxGroups > 0 ? root.allAppNames.slice(0, root.maxGroups) : root.allAppNames
    }
    delegate: NotificationGroup {
        required property int index
        required property var modelData
        popup: root.popup
        width: ListView.view.width // https://doc.qt.io/qt-6/qml-qtquick-listview.html
        notificationGroup: popup ?
            Notifications.popupGroupsByAppName[modelData] :
            Notifications.groupsByAppName[modelData]
    }

    // Lives inside contentItem, so the popup window's `mask: Region { item: listview.contentItem }`
    // keeps it clickable without any extra input region.
    footer: Item {
        width: root.width
        implicitHeight: root.hiddenGroupCount > 0 ? overflowPill.implicitHeight + 6 : 0
        visible: root.hiddenGroupCount > 0

        // No shadow, for the same reason the cards have none: a drop shadow's low-alpha spill
        // clears the layer's ignore_alpha floor, so the compositor frosts a halo around it.
        Rectangle {
            id: overflowPill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            implicitWidth: overflowText.implicitWidth + 22
            implicitHeight: 26
            radius: Appearance.rounding.full
            color: root.popup
                ? ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, Config.options.notifications.transparency ?? 0.55)
                : Appearance.colors.colLayer2
            border.width: root.popup ? 1 : 0
            border.color: Appearance.colors.colLayer0Border

            StyledText {
                id: overflowText
                anchors.centerIn: parent
                text: Translation.tr("+%1 more").arg(root.hiddenGroupCount)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                // Same destination the bar's unread count goes to: the full list, where the
                // overflow actually lives.
                onClicked: GlobalStates.sidebarRightOpen = true
            }
        }
    }
}
