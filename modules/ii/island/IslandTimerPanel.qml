import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell

/**
 * The Focus tab's right column: pomodoro and stopwatch, laid out for the island's glass card.
 *
 * Deliberately not PomodoroWidget. That one opens with a full SecondaryTabBar, which -- stacked
 * under the island's own tabs and beside the task list's former tab bar -- put four sub-tabs on one
 * card. It becomes a small segmented control here instead.
 *
 * The dial is gone too. ClockPicker drew a filled backing circle (an opaque fill on glass), twelve
 * numbers, twelve tick dots, a canvas hand and a hand tip: about thirty elements to express one
 * number, on a surface that is mostly transparent. A single depleting ring says the same thing, and
 * the minutes are still draggable -- grab the ring while stopped. The cycle counter, which was an
 * unlabelled "1" in a circle, became dots that read as progress toward the long break.
 */
Item {
    id: root

    property int tab: 0 // 0 = pomodoro, 1 = stopwatch

    readonly property var tabs: [
        {
            "icon": "timer",
            "label": Translation.tr("Pomodoro")
        },
        {
            "icon": "timelapse",
            "label": Translation.tr("Stopwatch")
        }
    ]

    // Matches PomodoroWidget's shortcuts so muscle memory survives the rewrite.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_S) {
            if (root.tab === 0)
                TimerService.togglePomodoro();
            else
                TimerService.toggleStopwatch();
            event.accepted = true;
        } else if (event.key === Qt.Key_R) {
            if (root.tab === 0)
                TimerService.resetPomodoro();
            else
                TimerService.stopwatchReset();
            event.accepted = true;
        } else if (event.key === Qt.Key_L && root.tab === 1) {
            TimerService.stopwatchRecordLap();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout { // Segmented tab control
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 4

            Repeater {
                model: root.tabs

                delegate: Rectangle {
                    id: tabChip
                    required property var modelData
                    required property int index
                    readonly property bool active: root.tab === tabChip.index

                    implicitWidth: tabChipRow.implicitWidth + 18
                    implicitHeight: 26
                    radius: Appearance.rounding.full
                    color: tabChip.active
                        ? Appearance.colors.colSecondaryContainer
                        : (tabChipMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent")

                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    RowLayout {
                        id: tabChipRow
                        anchors.centerIn: parent
                        spacing: 5

                        MaterialSymbol {
                            text: tabChip.modelData.icon
                            iconSize: Appearance.font.pixelSize.small
                            color: tabChip.active
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnSurfaceVariant
                        }

                        StyledText {
                            text: tabChip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: tabChip.active ? Font.DemiBold : Font.Normal
                            color: tabChip.active
                                ? Appearance.colors.colOnSecondaryContainer
                                : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    MouseArea {
                        id: tabChipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.tab = tabChip.index
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
            sourceComponent: root.tab === 0 ? pomodoroTab : stopwatchTab
        }
    }

    Component {
        id: pomodoroTab

        Item {
            id: pomodoroRoot
            readonly property bool running: TimerService.pomodoroRunning
            readonly property int lap: Math.max(1, TimerService.pomodoroLapDuration)

            // The ring means two different things, and which one depends on whether this lap has
            // started. Fresh and stopped, it is "how long is this lap", out of a full turn = 60
            // minutes, and the arc ends exactly at the drag handle. Running or paused, it is "how
            // much of the lap is left". Conflating the two made a half-dialled timer read as
            // half-elapsed before it had run at all.
            readonly property bool settable: !pomodoroRoot.running
                && TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration
                && !TimerService.pomodoroBreak

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item { // Ring
                    id: ringArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignHCenter

                    // Square, and never larger than the space it is given, so the ring cannot
                    // overflow the column at any dashboard height. The column offers roughly
                    // 287x310, so the cap is what actually sizes the ring.
                    readonly property real size: Math.max(80, Math.min(ringArea.width, ringArea.height, 250))
                    readonly property real ringThickness: 8
                    readonly property real ringRadius: (size - ringThickness) / 2
                    readonly property real centerX: ringArea.width / 2
                    readonly property real centerY: ringArea.height / 2

                    // Minutes <-> angle. 60 minutes is one full turn, snapped to 5, matching the
                    // dial this replaces. Held locally while the drag is in flight and only
                    // committed to Config on release -- Config writes hit the disk, and binding
                    // this straight to the drag wrote the file on every mouse move.
                    property int pendingMinutes: -1
                    readonly property int setMinutes: ringArea.pendingMinutes > 0
                        ? ringArea.pendingMinutes
                        : Math.max(1, Math.round(TimerService.focusTime / 60))
                    readonly property real handleAngle: (setMinutes / 60) * 2 * Math.PI - Math.PI / 2

                    readonly property real progress: pomodoroRoot.settable
                        ? Math.max(0, Math.min(1, setMinutes / 60))
                        : Math.max(0, Math.min(1, TimerService.pomodoroSecondsLeft / pomodoroRoot.lap))

                    Shape {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath { // Track
                            strokeColor: ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.78)
                            strokeWidth: ringArea.ringThickness
                            capStyle: ShapePath.RoundCap
                            fillColor: "transparent"

                            PathAngleArc {
                                centerX: ringArea.centerX
                                centerY: ringArea.centerY
                                radiusX: ringArea.ringRadius
                                radiusY: ringArea.ringRadius
                                startAngle: -90
                                sweepAngle: 360
                            }
                        }

                        ShapePath { // Remaining
                            strokeColor: TimerService.pomodoroBreak
                                ? Appearance.colors.colTertiary
                                : Appearance.colors.colPrimary
                            strokeWidth: ringArea.ringThickness
                            capStyle: ShapePath.RoundCap
                            fillColor: "transparent"

                            PathAngleArc {
                                centerX: ringArea.centerX
                                centerY: ringArea.centerY
                                radiusX: ringArea.ringRadius
                                radiusY: ringArea.ringRadius
                                startAngle: -90
                                // Never exactly 360: a full sweep with round caps draws the cap
                                // over the start of the arc and shows as a notch.
                                sweepAngle: Math.min(359.9, ringArea.progress * 360)

                                Behavior on sweepAngle {
                                    // Short, and off while dragging -- the timer ticks once a
                                    // second, so anything slower lags visibly behind the digits.
                                    enabled: !ringDrag.pressed
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { // Drag handle, only while the ring is settable
                        implicitWidth: ringArea.ringThickness + 8
                        implicitHeight: implicitWidth
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimary
                        border.width: 2
                        border.color: Appearance.colors.colLayer0
                        x: ringArea.centerX + ringArea.ringRadius * Math.cos(ringArea.handleAngle) - width / 2
                        y: ringArea.centerY + ringArea.ringRadius * Math.sin(ringArea.handleAngle) - height / 2

                        opacity: pomodoroRoot.settable ? 1 : 0
                        visible: opacity > 0
                        scale: ringDrag.pressed ? 1.25 : 1

                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        Behavior on scale {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    ColumnLayout { // Readout
                        anchors.centerIn: parent
                        spacing: -2

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: {
                                // While the ring is being dialled the committed value is still the
                                // old one, so read the pending minutes instead or the digits lag a
                                // whole drag behind the handle.
                                const total = pomodoroRoot.settable
                                    ? ringArea.setMinutes * 60
                                    : TimerService.pomodoroSecondsLeft;
                                const m = Math.floor(total / 60).toString().padStart(2, "0");
                                const s = Math.floor(total % 60).toString().padStart(2, "0");
                                return `${m}:${s}`;
                            }
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Math.round(ringArea.size * 0.24)
                            font.weight: Font.DemiBold
                            font.letterSpacing: -1
                            font.features: {
                                "tnum": 1
                            }
                            color: Appearance.colors.colOnLayer0
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: TimerService.pomodoroLongBreak ? Translation.tr("Long break")
                                : TimerService.pomodoroBreak ? Translation.tr("Break")
                                : Translation.tr("Focus")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.letterSpacing: 1.2
                            color: Appearance.colors.colSubtext
                        }
                    }

                    // Only live on a fresh, stopped focus lap, so neither a running nor a paused
                    // timer can be scrubbed by accident.
                    MouseArea {
                        id: ringDrag
                        anchors.fill: parent
                        enabled: pomodoroRoot.settable
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        function minutesAt(mx, my) {
                            const dx = mx - ringArea.centerX;
                            const dy = my - ringArea.centerY;
                            let a = Math.atan2(dy, dx) + Math.PI / 2;
                            if (a < 0)
                                a += 2 * Math.PI;
                            const snapped = Math.round((a / (2 * Math.PI)) * 60 / 5) * 5;
                            return snapped === 0 ? 60 : snapped;
                        }

                        onPressed: event => {
                            ringArea.pendingMinutes = ringDrag.minutesAt(event.x, event.y);
                        }
                        onPositionChanged: event => {
                            if (ringDrag.pressed)
                                ringArea.pendingMinutes = ringDrag.minutesAt(event.x, event.y);
                        }
                        // Committed once, on release. Config.options writes go to disk, so doing
                        // this per mouse-move would rewrite the config file dozens of times a drag.
                        onReleased: {
                            if (ringArea.pendingMinutes <= 0)
                                return;
                            const seconds = ringArea.pendingMinutes * 60;
                            ringArea.pendingMinutes = -1;
                            Config.options.time.pomodoro.focus = seconds;
                            TimerService.pomodoroSecondsLeft = seconds;
                        }
                    }
                }

                RowLayout { // Cycle dots
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 4
                    spacing: 5

                    Repeater {
                        model: TimerService.cyclesBeforeLongBreak

                        delegate: Rectangle {
                            required property int index
                            readonly property bool filled: index <= TimerService.pomodoroCycle

                            implicitWidth: 6
                            implicitHeight: 6
                            radius: Appearance.rounding.full
                            color: filled
                                ? Appearance.colors.colPrimary
                                : ColorUtils.transparentize(Appearance.colors.colOnSurfaceVariant, 0.72)

                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 3
                        text: Translation.tr("cycle %1 of %2")
                            .arg(TimerService.pomodoroCycle + 1)
                            .arg(TimerService.cyclesBeforeLongBreak)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }

                RowLayout { // Controls
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    spacing: 8

                    PrimaryButton {
                        symbolName: pomodoroRoot.running ? "pause" : "play_arrow"
                        text: pomodoroRoot.running ? Translation.tr("Pause")
                            : (TimerService.pomodoroSecondsLeft === TimerService.pomodoroLapDuration)
                                ? Translation.tr("Start")
                                : Translation.tr("Resume")
                        pressAction: () => TimerService.togglePomodoro()
                    }

                    // Reset is not destructive, so it is a quiet outline rather than the
                    // error-container red the sidebar used.
                    QuietButton {
                        text: Translation.tr("Reset")
                        enabled: TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration
                            || TimerService.pomodoroCycle > 0
                            || TimerService.pomodoroBreak
                        pressAction: () => TimerService.resetPomodoro()
                    }
                }
            }
        }
    }

    Component {
        id: stopwatchTab

        Item {
            id: stopwatchRoot
            readonly property bool running: TimerService.stopwatchRunning
            readonly property var laps: TimerService.stopwatchLaps

            function formatHundredths(value) {
                const total = Math.floor(value);
                const hundredths = (total % 100).toString().padStart(2, "0");
                const totalSeconds = Math.floor(total / 100);
                const minutes = Math.floor(totalSeconds / 60).toString().padStart(2, "0");
                const seconds = (totalSeconds % 60).toString().padStart(2, "0");
                return {
                    "main": `${minutes}:${seconds}`,
                    "fraction": hundredths
                };
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item { // Elapsed. Centred with no laps, top-aligned once the list needs the room.
                    id: elapsedArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        // Anchored left/right rather than centred, so the laps list below has a
                        // real width to fill.
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: stopwatchRoot.laps.length > 0 ? undefined : parent.verticalCenter
                        anchors.top: stopwatchRoot.laps.length > 0 ? parent.top : undefined
                        anchors.topMargin: 6
                        spacing: 6

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 1

                            StyledText {
                                text: formatHundredths(TimerService.stopwatchTime).main
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: 64
                                font.weight: Font.DemiBold
                                font.letterSpacing: -1
                                font.features: {
                                    "tnum": 1
                                }
                                color: Appearance.colors.colOnLayer0
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignBottom
                                Layout.bottomMargin: 8
                                text: `.${formatHundredths(TimerService.stopwatchTime).fraction}`
                                font.family: Appearance.font.family.numbers
                                font.pixelSize: 28
                                font.features: {
                                    "tnum": 1
                                }
                                color: Appearance.colors.colSubtext
                            }
                        }

                        StyledListView { // Laps
                            id: lapsList
                            Layout.fillWidth: true
                            Layout.preferredHeight: stopwatchRoot.laps.length > 0 ? 104 : 0
                            visible: stopwatchRoot.laps.length > 0
                            spacing: 1
                            clip: true

                            Behavior on Layout.preferredHeight {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }

                            model: ScriptModel {
                                values: stopwatchRoot.laps.map((v, i, arr) => arr[arr.length - 1 - i])
                            }

                            delegate: RowLayout {
                                id: lapRow
                                required property int index
                                required property var modelData
                                readonly property int lapNumber: stopwatchRoot.laps.length - lapRow.index

                                width: ListView.view.width
                                spacing: 8

                                StyledText {
                                    Layout.leftMargin: 8
                                    Layout.preferredWidth: 18
                                    text: `${lapRow.lapNumber}`
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: {
                                        const parts = formatHundredths(lapRow.modelData);
                                        return `${parts.main}.${parts.fraction}`;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.features: {
                                        "tnum": 1
                                    }
                                    color: Appearance.colors.colOnLayer0
                                }

                                StyledText {
                                    Layout.rightMargin: 8
                                    text: {
                                        const original = stopwatchRoot.laps.length - lapRow.index - 1;
                                        const previous = original > 0 ? stopwatchRoot.laps[original - 1] : 0;
                                        const parts = formatHundredths(lapRow.modelData - previous);
                                        return `+${parts.main}.${parts.fraction}`;
                                    }
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.features: {
                                        "tnum": 1
                                    }
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }

                RowLayout { // Controls
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    spacing: 8

                    PrimaryButton {
                        symbolName: stopwatchRoot.running ? "pause" : "play_arrow"
                        text: stopwatchRoot.running ? Translation.tr("Pause")
                            : TimerService.stopwatchTime === 0 ? Translation.tr("Start")
                            : Translation.tr("Resume")
                        pressAction: () => TimerService.toggleStopwatch()
                    }

                    QuietButton {
                        text: stopwatchRoot.running ? Translation.tr("Lap") : Translation.tr("Reset")
                        enabled: TimerService.stopwatchTime > 0 || stopwatchRoot.laps.length > 0
                        pressAction: () => {
                            if (stopwatchRoot.running)
                                TimerService.stopwatchRecordLap();
                            else
                                TimerService.stopwatchReset();
                        }
                    }
                }
            }
        }
    }

    // `symbolName`, not `icon`: Button already owns `icon` as a grouped property.
    component PrimaryButton: RippleButton {
        id: primaryButton
        property string symbolName
        property var pressAction

        implicitHeight: 34
        implicitWidth: primaryButtonRow.implicitWidth + 30
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.small

        colBackground: Appearance.colors.colPrimary
        colBackgroundHover: Appearance.colors.colPrimaryHover
        colRipple: Appearance.colors.colPrimaryActive

        downAction: () => {
            if (primaryButton.pressAction)
                primaryButton.pressAction();
        }

        contentItem: Item {
            RowLayout {
                id: primaryButtonRow
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    text: primaryButton.symbolName
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnPrimary
                    animateChange: true
                }

                StyledText {
                    text: primaryButton.text
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    component QuietButton: RippleButton {
        id: quietButton
        property var pressAction

        implicitHeight: 34
        implicitWidth: quietButtonText.implicitWidth + 30
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.small

        border: true
        colBorder: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.3)
        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active

        downAction: () => {
            if (quietButton.pressAction)
                quietButton.pressAction();
        }

        contentItem: StyledText {
            id: quietButtonText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: quietButton.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
