pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var result
    required property var theme
    property bool showWpm: true
    property bool showRaw: true
    property bool showBurst: true
    property bool showErrors: true
    property bool showPb: true
    property bool replayOpen: false
    property bool detailOpen: false
    signal repeatRequested
    signal nextRequested
    signal practiceRequested(string kind)
    signal copyRequested(string text)

    function summary() {
        return `${result.wpm || 0} wpm · ${result.rawWpm || 0} raw · ${result.accuracy || 0}% accuracy · ${result.consistency || 0}% consistency · ${result.mode || "test"} ${result.length || ""} · ${result.language || "english"}`;
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: resultColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: resultColumn
            width: parent.width
            spacing: 14
            GridLayout {
                Layout.fillWidth: true
                columns: width < 720 ? 2 : 4
                columnSpacing: 10
                rowSpacing: 10
                Metric { label: "wpm"; value: String(root.result.wpm || 0); prominent: true }
                Metric { label: "raw"; value: String(root.result.rawWpm || 0) }
                Metric { label: "accuracy"; value: `${root.result.accuracy || 0}%` }
                Metric { label: "consistency"; value: `${root.result.consistency || 0}%` }
                Metric { label: "peak burst"; value: String(root.result.peakBurst || 0) }
                Metric { label: "characters"; value: `${root.result.correct || 0}/${root.result.incorrect || 0}/${root.result.extra || 0}/${root.result.missed || 0}` }
                Metric { label: "keypresses"; value: String(root.result.keypresses || 0) }
                Metric { label: "backspaces"; value: String(root.result.backspaces || 0) }
            }
            TypingResultGraph {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(190, Math.min(300, root.height * 0.38))
                samples: root.result.samples || []
                mainColor: root.theme.main
                rawColor: root.theme.sub
                burstColor: root.theme.caret
                errorColor: root.theme.error
                mutedColor: root.theme.sub
                showWpm: root.showWpm; showRaw: root.showRaw; showBurst: root.showBurst; showErrors: root.showErrors; showPb: root.showPb
                personalBest: root.result.comparablePb || 0
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                LegendButton { label: "wpm"; active: root.showWpm; onClicked: root.showWpm = !root.showWpm }
                LegendButton { label: "raw"; active: root.showRaw; onClicked: root.showRaw = !root.showRaw }
                LegendButton { label: "burst"; active: root.showBurst; onClicked: root.showBurst = !root.showBurst }
                LegendButton { label: "errors"; active: root.showErrors; onClicked: root.showErrors = !root.showErrors }
                LegendButton { label: "pb"; active: root.showPb; onClicked: root.showPb = !root.showPb }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: insightText.implicitHeight + 26
                color: root.theme.subAlt
                radius: 10
                StyledText { id: insightText; anchors.fill: parent; anchors.margins: 13; text: root.result.failed ? `Failed: ${root.result.failureReason || "configured threshold"}.` : `${root.result.newPb ? "New personal best. " : ""}${root.result.missedWords?.length || 0} missed words · ${root.result.slowWords?.length || 0} slow-word samples · weakest: ${(root.result.weakKeys || []).slice(0, 5).map(item => item.key).join(" ") || "none"}`; color: root.result.failed ? root.theme.error : root.theme.sub; wrapMode: Text.Wrap; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
            }
            Flow {
                Layout.fillWidth: true
                spacing: 8
                ActionButton { label: "repeat test"; glyph: "replay"; onClicked: root.repeatRequested() }
                ActionButton { label: "next test"; glyph: "skip_next"; primary: true; onClicked: root.nextRequested() }
                ActionButton { label: "practice missed"; glyph: "error"; onClicked: root.practiceRequested("missed") }
                ActionButton { label: "practice slow"; glyph: "speed"; onClicked: root.practiceRequested("slow") }
                ActionButton { label: "combined practice"; glyph: "fitness_center"; onClicked: root.practiceRequested("combined") }
                ActionButton { label: "copy summary"; glyph: "content_copy"; onClicked: root.copyRequested(root.summary()) }
                ActionButton { label: root.replayOpen ? "hide replay" : "replay"; glyph: "movie"; onClicked: root.replayOpen = !root.replayOpen }
                ActionButton { label: root.detailOpen ? "hide input" : "input history"; glyph: "history"; onClicked: root.detailOpen = !root.detailOpen }
            }
            TypingReplayView { visible: root.replayOpen; Layout.fillWidth: true; Layout.preferredHeight: 190; result: root.result; backgroundColor: root.theme.subAlt; textColor: root.theme.text; mutedColor: root.theme.sub; errorColor: root.theme.error }
            Rectangle {
                visible: root.detailOpen
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(260, inputHistory.implicitHeight + 30)
                color: root.theme.subAlt
                radius: 10
                Flickable {
                    anchors.fill: parent; anchors.margins: 14; clip: true; contentWidth: width; contentHeight: inputHistory.implicitHeight
                    StyledText { id: inputHistory; width: parent.width; textFormat: Text.RichText; text: root.inputHistoryHtml(); color: root.theme.text; wrapMode: Text.Wrap; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
                }
            }
        }
    }

    function inputHistoryHtml() {
        let output = "";
        for (const event of (result.events || [])) {
            if (event.type !== "insert") continue;
            const escaped = event.text === " " ? "·" : String(event.text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
            output += event.correct ? `<span style=\"color:${theme.text}\">${escaped}</span>` : `<span style=\"color:${theme.error};text-decoration:underline\">${escaped}</span>`;
        }
        return output || "No detailed event stream is available for this older result.";
    }

    component Metric: Rectangle {
        id: metric
        required property string label
        required property string value
        property bool prominent: false
        Layout.fillWidth: true
        Layout.preferredHeight: prominent ? 84 : 72
        color: "transparent"
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            StyledText { text: metric.value; color: metric.prominent ? root.theme.main : root.theme.text; font.pixelSize: metric.prominent ? 34 : 23; font.family: Appearance.font.family.monospace; Layout.alignment: Qt.AlignHCenter }
            StyledText { text: metric.label; color: root.theme.sub; font.pixelSize: 10; font.family: Appearance.font.family.monospace; Layout.alignment: Qt.AlignHCenter }
        }
    }
    component LegendButton: RippleButton { id: legend; required property string label; property bool active: false; implicitWidth: legendText.implicitWidth + 20; implicitHeight: 30; buttonRadius: 8; toggled: active; focusPolicy: Qt.NoFocus; contentItem: StyledText { id: legendText; text: legend.label; color: legend.active ? "#000000" : root.theme.sub; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace; font.pixelSize: 10 } }
    component ActionButton: RippleButton {
        id: action
        required property string label
        required property string glyph
        property bool primary: false
        implicitWidth: actionContent.implicitWidth + 22
        implicitHeight: 38
        buttonRadius: 9
        toggled: primary
        focusPolicy: Qt.NoFocus
        contentItem: RowLayout {
            id: actionContent
            spacing: 6
            MaterialSymbol { text: action.glyph; iconSize: 15; color: action.primary ? "#000000" : root.theme.sub }
            StyledText { text: action.label; color: action.primary ? "#000000" : root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
        }
    }
}
