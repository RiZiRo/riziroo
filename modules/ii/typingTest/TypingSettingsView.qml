pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property var settings
    required property var theme
    required property var catalog
    property string searchText: ""
    property string category: "Test"
    property var categories: ["Test", "Behavior", "Input", "Caret", "Appearance", "Theme", "Keyboard", "Results", "Data"]
    signal closeRequested
    signal restartRequested
    signal importPackRequested(string text)

    function matches(categoryName, terms) {
        if (root.category !== categoryName) return false;
        const query = root.searchText.trim().toLowerCase();
        return query.length === 0 || terms.toLowerCase().includes(query);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            StyledText { text: "typing settings"; color: root.theme.text; font.pixelSize: 23; font.family: Appearance.font.family.monospace }
            Item { Layout.fillWidth: true }
            RippleButton { implicitWidth: 38; implicitHeight: 38; buttonRadius: 10; focusPolicy: Qt.NoFocus; onClicked: root.closeRequested(); contentItem: MaterialSymbol { text: "close"; iconSize: 19; color: root.theme.sub; horizontalAlignment: Text.AlignHCenter } }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            radius: 10
            color: root.theme.subAlt
            TextField {
                anchors.fill: parent
                anchors.margins: 8
                text: root.searchText
                placeholderText: "Search settings"
                color: root.theme.text
                font.family: Appearance.font.family.monospace
                onTextChanged: root.searchText = text
            }
        }
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            contentWidth: categoryRow.implicitWidth
            interactive: contentWidth > width
            clip: true
            RowLayout {
                id: categoryRow
                spacing: 6
                Repeater {
                    model: root.categories
                    delegate: RippleButton {
                        required property string modelData
                        implicitWidth: categoryLabel.implicitWidth + 24
                        implicitHeight: 36
                        toggled: root.category === modelData
                        buttonRadius: 9
                        focusPolicy: Qt.NoFocus
                        onClicked: root.category = modelData
                        contentItem: StyledText { id: categoryLabel; text: modelData; color: root.category === modelData ? "#000000" : root.theme.sub; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
                    }
                }
            }
        }
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: settingsColumn
                width: parent.width
                spacing: 11

                ChoiceRow { visible: root.matches("Test", "mode time words quote zen custom"); title: "mode"; description: "Timed, fixed word count, quote, free typing, or custom text."; values: ["time", "words", "quote", "zen", "custom"]; current: root.settings.mode; onSelected: value => { root.settings.mode = value; root.restartRequested(); } }
                NumberRow { visible: root.matches("Test", "duration word count length arbitrary custom"); title: "test length"; description: "Any value from 1 to 10,000."; value: root.settings.testLength; minimum: 1; maximum: 10000; onChanged: value => { root.settings.testLength = value; root.restartRequested(); } }
                ChoiceRow { visible: root.matches("Test", "language english persian javascript python rust"); title: "language"; description: "Compact local language and code packs."; values: ["english", "english_1k", "english_5k", "persian", "code_javascript", "code_python", "code_rust"]; current: root.settings.language; onSelected: value => { root.settings.language = value; root.restartRequested(); } }
                ToggleRow { visible: root.matches("Test", "punctuation"); title: "punctuation"; description: "Add punctuation and sentence capitalization."; value: root.settings.punctuation; onToggled: { root.settings.punctuation = !root.settings.punctuation; root.restartRequested(); } }
                ToggleRow { visible: root.matches("Test", "numbers"); title: "numbers"; description: "Mix numeric tokens into generated tests."; value: root.settings.numbers; onToggled: { root.settings.numbers = !root.settings.numbers; root.restartRequested(); } }
                ChoiceRow { visible: root.matches("Test", "quote length short medium long extra long"); title: "quote length"; description: "Filter the offline quote collection."; values: ["all", "short", "medium", "long", "thicc"]; current: root.settings.quoteLength; onSelected: value => { root.settings.quoteLength = value; root.restartRequested(); } }
                TextRow { visible: root.matches("Test", "quote search source text"); title: "quote search"; description: "Search quote text and source locally."; value: root.settings.quoteSearch; onChanged: value => { root.settings.quoteSearch = value; root.restartRequested(); } }
                ChoiceRow { visible: root.matches("Test", "repeat quote same restart"); title: "repeat quote"; description: "Keep the same quote when restarting, or choose a new one."; values: ["off", "always"]; current: root.settings.repeatQuotes; onSelected: value => root.settings.repeatQuotes = value }
                TextRow { visible: root.matches("Test", "custom text paste own content"); title: "custom text"; description: "Text used by custom mode."; value: root.settings.customText; multiline: true; onChanged: value => { root.settings.customText = value; if (root.settings.mode === "custom") root.restartRequested(); } }

                ToggleRow { visible: root.matches("Behavior", "freedom free input"); title: "freedom mode"; description: "Allow input independent of target characters."; value: root.settings.freedomMode; onToggled: root.settings.freedomMode = !root.settings.freedomMode }
                ToggleRow { visible: root.matches("Behavior", "strict space"); title: "strict space"; description: "Block Space until the current word has the expected length."; value: root.settings.strictSpace; onToggled: root.settings.strictSpace = !root.settings.strictSpace }
                ChoiceRow { visible: root.matches("Behavior", "difficulty expert master fail"); title: "difficulty"; description: "Expert fails a word; master fails the first wrong letter."; values: ["normal", "expert", "master"]; current: root.settings.difficulty; onSelected: value => root.settings.difficulty = value }
                ChoiceRow { visible: root.matches("Behavior", "stop on error letter word"); title: "stop on error"; description: "Block wrong letters or leaving an incorrect word."; values: ["off", "letter", "word"]; current: root.settings.stopOnError; onSelected: value => { root.settings.stopOnError = value; if (value !== "off") root.settings.deleteOnError = "off"; } }
                ChoiceRow { visible: root.matches("Behavior", "delete on error hard word letter"); title: "delete on error"; description: "Delete a letter or word after a mistake."; values: ["off", "letter", "letter_hard", "word", "word_hard"]; current: root.settings.deleteOnError; onSelected: value => { root.settings.deleteOnError = value; if (value !== "off") root.settings.stopOnError = "off"; } }
                ChoiceRow { visible: root.matches("Behavior", "confidence backspace"); title: "confidence"; description: "Restrict deletion to the active word or disable it."; values: ["off", "on", "max"]; current: root.settings.confidenceMode; onSelected: value => root.settings.confidenceMode = value }
                ToggleRow { visible: root.matches("Behavior", "blind"); title: "blind mode"; description: "Hide incorrect-letter feedback during the run."; value: root.settings.blindMode; onToggled: root.settings.blindMode = !root.settings.blindMode }
                ToggleRow { visible: root.matches("Behavior", "quick end"); title: "quick end"; description: "Finish fixed tests without requiring a clean last word."; value: root.settings.quickEnd; onToggled: root.settings.quickEnd = !root.settings.quickEnd }
                ChoiceRow { visible: root.matches("Behavior", "trainer weakspot memory symbols binary hexadecimal ipv4 ipv6 backwards case"); title: "trainer"; description: "Useful offline transformations and weak-key practice."; values: ["off", "weakspot", "memory", "no_space", "capitals", "all_caps", "random_case", "ascii", "symbols", "binary", "hexadecimal", "ipv4", "ipv6", "backwards", "doubled", "underscore"]; current: root.settings.trainer; onSelected: value => { root.settings.trainer = value; root.restartRequested(); } }

                ChoiceRow { visible: root.matches("Input", "restart key tab enter escape"); title: "quick restart"; description: "Choose the test restart key."; values: ["tab", "enter", "escape"]; current: root.settings.quickRestart; onSelected: value => root.settings.quickRestart = value }
                ChoiceRow { visible: root.matches("Input", "typo display below replace both off"); title: "typo display"; description: "Choose how incorrect input is indicated."; values: ["off", "below", "replace", "both"]; current: root.settings.indicateTypos; onSelected: value => root.settings.indicateTypos = value }
                ToggleRow { visible: root.matches("Input", "extra letters hide"); title: "hide extra letters"; description: "Hide characters typed beyond the target word."; value: root.settings.hideExtraLetters; onToggled: root.settings.hideExtraLetters = !root.settings.hideExtraLetters }
                ChoiceRow { visible: root.matches("Input", "minimum wpm fail threshold"); title: "minimum WPM"; description: "Fail after the warmup if speed drops below the value."; values: ["off", "on"]; current: root.settings.minWpm; onSelected: value => root.settings.minWpm = value }
                NumberRow { visible: root.matches("Input", "minimum wpm value"); title: "minimum WPM value"; description: "Threshold used when minimum WPM is enabled."; value: root.settings.minWpmValue; minimum: 1; maximum: 1000; onChanged: value => root.settings.minWpmValue = value }
                ChoiceRow { visible: root.matches("Input", "minimum accuracy fail threshold"); title: "minimum accuracy"; description: "Fail if accuracy drops below the selected threshold."; values: ["off", "on"]; current: root.settings.minAcc; onSelected: value => root.settings.minAcc = value }
                NumberRow { visible: root.matches("Input", "minimum accuracy value"); title: "minimum accuracy value"; description: "Required accuracy percentage."; value: root.settings.minAccValue; minimum: 1; maximum: 100; onChanged: value => root.settings.minAccValue = value }
                ChoiceRow { visible: root.matches("Input", "minimum burst fail threshold"); title: "minimum burst"; description: "Fail low per-second typing bursts after warmup."; values: ["off", "on"]; current: root.settings.minBurst; onSelected: value => root.settings.minBurst = value }
                NumberRow { visible: root.matches("Input", "minimum burst value"); title: "minimum burst value"; description: "Required one-second burst WPM."; value: root.settings.minBurstValue; minimum: 1; maximum: 1000; onChanged: value => root.settings.minBurstValue = value }

                ChoiceRow { visible: root.matches("Caret", "caret line block outline underline off"); title: "caret style"; description: "Smooth line, block, outline, or thick underline."; values: ["off", "line", "block", "outline", "underline"]; current: root.settings.caretStyle; onSelected: value => root.settings.caretStyle = value }
                ChoiceRow { visible: root.matches("Caret", "smooth speed"); title: "smooth caret"; description: "Caret interpolation speed."; values: ["off", "fast", "medium", "slow"]; current: root.settings.smoothCaret; onSelected: value => root.settings.smoothCaret = value }
                ChoiceRow { visible: root.matches("Caret", "pace personal best previous recent custom"); title: "pace caret"; description: "Run a second caret at a target pace."; values: ["off", "pb", "previous", "recent", "custom"]; current: root.settings.paceCaret; onSelected: value => root.settings.paceCaret = value }
                NumberRow { visible: root.matches("Caret", "pace wpm custom"); title: "pace WPM"; description: "Custom pace target."; value: root.settings.paceCaretWpm; minimum: 1; maximum: 1000; onChanged: value => root.settings.paceCaretWpm = value }

                ChoiceRow { visible: root.matches("Appearance", "timer bar text mini off"); title: "timer"; description: "Hide it or display a bar, text, or mini counter."; values: ["off", "bar", "text", "mini"]; current: root.settings.timerStyle; onSelected: value => root.settings.timerStyle = value }
                ChoiceRow { visible: root.matches("Appearance", "live speed wpm"); title: "live speed"; description: "Live WPM display."; values: ["off", "text", "mini"]; current: root.settings.liveSpeedStyle; onSelected: value => root.settings.liveSpeedStyle = value }
                ChoiceRow { visible: root.matches("Appearance", "live accuracy"); title: "live accuracy"; description: "Live accuracy display."; values: ["off", "text", "mini"]; current: root.settings.liveAccStyle; onSelected: value => root.settings.liveAccStyle = value }
                ChoiceRow { visible: root.matches("Appearance", "live burst"); title: "live burst"; description: "Live short-window speed."; values: ["off", "text", "mini"]; current: root.settings.liveBurstStyle; onSelected: value => root.settings.liveBurstStyle = value }
                ChoiceRow { visible: root.matches("Appearance", "typed text keep hide fade dots"); title: "typed text"; description: "Keep, hide, fade, or dot typed characters."; values: ["keep", "hide", "fade", "dots"]; current: root.settings.typedEffect; onSelected: value => root.settings.typedEffect = value }
                ChoiceRow { visible: root.matches("Appearance", "read ahead"); title: "read ahead"; description: "Focus the current reading window."; values: ["off", "one", "two", "three"]; current: root.settings.readAhead; onSelected: value => root.settings.readAhead = value }
                ChoiceRow { visible: root.matches("Appearance", "tape letter word"); title: "tape mode"; description: "Center the next letter or word."; values: ["off", "letter", "word"]; current: root.settings.tapeMode; onSelected: value => root.settings.tapeMode = value }
                NumberRow { visible: root.matches("Appearance", "panel opacity glass tint"); title: "panel opacity"; description: "Pure black/glass tint from 55 to 100 percent."; value: Math.round(root.settings.panelOpacity * 100); minimum: 55; maximum: 100; onChanged: value => root.settings.panelOpacity = value / 100 }

                TypingThemeEditor { visible: root.category === "Theme"; Layout.fillWidth: true; Layout.preferredHeight: implicitHeight > 0 ? implicitHeight : 600; settings: root.settings; catalog: root.catalog }

                ChoiceRow { visible: root.matches("Keyboard", "keyboard static react next key off"); title: "keyboard mode"; description: "Static layout, pressed-key reaction, or next-key guidance."; values: ["off", "static", "react", "next"]; current: root.settings.keyboardMode; onSelected: value => root.settings.keyboardMode = value }
                NumberRow { visible: root.matches("Keyboard", "keyboard scale size"); title: "keyboard scale"; description: "Scale from 50 to 200 percent."; value: Math.round(root.settings.keyboardScale * 100); minimum: 50; maximum: 200; onChanged: value => root.settings.keyboardScale = value / 100 }
                ChoiceRow { visible: root.matches("Keyboard", "labels uppercase lowercase"); title: "labels"; description: "QWERTY key labels."; values: ["lowercase", "uppercase"]; current: root.settings.keyboardLabels; onSelected: value => root.settings.keyboardLabels = value }

                ToggleRow { visible: root.matches("Results", "save results local history"); title: "save results"; description: "Store completed tests locally."; value: root.settings.resultSaving; onToggled: root.settings.resultSaving = !root.settings.resultSaving }
                ToggleRow { visible: root.matches("Results", "caps lock warning"); title: "Caps Lock warning"; description: "Warn while Caps Lock is active."; value: root.settings.capsLockWarning; onToggled: root.settings.capsLockWarning = !root.settings.capsLockWarning }
                ToggleRow { visible: root.matches("Results", "focus loss warning"); title: "focus warning"; description: "Warn if typing focus leaves the input sink."; value: root.settings.focusWarning; onToggled: root.settings.focusWarning = !root.settings.focusWarning }

                TextRow { id: packJson; visible: root.matches("Data", "import json word quote pack"); title: "import local pack"; description: "Paste a word array, {words:[...]}, or {quotes:[{text,...}]}."; value: ""; multiline: true }
                RippleButton { visible: root.category === "Data"; Layout.alignment: Qt.AlignRight; implicitWidth: 150; implicitHeight: 40; toggled: true; buttonRadius: 9; focusPolicy: Qt.NoFocus; onClicked: root.importPackRequested(packJson.value); contentItem: StyledText { text: "import pack"; color: "#000000"; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace } }
            }
        }
    }

    component ChoiceRow: ColumnLayout {
        id: choice
        required property string title
        required property string description
        required property var values
        required property string current
        signal selected(string value)
        Layout.fillWidth: true
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            StyledText { text: choice.title; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
            Item { Layout.fillWidth: true }
            StyledText { text: choice.description; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10; Layout.maximumWidth: Math.min(430, root.width * 0.48); wrapMode: Text.Wrap; horizontalAlignment: Text.AlignRight }
        }
        Flow { Layout.fillWidth: true; spacing: 6; Repeater { model: choice.values; delegate: RippleButton { required property string modelData; implicitWidth: optionLabel.implicitWidth + 22; implicitHeight: 32; buttonRadius: 8; toggled: choice.current === modelData; focusPolicy: Qt.NoFocus; onClicked: choice.selected(modelData); contentItem: StyledText { id: optionLabel; text: String(modelData).replace(/_/g, " "); color: choice.current === modelData ? "#000000" : root.theme.sub; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace; font.pixelSize: 10 } } } }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme.subAlt }
    }

    component ToggleRow: RowLayout {
        id: toggle
        required property string title
        required property string description
        required property bool value
        signal toggled
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { text: toggle.title; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
            StyledText { text: toggle.description; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10; wrapMode: Text.Wrap }
        }
        RippleButton { implicitWidth: 52; implicitHeight: 30; buttonRadius: 15; toggled: toggle.value; focusPolicy: Qt.NoFocus; onClicked: toggle.toggled(); contentItem: MaterialSymbol { text: toggle.value ? "check" : "close"; iconSize: 16; color: toggle.value ? "#000000" : root.theme.sub; horizontalAlignment: Text.AlignHCenter } }
    }

    component NumberRow: RowLayout {
        id: number
        required property string title
        required property string description
        required property int value
        required property int minimum
        required property int maximum
        signal changed(int value)
        Layout.fillWidth: true
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { text: number.title; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
            StyledText { text: number.description; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
        }
        SpinBox { from: number.minimum; to: number.maximum; value: number.value; editable: true; focusPolicy: Qt.StrongFocus; onValueModified: number.changed(value) }
    }

    component TextRow: ColumnLayout {
        id: textRow
        required property string title
        required property string description
        property string value: ""
        property bool multiline: false
        signal changed(string value)
        Layout.fillWidth: true
        StyledText { text: textRow.title; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 14 }
        StyledText { text: textRow.description; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: textRow.multiline ? 120 : 40; radius: 8; color: root.theme.subAlt; StyledTextArea { anchors.fill: parent; anchors.margins: 8; text: textRow.value; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 11; wrapMode: TextEdit.Wrap; background: null; onTextChanged: { textRow.value = text; textRow.changed(text); } } }
    }
}
