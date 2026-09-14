pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * The Monkeytype config bar: rounded capsules holding flat text pills.
 * Pills are deliberately not RippleButtons — a filled Material pill reads as a
 * different app entirely. Active is just `main`-colored text, inactive is `sub`.
 */
Item {
    id: root

    required property var settings
    required property var theme

    signal restartRequested
    signal settingsRequested
    signal customLengthRequested

    readonly property var timeLengths: [15, 30, 60, 120]
    readonly property var wordLengths: [10, 25, 50, 100]
    readonly property var quoteLengths: ["all", "short", "medium", "long", "thicc"]
    readonly property bool generated: settings.mode === "time" || settings.mode === "words"
    // Under this width the punctuation/numbers capsule stops fitting next to the
    // mode capsule; both toggles stay reachable from the settings screen.
    readonly property bool veryNarrow: width < 700

    implicitHeight: 42

    function setMode(value) {
        if (root.settings.mode !== value) {
            root.settings.mode = value;
            // Keep a sane length when moving between the two generated modes.
            if (value === "time" && root.timeLengths.indexOf(root.settings.testLength) < 0)
                root.settings.testLength = 30;
            else if (value === "words" && root.wordLengths.indexOf(root.settings.testLength) < 0)
                root.settings.testLength = 50;
        }
        root.restartRequested();
    }

    RowLayout {
        anchors.centerIn: parent
        spacing: 8

        Capsule {
            visible: root.generated && !root.veryNarrow

            ConfigPill {
                glyph: "alternate_email"
                label: "punctuation"
                active: root.settings.punctuation
                onActivated: {
                    root.settings.punctuation = !root.settings.punctuation;
                    root.restartRequested();
                }
            }
            ConfigPill {
                glyph: "tag"
                label: "numbers"
                active: root.settings.numbers
                onActivated: {
                    root.settings.numbers = !root.settings.numbers;
                    root.restartRequested();
                }
            }
        }

        Capsule {
            ConfigPill { glyph: "timer"; label: "time"; active: root.settings.mode === "time"; onActivated: root.setMode("time") }
            ConfigPill { glyph: "format_size"; label: "words"; active: root.settings.mode === "words"; onActivated: root.setMode("words") }
            ConfigPill { glyph: "format_quote"; label: "quote"; active: root.settings.mode === "quote"; onActivated: root.setMode("quote") }
            ConfigPill { glyph: "air"; label: "zen"; active: root.settings.mode === "zen"; onActivated: root.setMode("zen") }
            ConfigPill { glyph: "edit_note"; label: "custom"; active: root.settings.mode === "custom"; onActivated: root.setMode("custom") }
        }

        Capsule {
            visible: root.settings.mode !== "zen"

            Repeater {
                model: root.settings.mode === "time" ? root.timeLengths
                    : root.settings.mode === "words" ? root.wordLengths
                    : root.settings.mode === "quote" ? root.quoteLengths : []
                delegate: ConfigPill {
                    required property var modelData
                    label: String(modelData)
                    active: root.settings.mode === "quote"
                        ? root.settings.quoteLength === modelData
                        : root.settings.testLength === modelData
                    onActivated: {
                        if (root.settings.mode === "quote") root.settings.quoteLength = modelData;
                        else root.settings.testLength = modelData;
                        root.restartRequested();
                    }
                }
            }

            ConfigPill {
                visible: root.settings.mode === "custom"
                glyph: "edit"
                label: "edit text"
                onActivated: root.settingsRequested()
            }

            ConfigPill {
                visible: root.generated
                glyph: "build"
                tip: "Custom length"
                // Lit when the current length is not one of the four presets.
                active: root.generated && (root.settings.mode === "time"
                    ? root.timeLengths.indexOf(root.settings.testLength) < 0
                    : root.wordLengths.indexOf(root.settings.testLength) < 0)
                onActivated: root.customLengthRequested()
            }
        }
    }

    component Capsule: Rectangle {
        id: capsule
        default property alias content: capsuleRow.data
        Layout.preferredWidth: capsuleRow.implicitWidth + 16
        Layout.preferredHeight: 42
        radius: Appearance.rounding.full
        color: root.theme.subAlt

        RowLayout {
            id: capsuleRow
            anchors.centerIn: parent
            spacing: 2
        }
    }

    component ConfigPill: Item {
        id: pill
        property string glyph: ""
        property string label: ""
        property bool active: false
        property string tip: ""
        // StyledToolTip looks for `hovered` on its parent.
        readonly property bool hovered: pillArea.containsMouse
        signal activated

        Layout.preferredWidth: pillRow.implicitWidth + (pill.label.length > 0 ? 22 : 16)
        Layout.preferredHeight: 32
        Layout.alignment: Qt.AlignVCenter

        readonly property color tint: pill.active
            ? root.theme.main
            : (pill.hovered ? root.theme.text : root.theme.sub)

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.full
            color: pill.hovered && !pill.active ? Qt.alpha(root.theme.text, 0.07) : "transparent"
            Behavior on color { ColorAnimation { duration: 110 } }
        }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            MaterialSymbol {
                visible: pill.glyph.length > 0
                text: pill.glyph
                iconSize: 16
                color: pill.tint
                Behavior on color { ColorAnimation { duration: 130 } }
            }
            StyledText {
                visible: pill.label.length > 0
                text: pill.label
                font.family: Appearance.font.family.monospace
                font.pixelSize: 13
                color: pill.tint
                Behavior on color { ColorAnimation { duration: 130 } }
            }
        }

        MouseArea {
            id: pillArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.activated()
        }

        StyledToolTip {
            text: pill.tip
            extraVisibleCondition: pill.tip.length > 0
        }
    }
}
