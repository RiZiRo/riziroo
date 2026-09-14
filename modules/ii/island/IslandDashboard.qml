import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * The dashboard that grows out of the island on left-click.
 *
 * None of the three tabs reuses a right-sidebar widget any more. Every one of them assumed an
 * opaque container and a page's worth of height: they drew their own filled panel, which stacks
 * alpha on this card and reads as a grey slab, and they opened with a full tab bar, which put four
 * sub-tabs across one card once Focus's two pairs were counted. Overview and Focus are built from
 * the four Island*Panel files beside this one -- see those for the specifics.
 *
 * There is no Quick tab. The toggle grid's expand arrows open dialogs that are implemented inside
 * SidebarRightContent, and QuickSliders resolves its brightness monitor through QsWindow, which
 * comes back null inside nested loaders -- the same thing that pinned the island's own brightness
 * readout to 50%. Quick toggles stay where they work; Super+N still opens them.
 */
Rectangle {
    id: root

    readonly property var tabs: [
        {
            "id": "focus",
            "icon": "task_alt",
            "label": Translation.tr("Focus")
        },
        {
            "id": "overview",
            "icon": "dashboard",
            "label": Translation.tr("Overview")
        },
        {
            "id": "media",
            "icon": "music_note",
            "label": Translation.tr("Media")
        }
    ]

    implicitWidth: Config.options.bar.island.panelWidth
    // Lyrics want the extra room; the card animates between the two so switching tabs reshapes
    // rather than jumps.
    implicitHeight: IslandState.dashboardTab === "media" ? 470 : 430
    radius: Appearance.rounding.normal
    color: ColorUtils.transparentize(Appearance.m3colors.m3surfaceContainer, 0.12)
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: root.tabs

                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool active: IslandState.dashboardTab === tab.modelData.id

                    implicitWidth: tabRow.implicitWidth + 20
                    implicitHeight: 30
                    radius: Appearance.rounding.full
                    color: tab.active
                        ? Appearance.colors.colPrimary
                        : (tabMouse.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: tab.modelData.icon
                            iconSize: Appearance.font.pixelSize.normal
                            color: tab.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: tab.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: tab.active ? Font.DemiBold : Font.Normal
                            color: tab.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: tabMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: IslandState.dashboardTab = tab.modelData.id
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: {
                switch (IslandState.dashboardTab) {
                case "overview":
                    return overviewTab;
                case "media":
                    return mediaTab;
                default:
                    return focusTab;
                }
            }
        }
    }

    Component {
        id: overviewTab

        RowLayout {
            spacing: 12

            IslandNotificationsPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }

            // Splits the two columns without boxing either of them. A filled panel would stack
            // alpha on the card underneath and read as a grey slab; a hairline does not.
            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitWidth: 1
                color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
            }

            IslandCalendarPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }
        }
    }

    Component {
        id: focusTab

        RowLayout {
            spacing: 12

            IslandTasksPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                implicitWidth: 1
                color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
            }

            IslandTimerPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
            }
        }
    }

    Component {
        id: mediaTab

        Item {
            // Player's own lyrics mode: cover art, controls and the synced lyrics view in one
            // card, with the note button toggling back to plain controls. Opened on lyrics
            // because that is the reason to come here rather than right-click the pill.
            Loader {
                anchors.fill: parent
                active: MprisController.activePlayer !== null
                sourceComponent: Player {
                    player: MprisController.activePlayer
                    radius: Appearance.rounding.normal
                    visualizerPoints: GlobalStates.visualizerPoints
                    showLyrics: true
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: MprisController.activePlayer === null
                text: Translation.tr("Nothing playing")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }
    }
}
