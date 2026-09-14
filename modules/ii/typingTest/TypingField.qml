pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Single-line input painted from the typing test's own palette. The stock
 * QtQuick Controls TextField and SpinBox follow the shell's Material theme,
 * which renders as a white box on a pure-black panel.
 */
Rectangle {
    id: root

    required property var theme
    property string value: ""
    property string placeholder: ""
    property bool numeric: false
    property bool steppers: false
    property int minimum: 0
    property int maximum: 10000
    property int step: 1
    property bool live: false
    property alias inputItem: field

    signal committed(string value)

    implicitHeight: 36
    radius: Appearance.rounding.small
    color: root.theme.subAlt
    border.width: field.activeFocus ? 1 : 0
    border.color: Qt.alpha(root.theme.main, 0.6)

    function clamp(raw) {
        const number = Math.round(Number(raw));
        if (!isFinite(number)) return root.minimum;
        return Math.max(root.minimum, Math.min(root.maximum, number));
    }

    function commit() {
        const next = root.numeric ? String(root.clamp(field.text)) : field.text;
        if (field.text !== next) field.text = next;
        root.committed(next);
    }

    function nudge(delta) {
        field.text = String(root.clamp(Number(field.text) + delta * root.step));
        root.commit();
    }

    onValueChanged: if (!field.activeFocus && field.text !== root.value) field.text = root.value
    Component.onCompleted: field.text = root.value

    TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: root.steppers ? 56 : 12
        verticalAlignment: TextInput.AlignVCenter
        color: root.theme.text
        selectionColor: Qt.alpha(root.theme.main, 0.4)
        selectedTextColor: root.theme.text
        font.family: Appearance.font.family.monospace
        font.pixelSize: 13
        selectByMouse: true
        clip: true
        validator: root.numeric ? numberValidator : null
        inputMethodHints: root.numeric ? Qt.ImhDigitsOnly : Qt.ImhNone

        onEditingFinished: root.commit()
        onTextChanged: if (root.live) root.committed(text)
        Keys.onUpPressed: if (root.numeric) root.nudge(1)
        Keys.onDownPressed: if (root.numeric) root.nudge(-1)

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: field.text.length === 0 && root.placeholder.length > 0
            text: root.placeholder
            color: root.theme.sub
            font: field.font
        }
    }

    IntValidator { id: numberValidator; bottom: root.minimum; top: root.maximum }

    ColumnLayout {
        visible: root.steppers
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Stepper { glyph: "keyboard_arrow_up"; onActivated: root.nudge(1) }
        Stepper { glyph: "keyboard_arrow_down"; onActivated: root.nudge(-1) }
    }

    component Stepper: Item {
        id: stepper
        required property string glyph
        signal activated
        Layout.preferredWidth: 30
        Layout.preferredHeight: 15

        MaterialSymbol {
            anchors.centerIn: parent
            text: stepper.glyph
            iconSize: 15
            color: stepperArea.containsMouse ? root.theme.text : root.theme.sub
        }
        MouseArea {
            id: stepperArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: stepper.activated()
        }
    }
}
