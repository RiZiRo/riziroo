import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../sidebarRight/calendar/calendar_layout.js" as CalendarLayout
import QtQuick
import QtQuick.Layouts

/**
 * The Overview tab's right column: today's date, then the month grid.
 *
 * The sidebar's CalendarWidget is top-anchored inside whatever holds it and sizes itself to a
 * fixed 38px day button, so in the island it left the bottom third of the column empty and its
 * ripple-on-hover day cells implied the days were clickable, which they are not. This version
 * derives the cell size from the space it is actually given, and spends the room that frees up on
 * a date heading -- the column needed a focal point the way the media tab has its cover art.
 *
 * The heading always shows *today*; the grid follows wherever you scroll. When those disagree the
 * heading dims and a Today pill appears, so the big number can never be mistaken for the month on
 * screen.
 */
Item {
    id: root

    property int monthShift: 0
    readonly property var viewingDate: CalendarLayout.getDateInXMonthsTime(root.monthShift)
    readonly property var calendarLayout: CalendarLayout.getCalendarLayout(root.viewingDate, root.monthShift === 0)
    readonly property bool viewingToday: root.monthShift === 0

    readonly property date today: DateTime.clock.date
    // Monday-first, so Sunday's 0 goes to the end.
    readonly property int todayColumn: (root.today.getDay() + 6) % 7
    readonly property var weekDayOrder: [1, 2, 3, 4, 5, 6, 0]

    Keys.onPressed: event => {
        if (event.modifiers !== Qt.NoModifier)
            return;
        if (event.key === Qt.Key_PageDown) {
            root.monthShift++;
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp) {
            root.monthShift--;
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onWheel: event => {
            if (event.angleDelta.y > 0)
                root.monthShift--;
            else if (event.angleDelta.y < 0)
                root.monthShift++;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ColumnLayout { // Date heading
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: -4

            opacity: root.viewingToday ? 1 : 0.4
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            StyledText {
                text: root.today.toLocaleDateString(Qt.locale(), "dddd")
                font.pixelSize: Appearance.font.pixelSize.small
                font.letterSpacing: 1.6
                color: Appearance.colors.colSubtext
            }

            StyledText {
                // All digits, so StyledText picks up the numbers font on its own.
                text: root.today.getDate()
                font.pixelSize: 46
                font.weight: Font.DemiBold
                font.letterSpacing: -1
                color: Appearance.colors.colOnLayer0
            }
        }

        StyledText { // Month of the grid below, not of the heading above
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.topMargin: 2
            text: root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
            elide: Text.ElideRight
        }

        Rectangle { // Hairline under the heading
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.topMargin: 9
            implicitHeight: 1
            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
        }

        Item { // Grid: weekday letters plus six week rows
            id: gridArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 6

            readonly property real cellSpacing: 2
            readonly property real weekDayRowHeight: 20
            // Whichever axis runs out first decides the cell, so the grid never overflows the
            // column no matter what height the dashboard card settles on.
            readonly property real cellSize: Math.max(16, Math.min(
                (gridArea.width - 6 * gridArea.cellSpacing) / 7,
                (gridArea.height - gridArea.weekDayRowHeight - 6 * gridArea.cellSpacing) / 6))

            ColumnLayout {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                spacing: gridArea.cellSpacing

                RowLayout { // Weekday letters
                    Layout.alignment: Qt.AlignHCenter
                    spacing: gridArea.cellSpacing

                    Repeater {
                        model: 7

                        // Wrapped, not a bare StyledText: Text computes its own implicit size and
                        // will not take one, so the column width has to come from a plain Item.
                        delegate: Item {
                            required property int index

                            implicitWidth: gridArea.cellSize
                            implicitHeight: gridArea.weekDayRowHeight

                            StyledText {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: Qt.locale().dayName(root.weekDayOrder[index], Locale.NarrowFormat)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                // Marks the column you are in without putting another fill on the glass.
                                color: (root.viewingToday && index === root.todayColumn)
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colSubtext
                            }
                        }
                    }
                }

                Repeater { // Week rows
                    model: 6

                    delegate: RowLayout {
                        id: weekRow
                        readonly property int weekIndex: index

                        Layout.alignment: Qt.AlignHCenter
                        spacing: gridArea.cellSpacing

                        Repeater {
                            model: 7

                            delegate: Item {
                                required property int index
                                readonly property var dayData: root.calendarLayout[weekRow.weekIndex][index]

                                implicitWidth: gridArea.cellSize
                                implicitHeight: gridArea.cellSize

                                Rectangle { // Today. The one accent in the grid.
                                    anchors.centerIn: parent
                                    implicitWidth: Math.min(parent.width, parent.height) - 2
                                    implicitHeight: implicitWidth
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimary
                                    visible: dayData.today === 1
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: dayData.day
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: dayData.today === 1 ? Font.DemiBold : Font.Normal
                                    color: dayData.today === 1 ? Appearance.colors.colOnPrimary
                                        : dayData.today === 0 ? Appearance.colors.colOnLayer0
                                        : Appearance.colors.colOutlineVariant

                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item { // Month navigation
            Layout.fillWidth: true
            implicitHeight: 28

            RippleButton { // Only there when you have scrolled away from this month
                id: todayPill
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter

                implicitWidth: todayPillText.implicitWidth + 20
                implicitHeight: 24
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive

                opacity: root.viewingToday ? 0 : 1
                visible: opacity > 0
                enabled: !root.viewingToday
                downAction: () => {
                    root.monthShift = 0;
                }

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                contentItem: StyledText {
                    id: todayPillText
                    text: Translation.tr("Today")
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 2

                NavButton {
                    symbolName: "chevron_left"
                    pressAction: () => {
                        root.monthShift--;
                    }
                }

                NavButton {
                    symbolName: "chevron_right"
                    pressAction: () => {
                        root.monthShift++;
                    }
                }
            }
        }
    }

    // `symbolName`, not `icon`: Button already owns `icon` as a grouped property.
    component NavButton: RippleButton {
        id: button
        property string symbolName
        property var pressAction

        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.verysmall

        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        downAction: () => {
            if (button.pressAction)
                button.pressAction();
        }

        contentItem: MaterialSymbol {
            text: button.symbolName
            iconSize: Appearance.font.pixelSize.larger
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
