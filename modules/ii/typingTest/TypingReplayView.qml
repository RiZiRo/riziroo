pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    required property var result
    property color backgroundColor: "#080808"
    property color textColor: "#eeeeee"
    property color mutedColor: "#555555"
    property color errorColor: "#ca4754"
    property int replayTime: 0
    property bool playing: false
    property string replayText: ""
    readonly property int duration: Number(result?.durationMs || 0)

    color: backgroundColor
    radius: 12

    function rebuild() {
        let text = "";
        for (const event of (result?.events || [])) {
            if (event.t > replayTime) break;
            if (event.type === "insert") text += event.text;
            else if (event.type === "delete" || event.type === "deleteWord") text = text.slice(0, Math.max(0, text.length - String(event.text || "").length));
        }
        replayText = text;
    }

    function restart() {
        replayTime = 0;
        replayText = "";
        playing = true;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            StyledText { text: "deterministic replay"; color: root.textColor; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
            Item { Layout.fillWidth: true }
            StyledText { text: `${(root.replayTime / 1000).toFixed(1)} / ${(root.duration / 1000).toFixed(1)}s`; color: root.mutedColor; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
            RippleButton {
                implicitWidth: 34; implicitHeight: 30; buttonRadius: 8; focusPolicy: Qt.NoFocus
                onClicked: root.playing = !root.playing
                contentItem: MaterialSymbol { text: root.playing ? "pause" : "play_arrow"; iconSize: 17; color: root.textColor; horizontalAlignment: Text.AlignHCenter }
            }
            RippleButton {
                implicitWidth: 34; implicitHeight: 30; buttonRadius: 8; focusPolicy: Qt.NoFocus
                onClicked: root.restart()
                contentItem: MaterialSymbol { text: "replay"; iconSize: 17; color: root.textColor; horizontalAlignment: Text.AlignHCenter }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.replayText.length > 0 ? root.replayText : "Replay starts from the first recorded input."
            color: root.replayText.length > 0 ? root.textColor : root.mutedColor
            wrapMode: Text.Wrap
            font.family: Appearance.font.family.monospace
            font.pixelSize: 18
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            radius: 2
            color: "#222222"
            Rectangle { height: parent.height; width: parent.width * Math.min(1, root.replayTime / Math.max(1, root.duration)); radius: parent.radius; color: root.textColor }
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: root.playing
        onTriggered: {
            root.replayTime = Math.min(root.duration, root.replayTime + interval);
            root.rebuild();
            if (root.replayTime >= root.duration) root.playing = false;
        }
    }

    onReplayTimeChanged: rebuild()
}
