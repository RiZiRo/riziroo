import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.sidebarRight
import qs.modules.ii.sidebarRight.calendar
import qs.modules.ii.sidebarRight.todo
import qs.modules.ii.sidebarRight.pomodoro
import QtQuick
import QtQuick.Layouts

/**
 * The dashboard that grows out of the island on left-click.
 *
 * Every panel in here is an existing widget from the right sidebar, used as-is: the notification
 * list, the calendar, the to-do list and the pomodoro timer are all self-contained and already
 * expect to be sized by whatever holds them. Nothing about them is reimplemented.
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
            "id": "overview",
            "icon": "dashboard",
            "label": Translation.tr("Overview")
        },
        {
            "id": "focus",
            "icon": "task_alt",
            "label": Translation.tr("Focus")
        },
        {
            "id": "media",
            "icon": "music_note",
            "label": Translation.tr("Media")
        }
    ]

    // Panels sit on this, so it carries the frost: alpha above the ignore_alpha = 0.79 floor in
    // hyprland/rules.lua is what lets the shared quickshell:.* blur rule apply at all.
    readonly property color panelColor: Appearance.m3colors.m3surfaceContainerHigh

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
                case "focus":
                    return focusTab;
                case "media":
                    return mediaTab;
                default:
                    return overviewTab;
                }
            }
        }
    }

    Component {
        id: overviewTab

        RowLayout {
            spacing: 10

            CenterWidgetGroup {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: root.panelColor
            }

            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                radius: Appearance.rounding.normal
                color: root.panelColor
                clip: true

                CalendarWidget {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                }
            }
        }
    }

    Component {
        id: focusTab

        RowLayout {
            spacing: 10

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: Appearance.rounding.normal
                color: root.panelColor
                clip: true

                TodoWidget {
                    anchors.fill: parent
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                radius: Appearance.rounding.normal
                color: root.panelColor
                clip: true

                PomodoroWidget {
                    anchors.fill: parent
                }
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
