import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Expanded island content: mode chips, the query field, and a clear/close button.
 *
 * The chips do nothing more than rewrite the query's prefix, so this is a discoverable front-end
 * over the prefix system LauncherSearch already implements rather than a second search engine.
 *
 * This field lives in the *bar* window, which is why Bar.qml takes exclusive keyboard focus while
 * the island is expanded. The results list (modules/ii/island/IslandSurface.qml) is rendered in
 * that same window, so the two share one focus scope and the list reads its selection back out of
 * IslandState.
 */
RowLayout {
    id: root
    spacing: 8

    readonly property var modeIcons: ({
        "all": "search",
        "apps": "apps",
        "clipboard": "content_paste",
        "emoji": "mood",
        "ai": "smart_toy",
        "keybinds": "keyboard",
        "translate": "translate"
    })

    readonly property var placeholders: ({
        "all": Translation.tr("Search, calculate or run"),
        "apps": Translation.tr("Search apps"),
        "clipboard": Translation.tr("Search clipboard history"),
        "emoji": Translation.tr("Search emoji"),
        "ai": Translation.tr("Ask AI..."),
        "keybinds": Translation.tr("Search keybinds"),
        "translate": Translation.tr("Translate — direction is detected, or use en:fa")
    })

    function focusInput(): void {
        Qt.callLater(() => input.forceActiveFocus());
    }

    Component.onCompleted: {
        input.text = LauncherSearch.query;
        input.cursorPosition = input.text.length;
        root.focusInput();
    }

    // Two-way sync without binding `text`: typing into a TextInput assigns `text` imperatively,
    // which would destroy a declarative binding on it. The guards stop the two writes looping.
    Connections {
        target: LauncherSearch
        function onQueryChanged() {
            if (input.text === LauncherSearch.query)
                return;
            input.text = LauncherSearch.query;
            input.cursorPosition = input.text.length;
        }
    }

    RowLayout {
        spacing: 2
        Layout.alignment: Qt.AlignVCenter

        Repeater {
            model: IslandState.searchModes

            delegate: Rectangle {
                id: chip
                required property string modelData
                readonly property bool active: IslandState.searchMode === chip.modelData

                implicitWidth: 27
                implicitHeight: 24
                radius: Appearance.rounding.verysmall - 2
                color: chip.active
                    ? Appearance.colors.colPrimary
                    : (chipMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.modeIcons[chip.modelData] ?? "search"
                    iconSize: Appearance.font.pixelSize.normal
                    color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        IslandState.setSearchMode(chip.modelData);
                        root.focusInput();
                    }
                }
            }
        }
    }

    Rectangle {
        width: 1
        height: 16
        color: Appearance.colors.colOutlineVariant
        Layout.alignment: Qt.AlignVCenter
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        StyledTextInput {
            id: input
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            color: Appearance.colors.colOnSurface
            selectByMouse: true
            activeFocusOnPress: true

            // A HoverHandler rather than a MouseArea: it changes the pointer without consuming
            // presses, so clicking still places the caret and dragging still selects. It also makes
            // it obvious the field is hit-testable at all.
            HoverHandler {
                cursorShape: Qt.IBeamCursor
            }

            onTextChanged: {
                if (input.text !== LauncherSearch.query)
                    LauncherSearch.query = input.text;
            }

            Keys.onEscapePressed: IslandState.close()

            Keys.onTabPressed: event => {
                IslandState.cycleSearchMode(false);
                root.focusInput();
                event.accepted = true;
            }
            Keys.onBacktabPressed: event => {
                IslandState.cycleSearchMode(true);
                root.focusInput();
                event.accepted = true;
            }

            Keys.onUpPressed: event => {
                IslandState.moveSelection(IslandState.gridColumns > 0 ? -IslandState.gridColumns : -1);
                event.accepted = true;
            }
            Keys.onDownPressed: event => {
                IslandState.moveSelection(IslandState.gridColumns > 0 ? IslandState.gridColumns : 1);
                event.accepted = true;
            }

            // Only claimed for plain arrows in the grid modes. Everything else belongs to the text
            // cursor -- and it has to be handed back explicitly, because the specific Keys handlers
            // arrive with `accepted` already true, so an early `return` still swallows the key.
            // That is what stopped Left/Right from moving through what you had typed.
            Keys.onLeftPressed: event => {
                if (!IslandState.gridMode || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) {
                    event.accepted = false;
                    return;
                }
                IslandState.moveSelection(-1);
                event.accepted = true;
            }
            Keys.onRightPressed: event => {
                if (!IslandState.gridMode || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) {
                    event.accepted = false;
                    return;
                }
                IslandState.moveSelection(1);
                event.accepted = true;
            }

            Keys.onReturnPressed: event => {
                IslandState.activateSelected();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                IslandState.activateSelected();
                event.accepted = true;
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageDown) {
                    IslandState.moveSelection(IslandState.gridColumns > 0 ? IslandState.gridColumns * 4 : 5);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    IslandState.moveSelection(IslandState.gridColumns > 0 ? -IslandState.gridColumns * 4 : -5);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                    IslandState.deleteSelected();
                    event.accepted = true;
                } else if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    IslandState.activateAt(event.key - Qt.Key_1);
                    event.accepted = true;
                }
            }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            visible: input.text.length === 0
            text: root.placeholders[IslandState.searchMode] ?? Translation.tr("Search")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    // Clears the query first and only closes on a second press, so a mistyped search doesn't cost
    // the whole surface.
    Rectangle {
        implicitWidth: 24
        implicitHeight: 24
        radius: Appearance.rounding.full
        color: closeMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
        Layout.alignment: Qt.AlignVCenter

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "close"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSurfaceVariant
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (LauncherSearch.query.length > 0) {
                    LauncherSearch.query = IslandState.prefixFor(IslandState.searchMode);
                    root.focusInput();
                } else {
                    IslandState.close();
                }
            }
        }
    }
}
