import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Expanded island content: a compact mode menu, the query field, and close.
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

    readonly property real naturalWidth: 280

    readonly property var modeIcons: ({
        "all": "search",
        "apps": "apps",
        "files": "folder_open",
        "clipboard": "content_paste",
        "emoji": "mood",
        "symbols": "category",
        "ai": "smart_toy",
        "keybinds": "keyboard",
        "translate": "translate"
    })

    readonly property var placeholders: ({
        "all": Translation.tr("Search, calculate or run"),
        "apps": Translation.tr("Search apps"),
        "files": Translation.tr("Find files and folders"),
        "clipboard": Translation.tr("Search clipboard history"),
        "emoji": Translation.tr("Search emoji"),
        "ai": Translation.tr("Ask AI..."),
        "keybinds": Translation.tr("Search keybinds"),
        "translate": Translation.tr("Translate — direction is detected, or use en:fa")
    })

    function focusInput(): void {
        if (IslandState.searchActive)
            Qt.callLater(() => input.forceActiveFocus());
    }

    function submit(): void {
        if (IslandState.searchMode === "ai") {
            if (IslandAiService.status !== "loading")
                IslandAiService.submit();
        } else {
            IslandState.activateSelected();
        }
    }

    function openModes(): void {
        const point = modeButton.mapToItem(modeMenu.parent, 0, 0);
        modeMenu.x = Math.max(8, Math.min(point.x, modeMenu.parent.width - modeMenu.width - 8));
        modeMenu.y = Config.options.bar.bottom
            ? point.y - modeMenu.height - 12 : point.y + modeButton.height + 12;
        modeList.currentIndex = IslandState.searchModes.indexOf(IslandState.searchMode);
        modeMenu.open();
        modeList.forceActiveFocus();
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

    RippleButton {
        id: modeButton
        implicitWidth: 48
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        Layout.alignment: Qt.AlignVCenter
        colBackground: Appearance.colors.colPrimaryContainer
        contentItem: Row {
            anchors.centerIn: parent
            spacing: 2
            MaterialSymbol {
                text: root.modeIcons[IslandState.searchMode] ?? "search"
                iconSize: 18
                height: 18
                color: Appearance.colors.colOnPrimaryContainer
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 16
                height: 18
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
        onClicked: modeMenu.opened ? modeMenu.close() : root.openModes()
        StyledToolTip { text: Translation.tr("Search mode · F1 · Tab to cycle") }
    }

    // Item popup stays in the same layer window and escapes the pill's clip.
    Popup {
        id: modeMenu
        parent: Overlay.overlay
        popupType: Popup.Item
        width: 250
        height: modeList.contentHeight + 48
        padding: 8
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: root.focusInput()
        background: Rectangle {
            radius: Appearance.rounding.normal
            color: Appearance.m3colors.m3surfaceContainer
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }
        contentItem: Column {
            spacing: 6
            ListView {
                id: modeList
                width: parent.width
                height: contentHeight
                model: IslandState.searchModes
                spacing: 2
                keyNavigationEnabled: true
                function choose(index) {
                    IslandState.setSearchMode(IslandState.searchModes[index]);
                    modeMenu.close();
                }
                Keys.onReturnPressed: choose(currentIndex)
                Keys.onEnterPressed: choose(currentIndex)
                delegate: RippleButton {
                    required property string modelData
                    required property int index
                    width: modeList.width
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.small
                    colBackground: index === modeList.currentIndex
                        ? Appearance.colors.colPrimaryContainer : "transparent"
                    onClicked: modeList.choose(index)
                    contentItem: RowLayout {
                        spacing: 10
                        MaterialSymbol {
                            text: root.modeIcons[modelData] ?? "search"
                            iconSize: 19
                            color: Appearance.colors.colOnSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData === "ai" ? "AI assistant"
                                : modelData.charAt(0).toUpperCase() + modelData.slice(1)
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            text: modelData === "all" ? "—" : IslandState.prefixFor(modelData).trim()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
            StyledText {
                text: Translation.tr("Tab / Shift+Tab switch mode")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                anchors.horizontalCenter: parent.horizontalCenter
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
                if (event.modifiers & Qt.AltModifier)
                    root.openModes();
                else
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
                root.submit();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.submit();
                event.accepted = true;
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_F1) {
                    root.openModes();
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
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
                const modePrefix = IslandState.prefixFor(IslandState.searchMode);
                if (LauncherSearch.query.slice(modePrefix.length).length > 0) {
                    LauncherSearch.query = IslandState.prefixFor(IslandState.searchMode);
                    root.focusInput();
                } else {
                    IslandState.close();
                }
            }
        }
    }
}
