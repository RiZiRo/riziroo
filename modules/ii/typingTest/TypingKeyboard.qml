pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string highlightedCharacter: ""
    property int keySerial: 0
    property string mode: "react"
    property string labelStyle: "lowercase"
    property color mainColor: Appearance.colors.colPrimary
    property color textColor: Appearance.colors.colOnLayer2
    property color mutedColor: Appearance.colors.colOutlineVariant
    property color keyColor: Appearance.colors.colLayer2
    property var rows: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: 7

        Repeater {
            model: root.rows
            delegate: RowLayout {
                id: keyRow
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                spacing: 7

                Repeater {
                    model: keyRow.modelData
                    delegate: KeyCap {
                        required property string modelData
                        label: modelData
                        highlighted: root.highlightedCharacter === modelData
                        triggerSerial: root.keySerial
                    }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 7

            KeyCap {
                Layout.preferredWidth: 310
                label: "space"
                highlighted: root.highlightedCharacter === " "
                triggerSerial: root.keySerial
            }
            KeyCap {
                Layout.preferredWidth: 96
                label: "backspace"
                fontPixelSize: 11
                highlighted: root.highlightedCharacter === "backspace"
                triggerSerial: root.keySerial
            }
        }
    }

    component KeyCap: Rectangle {
        id: cap
        required property string label
        property bool highlighted: false
        property int triggerSerial: 0
        property real fontPixelSize: 14
        Layout.preferredWidth: 46
        Layout.preferredHeight: 40
        radius: 10
        color: highlighted ? root.mainColor : root.keyColor
        border.width: 1
        border.color: highlighted ? root.mainColor : root.mutedColor
        scale: highlighted ? 0.91 : 1

        Behavior on color { ColorAnimation { duration: 90 } }
        Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

        // Re-flash the key on every press, including repeats of the same character.
        onTriggerSerialChanged: {
            if (highlighted) {
                pressGlow.opacity = 1;
                pressGlowFade.restart();
            }
        }
        Timer {
            id: pressGlowFade
            interval: 40
            onTriggered: pressGlow.opacity = 0
        }
        Rectangle {
            id: pressGlow
            anchors.fill: parent
            radius: cap.radius
            color: "transparent"
            border.color: root.mainColor
            border.width: 2
            opacity: 0
            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }

        StyledText {
            anchors.centerIn: parent
            text: cap.label === "space" ? "" : (root.labelStyle === "uppercase" ? cap.label.toUpperCase() : cap.label.toLowerCase())
            color: cap.highlighted ? root.keyColor : root.textColor
            font.family: Appearance.font.family.monospace
            font.pixelSize: cap.fontPixelSize
        }
    }
}
