import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts

/**
 * The Overview tab's left column: notifications, laid out for the island's glass card.
 *
 * Deliberately not CenterWidgetGroup. That one wraps the list in an opaque
 * m3surfaceContainerHigh rectangle and parks three 36px pills along the bottom. Both fight the
 * island: the card underneath is ~9% alpha, so an opaque fill drawn on top of it stacks and reads
 * as a separate grey slab (the same trap the clock popup hit), and a full-width toolbar spends a
 * tenth of the panel on two actions.
 *
 * So the cards sit straight on the glass and the two actions move into the header as icon buttons.
 * The only fills left in this column are the notification cards themselves and the accent on a
 * toggled mute.
 */
Item {
    id: root

    readonly property int count: Notifications.list.length

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout { // Header
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 6

            StyledText {
                text: Translation.tr("Notifications")
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.normal
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer0
            }

            Rectangle { // Count chip
                implicitWidth: countText.implicitWidth + 14
                implicitHeight: 19
                radius: Appearance.rounding.full
                color: Appearance.colors.colSecondaryContainer
                opacity: root.count > 0 ? 1 : 0
                visible: opacity > 0

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                StyledText {
                    id: countText
                    anchors.centerIn: parent
                    text: root.count
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            Item {
                Layout.fillWidth: true
            }

            HeaderButton {
                symbolName: Notifications.silent ? "notifications_off" : "notifications_active"
                toggled: Notifications.silent
                tooltipText: Notifications.silent
                    ? Translation.tr("Notifications silenced")
                    : Translation.tr("Silence notifications")
                pressAction: () => {
                    Notifications.silent = !Notifications.silent;
                }
            }

            HeaderButton {
                symbolName: "delete_sweep"
                enabled: root.count > 0
                tooltipText: Translation.tr("Clear all")
                pressAction: () => {
                    Notifications.discardAllNotifications();
                }
            }
        }

        Item { // List area
            Layout.fillWidth: true
            Layout.fillHeight: true

            // The list is masked rather than merely clipped, so a card scrolling past the bottom
            // dissolves instead of being sliced mid-sentence -- which is what made the collapsed
            // two-line groups look broken. The fade retracts once there is nothing left below.
            NotificationListView {
                id: listview
                anchors.fill: parent
                spacing: 6
                popup: false
                clip: true

                property real fadeStart: listview.atYEnd ? 1 : 0.86
                Behavior on fadeStart {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: listview.width
                        height: listview.height
                        radius: Appearance.rounding.normal
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
            }

            PagePlaceholder {
                shown: root.count === 0
                icon: "notifications_active"
                description: Translation.tr("Nothing")
                shape: MaterialShape.Shape.Ghostish
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
            iconSize: Appearance.font.pixelSize.larger
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            animateChange: true
            color: button.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnSurfaceVariant
        }

        StyledToolTip {
            text: button.tooltipText
        }
    }
}
