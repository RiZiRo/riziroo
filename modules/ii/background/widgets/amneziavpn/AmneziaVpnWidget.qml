import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root
    configEntryName: "amneziaVpn"
    hoverEnabled: true

    property bool compact: root.configEntry.compact ?? false

    readonly property bool connected: AmneziaVpn.connected
    readonly property bool busy: AmneziaVpn.busy

    property real widgetWidth: root.compact ? 168 : 300
    property real widgetHeight: root.compact ? 168 : 236

    Behavior on widgetWidth { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }
    Behavior on widgetHeight { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }

    implicitWidth: widgetWidth
    implicitHeight: widgetHeight

    // The base type uses onClicked for right-click lock toggling, so re-implement that
    // here rather than losing it, and make the whole card the connect/disconnect target.
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            Config.options.background.widgetsLocked = !Config.options.background.widgetsLocked;
            return;
        }
        AmneziaVpn.toggle();
    }

    property color colCard: root.busy
        ? Appearance.colors.colTertiaryContainer
        : (root.connected ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2)
    property color colAccent: root.busy
        ? Appearance.colors.colTertiary
        : (root.connected ? Appearance.colors.colPrimary : Appearance.colors.colSecondary)
    property color colOnAccent: root.busy
        ? Appearance.colors.colOnTertiary
        : (root.connected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondary)
    property color colOnCard: root.busy
        ? Appearance.colors.colOnTertiaryContainer
        : (root.connected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2)

    Behavior on colCard { ColorAnimation { duration: 250 } }
    Behavior on colAccent { ColorAnimation { duration: 250 } }

    readonly property string stateIcon: root.busy ? "sync" : (root.connected ? "vpn_lock" : "vpn_key_off")
    readonly property int stateShape: root.busy
        ? MaterialShape.Shape.Sunny
        : (root.connected ? MaterialShape.Shape.Clover4Leaf : MaterialShape.Shape.Circle)
    readonly property string subtitleText: {
        if (AmneziaVpn.lastError.length > 0)
            return AmneziaVpn.lastError;
        const bits = [];
        if (AmneziaVpn.serverName.length > 0) bits.push(AmneziaVpn.serverName);
        if (AmneziaVpn.protocolName.length > 0) bits.push(AmneziaVpn.protocolName);
        if (root.connected && AmneziaVpn.uptimeText.length > 0) bits.push(AmneziaVpn.uptimeText);
        if (bits.length === 0) bits.push("AmneziaVPN");
        return bits.join(" · ");
    }

    component PowerShape: MaterialShapeWrappedMaterialSymbol {
        id: powerShape
        property real diameter: 46
        shape: root.stateShape
        color: root.colAccent
        colSymbol: root.colOnAccent
        text: root.stateIcon
        iconSize: Math.round(diameter * 0.44)
        fill: 1
        padding: Math.round(diameter * 0.15)
        implicitWidth: diameter
        implicitHeight: diameter
        scale: root.containsMouse ? 1.06 : 1
        Behavior on scale { animation: Appearance.animation.elementResize.numberAnimation.createObject(this) }

        RotationAnimation on rotation {
            running: root.busy
            from: 0
            to: 360
            duration: 2000
            loops: Animation.Infinite
        }
    }

    component TrafficPill: Rectangle {
        id: pill
        property string icon: ""
        property string speed: ""
        property string total: ""
        Layout.fillWidth: true
        implicitHeight: 52
        radius: Appearance.rounding.normal
        color: ColorUtils.transparentize(root.colOnCard, 0.88)

        RowLayout {
            anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
            spacing: 5

            MaterialSymbol {
                text: pill.icon
                iconSize: Appearance.font.pixelSize.larger
                color: root.colOnCard
                opacity: 0.8
            }
            ColumnLayout {
                spacing: -2
                StyledText {
                    text: pill.speed
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: root.colOnCard
                }
                StyledText {
                    text: pill.total
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.colOnCard
                    opacity: 0.6
                }
            }
            Item { Layout.fillWidth: true }
        }
    }

    StyledRectangularShadow {
        target: contentRect
        z: -2
    }

    Rectangle {
        id: contentRect
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: root.colCard

        // Expanded
        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 0
            visible: !root.compact

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                PowerShape { diameter: 46 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -3
                    StyledText {
                        text: AmneziaVpn.statusText
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Bold
                        color: root.colOnCard
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.subtitleText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colOnCard
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "open_in_new"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.colOnCard
                    opacity: openAppArea.containsMouse ? 1 : 0.45
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    MouseArea {
                        id: openAppArea
                        anchors.fill: parent
                        anchors.margins: -7
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AmneziaVpn.openApp()
                    }
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }

            // Explicit action button, so the click target is obvious
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance.rounding.full
                color: actionArea.containsMouse
                    ? ColorUtils.mix(root.colAccent, root.colOnAccent, 0.88)
                    : root.colAccent

                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: root.connected ? "link_off" : (AmneziaVpn.appRunning ? "open_in_new" : "power_settings_new")
                        iconSize: Appearance.font.pixelSize.large
                        color: root.colOnAccent
                    }
                    StyledText {
                        text: AmneziaVpn.actionText
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: root.colOnAccent
                    }
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AmneziaVpn.toggle()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8
                visible: root.connected
                TrafficPill {
                    icon: "arrow_downward"
                    speed: AmneziaVpn.formatSpeed(AmneziaVpn.rxSpeed)
                    total: AmneziaVpn.formatBytes(AmneziaVpn.rxBytes)
                }
                TrafficPill {
                    icon: "arrow_upward"
                    speed: AmneziaVpn.formatSpeed(AmneziaVpn.txSpeed)
                    total: AmneziaVpn.formatBytes(AmneziaVpn.txBytes)
                }
            }
        }

        // Compact
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 7
            visible: root.compact

            PowerShape {
                Layout.alignment: Qt.AlignHCenter
                diameter: 66
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: AmneziaVpn.statusText
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: root.colOnCard
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.connected
                    ? `↓ ${AmneziaVpn.formatSpeed(AmneziaVpn.rxSpeed)}   ↑ ${AmneziaVpn.formatSpeed(AmneziaVpn.txSpeed)}`
                    : AmneziaVpn.actionText
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.colOnCard
                opacity: 0.6
            }
        }
    }

    Rectangle {
        id: sizeHandle
        width: 16
        height: 16
        radius: 6
        color: root.colOnCard
        anchors {
            left: parent.right
            bottom: parent.bottom
            margins: -6
        }
        opacity: root.containsMouse || sizeHandleArea.containsMouse ? 0.7 : 0
        visible: opacity > 0 && !Config.options.background.widgetsLocked

        Behavior on opacity { NumberAnimation { duration: 150 } }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.compact ? "open_in_full" : "close_fullscreen"
            iconSize: 11
            color: root.colCard
        }

        MouseArea {
            id: sizeHandleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.compact = !root.compact;
                root.configEntry.compact = root.compact;
            }
        }
    }
}
