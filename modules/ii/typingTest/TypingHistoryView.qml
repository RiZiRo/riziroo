pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var store
    required property var theme
    property string modeFilter: "all"
    property string languageFilter: "all"
    property string difficultyFilter: "all"
    property bool savedOnly: false
    property string statusFilter: "all"
    property string optionFilter: "all"
    property int recentDays: 0
    property var filtered: []
    signal closeRequested
    signal resultRequested(string id)

    function refresh() {
        filtered = store.filter({
            mode: modeFilter,
            language: languageFilter,
            difficulty: difficultyFilter,
            saved: savedOnly ? true : undefined,
            failed: statusFilter === "failed" ? true : (statusFilter === "passed" ? false : undefined),
            pb: statusFilter === "pb" ? true : undefined,
            punctuation: optionFilter === "punctuation" ? true : undefined,
            numbers: optionFilter === "numbers" ? true : undefined,
            since: recentDays > 0 ? Date.now() - recentDays * 86400000 : undefined
        });
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 13
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 1
                StyledText { text: "local history"; color: root.theme.text; font.pixelSize: 23; font.family: Appearance.font.family.monospace }
                StyledText { text: `${root.store.summaries.length} tests · ${(root.store.aggregates().timeTypedMs / 60000).toFixed(1)} minutes`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
            }
            Item { Layout.fillWidth: true }
            RippleButton { implicitWidth: 38; implicitHeight: 38; buttonRadius: 10; focusPolicy: Qt.NoFocus; onClicked: root.closeRequested(); contentItem: MaterialSymbol { text: "close"; iconSize: 19; color: root.theme.sub; horizontalAlignment: Text.AlignHCenter } }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            FilterButton { label: "all modes"; active: root.modeFilter === "all"; onClicked: { root.modeFilter = "all"; root.refresh(); } }
            Repeater { model: ["time", "words", "quote", "zen", "custom"]; delegate: FilterButton { required property string modelData; label: modelData; active: root.modeFilter === modelData; onClicked: { root.modeFilter = modelData; root.refresh(); } } }
            FilterButton { label: "saved"; active: root.savedOnly; onClicked: { root.savedOnly = !root.savedOnly; root.refresh(); } }
            FilterButton { label: "passed"; active: root.statusFilter === "passed"; onClicked: { root.statusFilter = root.statusFilter === "passed" ? "all" : "passed"; root.refresh(); } }
            FilterButton { label: "failed"; active: root.statusFilter === "failed"; onClicked: { root.statusFilter = root.statusFilter === "failed" ? "all" : "failed"; root.refresh(); } }
            FilterButton { label: "PB"; active: root.statusFilter === "pb"; onClicked: { root.statusFilter = root.statusFilter === "pb" ? "all" : "pb"; root.refresh(); } }
            FilterButton { label: "punctuation"; active: root.optionFilter === "punctuation"; onClicked: { root.optionFilter = root.optionFilter === "punctuation" ? "all" : "punctuation"; root.refresh(); } }
            FilterButton { label: "numbers"; active: root.optionFilter === "numbers"; onClicked: { root.optionFilter = root.optionFilter === "numbers" ? "all" : "numbers"; root.refresh(); } }
            FilterButton { label: "7 days"; active: root.recentDays === 7; onClicked: { root.recentDays = root.recentDays === 7 ? 0 : 7; root.refresh(); } }
            FilterButton { label: "30 days"; active: root.recentDays === 30; onClicked: { root.recentDays = root.recentDays === 30 ? 0 : 30; root.refresh(); } }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.subAlt }
        GridLayout {
            Layout.fillWidth: true
            columns: width < 720 ? 2 : 4
            columnSpacing: 8
            rowSpacing: 8
            Metric { label: "tests"; value: String(root.store.aggregates().tests) }
            Metric { label: "average wpm"; value: String(root.store.aggregates().averageWpm) }
            Metric { label: "average accuracy"; value: `${root.store.aggregates().averageAccuracy}%` }
            Metric { label: "weakest keys"; value: root.store.aggregates().weakKeys.slice(0, 5).map(item => item.key).join("  ") || "—" }
        }
        StyledText { visible: root.filtered.length === 0; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 60; text: "No results match these filters."; color: root.theme.sub; font.family: Appearance.font.family.monospace }
        ListView {
            visible: root.filtered.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.filtered
            delegate: RippleButton {
                id: resultRow
                required property var modelData
                required property int index
                width: ListView.view.width
                height: 58
                buttonRadius: 9
                colBackground: index % 2 === 0 ? root.theme.subAlt : "transparent"
                colBackgroundHover: Qt.lighter(root.theme.subAlt, 1.25)
                focusPolicy: Qt.NoFocus
                onClicked: root.resultRequested(modelData.id)
                contentItem: RowLayout {
                    spacing: 12
                    StyledText { text: String(modelData.wpm); color: root.theme.text; font.pixelSize: 20; font.family: Appearance.font.family.monospace; Layout.preferredWidth: 44 }
                    StyledText { text: "wpm"; color: root.theme.sub; font.pixelSize: 10; font.family: Appearance.font.family.monospace }
                    StyledText { text: `${modelData.accuracy}%`; color: modelData.accuracy < 90 ? root.theme.error : root.theme.sub; font.family: Appearance.font.family.monospace; Layout.preferredWidth: 48 }
                    StyledText { text: `${modelData.mode} ${modelData.length}`; color: root.theme.sub; font.family: Appearance.font.family.monospace; Layout.preferredWidth: 90 }
                    StyledText { text: modelData.language; color: root.theme.sub; font.family: Appearance.font.family.monospace; Layout.preferredWidth: 110 }
                    Item { Layout.fillWidth: true }
                    MaterialSymbol { visible: modelData.pb; text: "workspace_premium"; iconSize: 15; color: root.theme.main }
                    MaterialSymbol { visible: modelData.failed; text: "warning"; iconSize: 15; color: root.theme.error }
                    StyledText { text: new Date(modelData.timestamp).toLocaleString(); color: root.theme.sub; font.pixelSize: 10; font.family: Appearance.font.family.monospace }
                    RippleButton { implicitWidth: 32; implicitHeight: 30; buttonRadius: 8; focusPolicy: Qt.NoFocus; onClicked: mouse => { root.store.toggleSaved(modelData.id); mouse.accepted = true; root.refresh(); } contentItem: MaterialSymbol { text: modelData.saved ? "bookmark" : "bookmark_border"; iconSize: 16; color: modelData.saved ? root.theme.main : root.theme.sub; horizontalAlignment: Text.AlignHCenter } }
                }
            }
        }
    }

    Connections { target: root.store; function onSummariesChanged(): void { root.refresh(); } }
    Component.onCompleted: refresh()

    component FilterButton: RippleButton {
        id: filterButton
        required property string label
        property bool active: false
        implicitWidth: filterText.implicitWidth + 22
        implicitHeight: 32
        toggled: active
        buttonRadius: 8
        focusPolicy: Qt.NoFocus
        contentItem: StyledText { id: filterText; text: filterButton.label; color: filterButton.active ? "#000000" : root.theme.sub; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
    }
    component Metric: Rectangle {
        id: metric
        required property string label
        required property string value
        Layout.fillWidth: true
        Layout.preferredHeight: 62
        color: root.theme.subAlt
        radius: 9
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            StyledText { text: metric.value; color: root.theme.text; font.pixelSize: 17; font.family: Appearance.font.family.monospace; Layout.alignment: Qt.AlignHCenter }
            StyledText { text: metric.label; color: root.theme.sub; font.pixelSize: 9; font.family: Appearance.font.family.monospace; Layout.alignment: Qt.AlignHCenter }
        }
    }
}
