import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton { // Expand button
    id: root
    required property int count
    required property bool expanded
    property real fontSize: Appearance?.font.pixelSize.small ?? 12
    property real iconSize: Appearance?.font.pixelSize.normal ?? 16
    // Square and icon-only, so a progress ring drawn around it is a true circle rather than a
    // stadium. Used on toasts, where the stacked cards already say how many there are; the lists
    // keep the counted pill, since a collapsed group there shows nothing else.
    property bool compact: false
    readonly property real baseSize: fontSize + 4 * 2
    implicitHeight: root.baseSize
    implicitWidth: root.compact ? root.baseSize : Math.max(contentItem.implicitWidth + 5 * 2, 30)
    Layout.alignment: Qt.AlignVCenter
    Layout.fillHeight: false

    buttonRadius: Appearance.rounding.full
    colBackground: ColorUtils.mix(Appearance?.colors.colLayer2, Appearance?.colors.colLayer2Hover, 0.5)
    colBackgroundHover: Appearance?.colors.colLayer2Hover ?? "#E5DFED"
    colRipple: Appearance?.colors.colLayer2Active ?? "#D6CEE2"

    contentItem: Item {
        anchors.centerIn: parent
        implicitWidth: contentRow.implicitWidth
        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 3
            StyledText {
                Layout.leftMargin: 4
                visible: root.count > 1 && !root.compact
                text: root.count
                font.pixelSize: root.fontSize
            }
            MaterialSymbol {
                text: "keyboard_arrow_down"
                iconSize: root.iconSize
                color: Appearance.colors.colOnLayer2
                rotation: expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
