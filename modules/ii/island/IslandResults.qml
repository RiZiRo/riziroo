import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.overview
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The search results card that grows out of the island.
 *
 * Two presentations over the same LauncherSearch results. Apps, clipboard, keybinds and the rest
 * render as rows through the overview search's own SearchItem delegate, so icon types, fuzzy-match
 * highlighting, clipboard image previews and per-result action buttons all come for free. Emoji and
 * Material symbols render as a glyph grid instead, because those are scanned rather than read.
 *
 * SearchItem needs one thing overridden: `focus` marks the keyboard selection, since its own
 * `selected` test is hovered-or-focused and only the search field holds active focus. `onClicked`
 * closes the island rather than the overview.
 */
Rectangle {
    id: root

    readonly property int rowLimit: Config.options.bar.island.maxResults
    readonly property string strippedQuery: StringUtils.cleanOnePrefix(LauncherSearch.query, IslandState.knownPrefixes)
    readonly property bool isAiMode: IslandState.searchMode === "ai"

    // Derived from the fixed panel width, never from a view's own geometry -- sizing the card from
    // contentHeight while the view is sized by the card is a binding loop.
    readonly property int gridRows: IslandState.gridColumns > 0 ? Math.ceil(IslandState.resultCount / IslandState.gridColumns) : 0
    readonly property real captionHeight: 20

    implicitWidth: Config.options.bar.island.panelWidth
    implicitHeight: {
        if (root.isAiMode)
            return Math.min(380, aiScroll.contentHeight + 32);
        if (IslandState.resultCount === 0)
            return 56;
        if (IslandState.gridMode)
            return Math.min(376, root.gridRows * IslandState.gridCellSize + 16 + root.captionHeight + 4);
        return Math.min(520, listView.contentHeight + 16);
    }

    radius: Appearance.rounding.normal
    // Not colSurfaceContainer: with automatic transparency on, that resolves to roughly 10% alpha,
    // which is both unreadable over a terminal AND below the ignore_alpha = 0.79 floor in
    // hyprland/rules.lua, so Hyprland skipped blurring it too. Above that floor the shared
    // quickshell:.* blur rule kicks in and this reads as frosted glass instead of a smear.
    color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.12)
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    StyledListView {
        id: listView
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2
        clip: true
        visible: !IslandState.gridMode && !root.isAiMode && IslandState.resultCount > 0

        model: IslandState.searchResults
        currentIndex: IslandState.selectedIndex
        onCurrentIndexChanged: listView.positionViewAtIndex(listView.currentIndex, ListView.Contain)

        delegate: SearchItem {
            required property var modelData
            required property int index

            width: listView.width
            entry: modelData
            query: root.strippedQuery
            focus: index === IslandState.selectedIndex

            // Deliberately does NOT write back to IslandState.selectedIndex on hover. It used to,
            // and that made the wheel useless: scrolling moved a new row under the cursor, which
            // moved the selection, which fired positionViewAtIndex and dragged the view straight
            // back. Hover still highlights the row on its own (SearchItem's `selected` is
            // hovered-or-focused), it just no longer steals what Enter will run.
            onClicked: IslandState.activateAt(index)
        }
    }

    // AI answer view: full wrapped text instead of a single truncated row,
    // so the answer reads right here in the results card.
    Flickable {
        id: aiScroll
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        visible: root.isAiMode
        contentWidth: width
        contentHeight: aiColumn.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds

        readonly property string aiBody: {
            if (root.strippedQuery.length === 0)
                return Translation.tr("Type a question for %1").arg(IslandAiService.modelName);
            if (IslandAiService.status === "loading" || IslandAiService.status === "idle")
                return Translation.tr("Thinking with %1...").arg(IslandAiService.modelName);
            if (IslandAiService.status === "nokey")
                return Translation.tr("No API key for %1 — type /key in the sidebar").arg(IslandAiService.modelName);
            if (IslandAiService.status === "failed")
                return IslandAiService.result.length > 0 ? IslandAiService.result : Translation.tr("Couldn't get an answer");
            return IslandAiService.result;
        }

        Column {
            id: aiColumn
            width: aiScroll.width
            spacing: 6

            Row {
                spacing: 8
                width: parent.width
                MaterialSymbol {
                    text: "smart_toy"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: IslandAiService.modelName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                width: parent.width
                text: aiScroll.aiBody
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                textFormat: Text.PlainText
            }

            StyledText {
                width: parent.width
                visible: IslandAiService.status === "ok"
                text: Translation.tr("Enter: copy • Open in sidebar via → button")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }

    // Emoji grid. Same LauncherSearch results the list renders, drawn as glyphs.
    // (hypr/hyprland/scripts/fuzzel-emoji.sh) is `<glyph> <name> <keywords>` with no category
    // field, so chips would need a whole new categorised dataset.
    Item {
        id: gridWrap
        anchors.fill: parent
        anchors.margins: 8
        visible: IslandState.gridMode && IslandState.resultCount > 0

        GridView {
            id: gridView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height - root.captionHeight - 4
            clip: true
            cellWidth: IslandState.gridCellSize
            cellHeight: IslandState.gridCellSize

            model: IslandState.searchResults
            currentIndex: IslandState.selectedIndex
            onCurrentIndexChanged: gridView.positionViewAtIndex(gridView.currentIndex, GridView.Contain)

            delegate: Rectangle {
                id: cell
                required property var modelData
                required property int index
                readonly property bool selected: cell.index === IslandState.selectedIndex

                width: IslandState.gridCellSize - 4
                height: IslandState.gridCellSize - 4
                radius: Appearance.rounding.verysmall
                color: cell.selected
                    ? Appearance.colors.colPrimaryContainer
                    : (cellMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")
                border.width: cell.selected ? 1 : 0
                border.color: Appearance.colors.colPrimary

                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: cell.modelData?.iconType !== LauncherSearchResult.IconType.Material
                    text: cell.modelData?.iconName ?? ""
                    font.pixelSize: Appearance.font.pixelSize.hugeass
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: cell.modelData?.iconType === LauncherSearchResult.IconType.Material
                    text: cell.modelData?.iconName ?? ""
                    iconSize: Appearance.font.pixelSize.hugeass
                    color: cell.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSurface
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: IslandState.selectedIndex = cell.index
                    onClicked: IslandState.activateAt(cell.index)
                }
            }
        }

        // The list rows carry their own labels; in the grid the name has nowhere to go, so the
        // selected glyph names itself down here.
        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: root.captionHeight
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: IslandState.selectedResult?.name ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // Wheel handling is explicit, following the pattern at the bottom of Lyrics.qml: NoButton so
    // clicks still reach the rows underneath, and declared last so it sits above them and actually
    // receives the wheel. StyledListView only installs its own handler when
    // interactions.scrolling.fasterTouchpadScroll is enabled, which it isn't here, and the plain
    // Flickable fallback had almost nothing to travel over.
    StyledText {
        anchors.centerIn: parent
        visible: IslandState.resultCount === 0 && !root.isAiMode
        text: LauncherSearch.query.length === 0
            ? Translation.tr("Type to search")
            : Translation.tr("No results")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: IslandState.resultCount > 0
        onWheel: wheel => {
            const view = IslandState.gridMode ? gridView : listView;
            const scrolling = Config.options.interactions.scrolling;
            const threshold = scrolling.mouseScrollDeltaThreshold;
            const steps = wheel.angleDelta.y / threshold;
            // Touchpads send small continuous deltas, wheels send multiples of ±120
            const factor = Math.abs(wheel.angleDelta.y) >= threshold ? scrolling.mouseScrollFactor : scrolling.touchpadScrollFactor;
            const maxY = Math.max(0, view.contentHeight - view.height);
            const base = view.scrollTargetY ?? view.contentY;
            view.contentY = Math.max(0, Math.min(base - steps * factor, maxY));
            wheel.accepted = true;
        }
    }
}
