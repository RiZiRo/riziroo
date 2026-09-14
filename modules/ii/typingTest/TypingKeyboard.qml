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
    // "next" mode feeds the upcoming target character, which may be capitalized
    // or a shifted symbol, so matching has to ignore case and shift pairs.
    readonly property string activeKey: {
        const raw = root.highlightedCharacter;
        if (raw.length !== 1) return raw;
        const lower = raw.toLowerCase();
        return root.shiftPairs[raw] ?? lower;
    }
    readonly property var shiftPairs: ({
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
        "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]",
        ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/", "|": "\\", "~": "`"
    })
    property color mainColor: Appearance.colors.colPrimary
    property color textColor: Appearance.colors.colOnLayer2
    property color mutedColor: Appearance.colors.colOutlineVariant
    property color keyColor: Appearance.colors.colLayer2
    property var rows: [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "[", "]"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"],
        ["z", "x", "c", "v", "b", "n", "m", ",", ".", "/"]
    ]

    // The layout below is fixed-size; the whole board is scaled to whatever box
    // it is given so a short panel shrinks it instead of clipping the last row.
    readonly property real naturalWidth: 12 * 46 + 11 * 7
    readonly property real naturalHeight: 4 * 40 + 3 * 7

    Item {
        id: board
        width: root.naturalWidth
        height: root.naturalHeight
        anchors.centerIn: parent
        scale: Math.min(1, Math.min(root.width / root.naturalWidth, root.height / root.naturalHeight))
        transformOrigin: Item.Center

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
                            highlighted: root.activeKey === modelData
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
                    highlighted: root.activeKey === " "
                    triggerSerial: root.keySerial
                }
                KeyCap {
                    Layout.preferredWidth: 96
                    label: "backspace"
                    fontPixelSize: 11
                    highlighted: root.activeKey === "backspace"
                    triggerSerial: root.keySerial
                }
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
