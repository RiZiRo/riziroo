pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Searchable language/word-pack picker, opened from the globe line under the
 * config bar. Lists the built-in packs, the shipped JSON packs, and anything
 * the user dropped in the languages folder.
 */
Item {
    id: root

    required property var typingData
    required property var settings
    required property var theme

    property string query: ""

    signal closeRequested
    signal picked(string key)

    readonly property var matches: {
        const needle = root.query.trim().toLowerCase();
        const all = root.typingData.profiles;
        if (needle.length === 0) return all;
        return all.filter(item => String(item.label).toLowerCase().includes(needle)
            || String(item.key).toLowerCase().includes(needle));
    }

    function commit(key) {
        root.picked(key);
    }

    // Dims the test behind the modal instead of hiding it.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(root.theme.bg, 0.78)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 60, 460)
        height: Math.min(parent.height - 40, 420)
        radius: Appearance.rounding.large
        color: root.theme.bg
        border.width: 1
        border.color: Qt.alpha(root.theme.sub, 0.4)

        // Swallow clicks so they do not reach the dismiss layer behind the card.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MaterialSymbol { text: "language"; iconSize: 18; color: root.theme.main }
                StyledText {
                    Layout.fillWidth: true
                    text: "language"
                    color: root.theme.text
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 15
                }
                StyledText {
                    text: `${root.matches.length}`
                    color: root.theme.sub
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: Appearance.rounding.small
                color: root.theme.subAlt

                TextInput {
                    id: searchInput
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.theme.text
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 13
                    selectByMouse: true
                    focus: true
                    onTextChanged: root.query = text
                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: if (root.matches.length > 0) root.commit(root.matches[0].key)

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "search packs"
                        color: root.theme.sub
                        font: searchInput.font
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: root.matches
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: languageRow
                    required property var modelData
                    width: ListView.view.width
                    height: 38
                    radius: Appearance.rounding.small
                    readonly property bool selected: root.settings.language === languageRow.modelData.key
                    color: languageRow.selected ? Qt.alpha(root.theme.main, 0.16)
                        : (rowArea.containsMouse ? Qt.alpha(root.theme.text, 0.07) : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        StyledText {
                            Layout.fillWidth: true
                            text: languageRow.modelData.label
                            color: languageRow.selected ? root.theme.main : root.theme.text
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: languageRow.modelData.direction === "rtl"
                            text: "rtl"
                            color: root.theme.sub
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                        }
                        StyledText {
                            visible: languageRow.modelData.kind === "quotes"
                            text: "quotes"
                            color: root.theme.sub
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 10
                        }
                        MaterialSymbol {
                            visible: languageRow.modelData.user === true
                            text: "folder"
                            iconSize: 14
                            color: root.theme.sub
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commit(languageRow.modelData.key)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: `drop Monkeytype JSON in ${Directories.typingTestLanguagesUser}`
                color: root.theme.sub
                font.family: Appearance.font.family.monospace
                font.pixelSize: 9
                elide: Text.ElideMiddle
            }
        }
    }
}
