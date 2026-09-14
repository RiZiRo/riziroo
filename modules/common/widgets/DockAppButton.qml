import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

DockButton {
    id: root
    property var appToplevel
    property var appListRoot
    property int lastFocused: -1
    property real iconSize: DockGlow.iconSize
    property real countDotWidth: 10
    property real countDotHeight: 4
    property bool appIsActive: appToplevel.toplevels.find(t => (t.activated == true)) !== undefined

    readonly property bool isSeparator: appToplevel.appId === "SEPARATOR"
    property var desktopEntry: DesktopEntries.heuristicLookup(appToplevel.appId)
    enabled: !isSeparator
    implicitWidth: isSeparator ? 1 : implicitHeight - topInset - bottomInset
    hoverEnabled: true

    // NOTE: previously a transparent MouseArea overlay tracked hover for the
    // window preview. That overlay sat on top of RippleButton's own MouseArea
    // and stole hover events, so root.hovered never became true and the
    // Windows-like hover highlight never showed. Track hover directly on the
    // button instead so the highlight + tooltip both work.
    onHoveredChanged: {
        if (hovered) {
            if (appListRoot) {
                appListRoot.lastHoveredButton = root
                appListRoot.buttonHovered = true
            }
            if (appToplevel?.toplevels?.length > 0)
                lastFocused = appToplevel.toplevels.length - 1
        } else {
            if (appListRoot && appListRoot.lastHoveredButton === root) {
                appListRoot.buttonHovered = false
            }
        }
    }

    Connections {
        target: DesktopEntries

        function onApplicationsChanged() {
            root.desktopEntry = DesktopEntries.heuristicLookup(appToplevel.appId);
        }
    }

    Loader {
        active: isSeparator
        anchors {
            fill: parent
            topMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
            bottomMargin: dockVisualBackground.margin + dockRow.padding + Appearance.rounding.normal
        }
        sourceComponent: DockSeparator {}
    }

    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            AppLaunchFeedback.launch(root.desktopEntry);
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    // Windows-like tooltip: show app name on hover so it's clear what will be clicked.
    PopupToolTip {
        text: root.desktopEntry?.name ?? root.appToplevel?.toplevels[0]?.title ?? root.appToplevel?.appId ?? ""
    }

    middleClickAction: () => {
        AppLaunchFeedback.launch(root.desktopEntry);
    }

    altAction: () => {
        TaskbarApps.togglePin(appToplevel.appId);
    }

    contentItem: Loader {
        active: !isSeparator
        sourceComponent: Item {
            anchors.centerIn: parent

            // Own-colour bloom behind the icon. The loader is wider than the
            // glyph it holds (anchored left-to-right, height from implicitSize),
            // so the short side is the real icon size.
            IconGlow {
                anchors.centerIn: iconImageLoader
                z: -1
                iconSource: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                iconSize: Math.min(iconImageLoader.width, iconImageLoader.height)
                emphasis: root.appIsActive ? 1.0 : 0.5
                boosted: root.hovered
            }

            Loader {
                id: iconImageLoader
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                active: !root.isSeparator
                sourceComponent: IconImage {
                    source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                    implicitSize: root.iconSize
                }
            }

            Loader {
                active: Config.options.dock.monochromeIcons
                anchors.fill: iconImageLoader
                sourceComponent: Item {
                    Desaturate {
                        id: desaturatedIcon
                        visible: false // There's already color overlay
                        anchors.fill: parent
                        source: iconImageLoader
                        desaturation: 0.8
                    }
                    ColorOverlay {
                        anchors.fill: desaturatedIcon
                        source: desaturatedIcon
                        color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                    }
                }
            }

            RowLayout {
                spacing: 3
                anchors {
                    top: iconImageLoader.bottom
                    topMargin: 2
                    horizontalCenter: parent.horizontalCenter
                }
                Repeater {
                    model: Math.min(appToplevel.toplevels.length, 3)
                    delegate: Rectangle {
                        required property int index
                        radius: Appearance.rounding.full
                        implicitWidth: (appToplevel.toplevels.length <= 3) ? 
                            root.countDotWidth : root.countDotHeight // Circles when too many
                        implicitHeight: root.countDotHeight
                        color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                    }
                }
            }
        }
    }
}