pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var settings
    required property var catalog
    property string importText: ""
    property string statusText: ""

    function applyCustom() {
        const result = catalog.importJson(importText);
        statusText = result.message;
        if (result.valid) {
            settings.customTheme = true;
            settings.customThemeJson = catalog.exportJson();
        }
    }

    function setColor(field, value) {
        if (!catalog.isHex(value)) {
            statusText = `${field}: enter #RGB, #RRGGBB, or #RRGGBBAA`;
            return;
        }
        const next = Object.assign({}, catalog.customColors);
        next[field] = value;
        catalog.customColors = next;
        catalog.customTheme = true;
        settings.customTheme = true;
        settings.customThemeJson = catalog.exportJson();
        statusText = catalog.validatePalette(next).message;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        StyledText { text: "theme catalog"; color: catalog.active.text; font.pixelSize: 17; font.family: Appearance.font.family.monospace }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 640 ? 2 : 4
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: root.catalog.presets
                delegate: RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 44
                    buttonRadius: 9
                    focusPolicy: Qt.NoFocus
                    colBackground: modelData.bg
                    colBackgroundHover: modelData.subAlt
                    onClicked: {
                        root.catalog.themeName = modelData.key;
                        root.catalog.customTheme = false;
                        root.settings.themeName = modelData.key;
                        root.settings.customTheme = false;
                    }
                    contentItem: RowLayout {
                        Rectangle { width: 8; height: 8; radius: 4; color: modelData.main }
                        StyledText { text: modelData.label; color: modelData.text; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
                    }
                }
            }
        }
        StyledText { text: "palette colors"; color: catalog.active.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 12 }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 650 ? 1 : 2
            columnSpacing: 10
            rowSpacing: 8
            Repeater {
                model: ["bg", "main", "caret", "sub", "subAlt", "text", "error", "errorExtra", "colorfulError", "colorfulErrorExtra"]
                delegate: Rectangle {
                    id: colorEditor
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: 9
                    color: root.catalog.active.subAlt
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        Rectangle { width: 18; height: 18; radius: 5; color: root.catalog.customColors[colorEditor.modelData] || root.catalog.active[colorEditor.modelData] }
                        StyledText { text: colorEditor.modelData.replace(/([A-Z])/g, " $1").toLowerCase(); color: root.catalog.active.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10; Layout.preferredWidth: 106 }
                        TextField {
                            Layout.fillWidth: true
                            text: root.catalog.customColors[colorEditor.modelData] || root.catalog.active[colorEditor.modelData]
                            color: root.catalog.active.text
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                            selectByMouse: true
                            onEditingFinished: root.setColor(colorEditor.modelData, text.trim())
                        }
                    }
                }
            }
        }
        StyledText { text: "custom palette JSON"; color: catalog.active.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 12 }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: catalog.active.subAlt
            radius: 9
            border.width: 1
            border.color: "#303030"
            StyledTextArea {
                id: jsonInput
                anchors.fill: parent
                anchors.margins: 10
                text: root.importText
                placeholderText: root.catalog.exportJson()
                color: root.catalog.active.text
                wrapMode: TextEdit.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: 11
                background: null
                onTextChanged: root.importText = text
            }
        }
        RowLayout {
            Layout.fillWidth: true
            StyledText { text: root.statusText || root.catalog.validatePalette(root.catalog.active).message; color: root.catalog.validatePalette(root.catalog.active).warning ? root.catalog.active.error : root.catalog.active.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.Wrap }
            RippleButton { implicitWidth: 110; implicitHeight: 38; buttonRadius: 9; focusPolicy: Qt.NoFocus; onClicked: { root.catalog.resetCustomFromPreset(); root.importText = root.catalog.exportJson(); root.statusText = "Reset to selected preset."; } contentItem: StyledText { text: "reset"; color: root.catalog.active.text; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace } }
            RippleButton { implicitWidth: 110; implicitHeight: 38; buttonRadius: 9; focusPolicy: Qt.NoFocus; toggled: true; onClicked: root.applyCustom(); contentItem: StyledText { text: "apply JSON"; color: "#000000"; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace } }
        }
    }
}
