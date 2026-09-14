import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * The Focus tab's left column: the to-do list, laid out for the island's glass card.
 *
 * Deliberately not TodoWidget. That one is built for a sidebar page: a full SecondaryTabBar for
 * Unfinished/Done, a SwipeView, a 48px shadowed FAB floating over the list, and a scrim dialog for
 * adding a task. Inside the island that is a second row of tabs directly under the island's own
 * tabs, and four sub-tabs across the card once the timer's pair is counted.
 *
 * So the tab bar collapses into the header -- title, count, a Done toggle and an Add toggle, the
 * same header shape the Overview notifications column uses -- and both lists render in one
 * continuous column with a divider, so finishing a task moves it down the list instead of
 * teleporting it behind a tab. Adding a task is an inline field that unfolds under the header
 * rather than a dialog over a scrim; there is no room here for a scrim and it was never modal in
 * spirit.
 *
 * Per-task actions were a whole second row of two 30px buttons. The check became a leading
 * checkbox (the affordance people already look for) and delete only appears on hover, which is
 * what buys back the vertical space.
 */
Item {
    id: root

    property bool showDone: false
    property bool showAddField: false

    readonly property var unfinished: Todo.list
        .map((item, i) => Object.assign({}, item, { originalIndex: i }))
        .filter(item => !item.done)
    readonly property var finished: Todo.list
        .map((item, i) => Object.assign({}, item, { originalIndex: i }))
        .filter(item => item.done)

    function openAddField() {
        root.showAddField = true;
        Qt.callLater(() => taskInput.forceActiveFocus());
    }

    function commitTask() {
        const text = taskInput.text.trim();
        if (text.length === 0)
            return;
        Todo.addTask(text);
        taskInput.text = "";
        // Stays open: adding one task usually means adding the next.
        Qt.callLater(() => taskInput.forceActiveFocus());
    }

    // Matches TodoWidget's shortcuts so muscle memory survives the rewrite.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_N && !taskInput.activeFocus) {
            root.openAddField();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape && root.showAddField) {
            root.showAddField = false;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 6

            StyledText {
                text: Translation.tr("Tasks")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.normal
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer0
            }

            Rectangle { // Unfinished count
                implicitWidth: countText.implicitWidth + 14
                implicitHeight: 19
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer
                opacity: root.unfinished.length > 0 ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: root.unfinished.length
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            Item {
                Layout.fillWidth: true
            }

            HeaderButton {
                symbolName: "check_circle"
                toggled: root.showDone
                enabled: root.finished.length > 0 || root.showDone
                tooltipText: root.showDone
                    ? Translation.tr("Hide done")
                    : Translation.tr("Show done (%1)").arg(root.finished.length)
                pressAction: () => {
                    root.showDone = !root.showDone;
                }
            }

            HeaderButton {
                symbolName: "add"
                toggled: root.showAddField
                tooltipText: Translation.tr("Add task")
                pressAction: () => {
                    if (root.showAddField)
                        root.showAddField = false;
                    else
                        root.openAddField();
                }
            }
        }

        Revealer { // Inline add field
            Layout.fillWidth: true
            vertical: true
            reveal: root.showAddField

            Rectangle {
                // Revealer measures its child's implicitWidth, so this cannot just fill the parent.
                implicitWidth: root.width
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: ColorUtils.transparentize(Appearance.colors.colLayer2, 0.35)
                border.width: 1
                border.color: taskInput.activeFocus
                    ? Appearance.colors.colPrimary
                    : ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)

                Behavior on border.color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    spacing: 4

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledTextInput {
                            id: taskInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            color: Appearance.colors.colOnSurface
                            selectByMouse: true
                            activeFocusOnPress: true
                            onAccepted: root.commitTask()

                            Keys.onEscapePressed: {
                                root.showAddField = false;
                            }

                            HoverHandler {
                                cursorShape: Qt.IBeamCursor
                            }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            visible: taskInput.text.length === 0
                            text: Translation.tr("New task")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }

                    HeaderButton {
                        symbolName: "arrow_forward"
                        enabled: taskInput.text.trim().length > 0
                        tooltipText: Translation.tr("Add")
                        pressAction: () => root.commitTask()
                    }
                }
            }
        }

        Item { // List area
            id: listArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            // One list for both sections, so completing a task animates down past the divider
            // instead of vanishing into another tab. The divider is a row in the model.
            readonly property var rows: {
                const out = root.unfinished.slice();
                if (root.showDone && root.finished.length > 0) {
                    out.push({ divider: true });
                    return out.concat(root.finished);
                }
                return out;
            }

            StyledListView {
                id: listview
                anchors.fill: parent
                spacing: 2
                clip: true
                animateAppearance: false

                // listArea by id, not `parent`: ScriptModel is not an Item, so an unqualified
                // `parent` in here escapes to the enclosing component's parent and the list
                // silently comes back empty.
                model: ScriptModel {
                    values: listArea.rows
                }

                property real fadeStart: listview.atYEnd ? 1 : 0.88
                Behavior on fadeStart {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: listview.width
                        height: listview.height
                        radius: Appearance.rounding.small
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "#ffffffff"
                            }
                            GradientStop {
                                position: listview.fadeStart
                                color: "#ffffffff"
                            }
                            GradientStop {
                                position: 1
                                color: "#00ffffff"
                            }
                        }
                    }
                }

                // Deliberately one delegate holding both row shapes rather than a Loader over two
                // Components: Loader's *default* property is sourceComponent, so inline Components
                // declared as its children fight the explicit binding.
                delegate: Item {
                    id: taskDelegate
                    required property var modelData
                    readonly property bool isDivider: taskDelegate.modelData.divider === true

                    width: ListView.view.width
                    implicitHeight: taskDelegate.isDivider ? 26 : taskCard.implicitHeight

                    RowLayout { // Done divider
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 4
                        spacing: 8
                        visible: taskDelegate.isDivider

                        StyledText {
                            text: Translation.tr("Done")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.5)
                        }
                    }

                    Rectangle { // Task
                        id: taskCard
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        visible: !taskDelegate.isDivider

                        implicitHeight: taskRowLayout.implicitHeight + 14
                        radius: Appearance.rounding.small
                        color: taskHover.hovered
                            ? ColorUtils.transparentize(Appearance.colors.colLayer2, 0.3)
                            : "transparent"

                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }

                        HoverHandler {
                            id: taskHover
                        }

                        RowLayout {
                            id: taskRowLayout
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8
                            // Room for the delete button, reserved whether or not it is showing.
                            anchors.rightMargin: 6 + deleteButton.implicitWidth + 10
                            spacing: 10

                            Rectangle { // Checkbox
                                Layout.alignment: Qt.AlignTop
                                Layout.topMargin: 1
                                implicitWidth: 18
                                implicitHeight: 18
                                radius: Appearance.rounding.unsharpenmore
                                color: taskDelegate.modelData.done ? Appearance.colors.colPrimary : "transparent"
                                border.width: taskDelegate.modelData.done ? 0 : 2
                                border.color: checkMouse.containsMouse
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colOutline

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                                Behavior on border.color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "check"
                                    iconSize: 14
                                    color: Appearance.colors.colOnPrimary
                                    opacity: taskDelegate.modelData.done ? 1 : 0
                                    visible: opacity > 0

                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }

                                // Negative margins so the hit target is a comfortable 28px while
                                // the drawn box stays 18px.
                                MouseArea {
                                    id: checkMouse
                                    anchors.fill: parent
                                    anchors.margins: -5
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (taskDelegate.modelData.done)
                                            Todo.markUnfinished(taskDelegate.modelData.originalIndex);
                                        else
                                            Todo.markDone(taskDelegate.modelData.originalIndex);
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: taskDelegate.modelData.content ?? ""
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.strikeout: taskDelegate.modelData.done === true
                                color: taskDelegate.modelData.done
                                    ? Appearance.colors.colSubtext
                                    : Appearance.colors.colOnLayer0

                                Behavior on color {
                                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                }
                            }
                        }

                        // Anchored to the card rather than sitting in taskRowLayout. An item with
                        // `visible: false` is dropped from a layout entirely, so while it lived in
                        // the row its appearance on hover pushed the row's implicitHeight from the
                        // text's ~20px up to its own 28px -- the card grew and the text and
                        // checkbox slid down a few px every time the pointer crossed a task. Out
                        // here it overlays a fixed-height row, and the margin above keeps the text
                        // clear of it.
                        HeaderButton { // Delete, only while hovered
                            id: deleteButton
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            symbolName: "close"
                            iconPixelSize: Appearance.font.pixelSize.normal
                            opacity: taskHover.hovered ? 1 : 0
                            visible: opacity > 0
                            colText: Appearance.colors.colError
                            tooltipText: Translation.tr("Delete")
                            pressAction: () => {
                                Todo.deleteItem(taskDelegate.modelData.originalIndex);
                            }

                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                        }
                    }
                }
            }

            PagePlaceholder {
                shown: root.unfinished.length === 0 && (!root.showDone || root.finished.length === 0)
                icon: "check_circle"
                description: Translation.tr("Nothing to do")
                shape: MaterialShape.Shape.Clover4Leaf
                descriptionHorizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // `symbolName`, not `icon`: Button already owns `icon` as a grouped property.
    component HeaderButton: RippleButton {
        id: button
        property string symbolName
        property string tooltipText
        property var pressAction
        property real iconPixelSize: Appearance.font.pixelSize.larger
        property color colText: button.toggled
            ? Appearance.colors.colOnSecondaryContainer
            : Appearance.colors.colOnSurfaceVariant

        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        buttonRadiusPressed: Appearance.rounding.verysmall

        colBackground: "transparent"
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colLayer1Active
        colRippleToggled: Appearance.colors.colSecondaryContainerActive

        downAction: () => {
            if (button.pressAction)
                button.pressAction();
        }

        contentItem: MaterialSymbol {
            text: button.symbolName
            iconSize: button.iconPixelSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            animateChange: true
            color: button.colText
        }

        StyledToolTip {
            text: button.tooltipText
        }
    }
}
