pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

FocusScope {
    id: root

    signal closeRequested

    property alias panelItem: appPanel
    property alias settings: settingsModel
    property alias engine: typingEngine
    property alias resultStore: resultStorage
    property string page: "test"
    property var displayedResult: ({})
    property bool capsLockActive: false
    property bool openedOnce: false
    property bool restoringSettings: false
    property double requestedOpenAt: 0
    property int lastOpenLatencyMs: 0
    property int focusAttempts: 0
    property int focusLosses: 0
    property string transientMessage: ""

    readonly property bool overlayOpen: page === "settings" || page === "history"
    readonly property bool inputHasFocus: inputSink.activeFocus
    readonly property var theme: themeCatalog.active
    readonly property real panelMarginX: width < 1450 ? 34 : 94
    readonly property real panelMarginY: height < 850 ? 28 : 48

    TypingSettings { id: settingsModel }
    TypingThemeCatalog {
        id: themeCatalog
        themeName: settingsModel.themeName
        customTheme: settingsModel.customTheme
        onThemeNameChanged: if (settingsModel.themeName !== themeName) settingsModel.themeName = themeName
        onCustomThemeChanged: if (settingsModel.customTheme !== customTheme) settingsModel.customTheme = customTheme
    }
    TypingData { id: typingData }
    TypingEngine {
        id: typingEngine
        settings: settingsModel
        data: typingData
        panelActive: root.visible
        onFinished: result => root.handleFinished(result)
        onInputRejected: reason => root.showTransient(reason === "space" ? "finish the current word first" : reason.replace(/-/g, " "))
    }
    TypingResultStore { id: resultStorage }

    function settingChangesRequireRestart() {
        if (restoringSettings) return;
        restartDebounce.restart();
    }

    function syncThemeFromSettings() {
        themeCatalog.themeName = settingsModel.themeName;
        themeCatalog.customTheme = settingsModel.customTheme;
        if (settingsModel.customThemeJson.length > 0) {
            const imported = themeCatalog.importJson(settingsModel.customThemeJson);
            if (!imported.valid) {
                settingsModel.customTheme = false;
                themeCatalog.customTheme = false;
            }
        } else if (settingsModel.customTheme) {
            themeCatalog.resetCustomFromPreset();
        }
    }

    function focusTyping() {
        if (!root.visible || root.overlayOpen) return;
        focusAttempts++;
        inputSink.forceActiveFocus(Qt.ShortcutFocusReason);
        if (requestedOpenAt > 0 && lastOpenLatencyMs === 0)
            lastOpenLatencyMs = Math.max(0, Date.now() - requestedOpenAt);
    }

    function opened() {
        requestedOpenAt = Date.now();
        lastOpenLatencyMs = 0;
        engine.panelActive = true;
        if (!openedOnce) {
            openedOnce = true;
            syncThemeFromSettings();
            if (engine.targetText.length === 0) engine.restart();
        }
        Qt.callLater(focusTyping);
        focusRetry.restart();
    }

    function restartTest() {
        page = "test";
        displayedResult = ({});
        engine.practiceWords = [];
        engine.practiceKind = "";
        engine.restart();
        showTransient("new test");
        Qt.callLater(focusTyping);
    }

    function repeatTest() {
        page = "test";
        displayedResult = ({});
        engine.repeatTest();
        Qt.callLater(focusTyping);
    }

    function nextTest() {
        page = "test";
        displayedResult = ({});
        engine.practiceWords = [];
        engine.practiceKind = "";
        engine.restart();
        Qt.callLater(focusTyping);
    }

    function previewResult() {
        const diagnostic = Object.assign({
            wpm: 96, rawWpm: 108, accuracy: 97, consistency: 88, peakBurst: 124,
            correct: 242, incorrect: 5, extra: 1, missed: 2, keypresses: 253,
            backspaces: 6, mode: "words", length: 50, language: "english",
            durationMs: 31250, samples: [], events: [], words: [], missedWords: [], slowWords: [], weakKeys: []
        }, engine.latestResult || ({}));
        diagnostic.diagnostic = true;
        displayedResult = diagnostic;
        page = "result";
    }

    function diagnosticStatus() {
        return JSON.stringify({
            visible: root.visible,
            page: root.page,
            phase: root.engine.phase,
            typedLength: root.engine.typedLength,
            currentWord: root.engine.currentTypedWord(),
            backspaces: root.engine.backspaceCount,
            focus: root.inputHasFocus,
            openLatencyMs: root.lastOpenLatencyMs,
            activeDelegates: root.page === "test" ? testView.activeDelegateCount : 0,
            viewportStartWord: root.page === "test" ? testView.windowStartWord : -1,
            viewportEndWord: root.page === "test" ? testView.windowEndWord : -1,
            viewportLine: root.page === "test" ? testView.logicalCurrentLine : -1,
            viewportY: root.page === "test" ? Math.round(testView.targetContentY) : -1,
            viewportRebuilds: root.page === "test" ? testView.viewportRebuilds : 0,
            viewportTransitions: root.page === "test" ? testView.viewportTransitions : 0,
            viewportReason: root.page === "test" ? testView.lastRebuildReason : "inactive",
            clockRunning: root.engine.clockTimer.running,
            analyticsRunning: root.engine.analyticsTimer.running,
            historyLoaded: root.resultStore.loaded,
            settingsWrites: root.settings.writeCount,
            historyWrites: root.resultStore.writeCount
        });
    }

    function handleFinished(result) {
        let complete = result;
        if (settingsModel.resultSaving) complete = resultStorage.addResult(result);
        else complete = Object.assign({}, result, {comparablePb: resultStorage.bestFor(result), newPb: false, pbDelta: 0});
        const recent = resultStorage.summaries.slice(0, 10);
        if (recent.length > 0)
            complete.recentAverageWpm = Math.round(recent.reduce((sum, item) => sum + Number(item.wpm || 0), 0) / recent.length);
        engine.latestResult = complete;
        displayedResult = complete;
        page = "result";
    }

    function showTransient(message) {
        transientMessage = message;
        transientTimer.restart();
    }

    function openSettings() {
        page = "settings";
        inputSink.focus = false;
    }

    function openHistory() {
        page = "history";
        inputSink.focus = false;
    }

    function closeOverlay() {
        page = engine.phase === "finished" ? "result" : "test";
        Qt.callLater(focusTyping);
    }

    function openStoredResult(id) {
        const detail = resultStorage.select(id);
        if (detail && detail.id) {
            displayedResult = detail;
            page = "result";
        }
    }

    function practice(kind) {
        page = "test";
        engine.startPractice(kind, displayedResult);
        Qt.callLater(focusTyping);
    }

    function handleKey(event) {
        const ctrl = Boolean(event.modifiers & Qt.ControlModifier);
        const alt = Boolean(event.modifiers & Qt.AltModifier);
        const meta = Boolean(event.modifiers & Qt.MetaModifier);

        if (event.key === Qt.Key_CapsLock) capsLockActive = !capsLockActive;
        if (event.key === Qt.Key_Escape && root.overlayOpen) {
            closeOverlay();
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Escape && settingsModel.quickRestart !== "escape") {
            closeRequested();
            event.accepted = true;
            return;
        }
        const restart = (settingsModel.quickRestart === "tab" && event.key === Qt.Key_Tab)
            || (settingsModel.quickRestart === "enter" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter))
            || (settingsModel.quickRestart === "escape" && event.key === Qt.Key_Escape);
        if (restart && !root.overlayOpen) {
            restartTest();
            event.accepted = true;
            return;
        }
        if (root.overlayOpen) return;
        if (engine.phase === "finished") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) nextTest();
            event.accepted = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            return;
        }
        if (event.key === Qt.Key_Backspace) {
            if (ctrl) engine.eraseWord(event.modifiers, false);
            else engine.eraseCharacter(event.modifiers, false);
            event.accepted = true;
            return;
        }
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && settingsModel.mode === "zen") {
            engine.acceptText("\n", event.modifiers);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Space) {
            engine.acceptText(" ", event.modifiers);
            event.accepted = true;
            return;
        }
        if (!ctrl && !alt && !meta && event.text && event.text.length > 0) {
            engine.acceptComposition(event.text, event.modifiers);
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        restoringSettings = true;
        syncThemeFromSettings();
        if (typingEngine.targetText.length === 0) typingEngine.restart();
        restoringSettings = false;
        if (visible) opened();
    }
    onVisibleChanged: {
        engine.panelActive = visible;
        if (visible) opened();
        else inputSink.focus = false;
    }

    Connections {
        target: settingsModel
        function onThemeNameChanged(): void { root.syncThemeFromSettings(); }
        function onCustomThemeChanged(): void { root.syncThemeFromSettings(); }
        function onCustomThemeJsonChanged(): void { root.syncThemeFromSettings(); }
        function onTestLengthChanged(): void { root.settingChangesRequireRestart(); }
        function onPunctuationChanged(): void { root.settingChangesRequireRestart(); }
        function onNumbersChanged(): void { root.settingChangesRequireRestart(); }
        function onLanguageChanged(): void { root.settingChangesRequireRestart(); }
        function onCustomTextChanged(): void { root.settingChangesRequireRestart(); }
        function onQuoteLengthChanged(): void { root.settingChangesRequireRestart(); }
        function onQuoteSearchChanged(): void { root.settingChangesRequireRestart(); }
        function onTrainerChanged(): void { root.settingChangesRequireRestart(); }
    }

    TextInput {
        id: inputSink
        width: 2
        height: 2
        x: -100
        y: -100
        opacity: 0
        visible: root.visible
        activeFocusOnTab: false
        focus: root.visible && !root.overlayOpen
        inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
        Keys.onPressed: event => root.handleKey(event)
        onAccepted: {
            if (root.settings.mode === "zen") root.engine.acceptComposition("\n", 0);
            text = "";
        }
        onTextEdited: {
            if (text.length > 0) {
                root.engine.acceptComposition(text, 0);
                text = "";
            }
        }
        onActiveFocusChanged: {
            if (!activeFocus && root.visible && !root.overlayOpen) {
                root.focusLosses++;
                focusRestore.restart();
            }
        }
    }

    Timer { id: focusRetry; interval: 45; repeat: false; onTriggered: root.focusTyping() }
    Timer { id: focusRestore; interval: 80; repeat: false; onTriggered: root.focusTyping() }
    Timer { id: transientTimer; interval: 1400; repeat: false; onTriggered: root.transientMessage = "" }
    Timer { id: restartDebounce; interval: 80; repeat: false; onTriggered: if (root.visible) root.nextTest() }

    Rectangle {
        id: appPanel
        anchors.centerIn: parent
        width: Math.min(1560, Math.max(0, parent.width - root.panelMarginX * 2))
        height: Math.min(940, Math.max(0, parent.height - root.panelMarginY * 2))
        radius: Math.max(20, Appearance.rounding.windowRounding)
        color: Qt.alpha(root.theme.bg, root.settings.panelOpacity)
        clip: true

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.theme.sub, 0.28)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.width < 1500 ? 30 : 44
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                spacing: 8

                RowLayout {
                    spacing: 5
                    ModeButton { label: "time"; value: "time" }
                    ModeButton { label: "words"; value: "words" }
                    ModeButton { visible: root.width > 1050; label: "quote"; value: "quote" }
                    ModeButton { visible: root.width > 1250; label: "zen"; value: "zen" }
                }
                StyledText { visible: root.width > 950; text: `${root.settings.language.replace(/_/g, " ")} · ${root.settings.testLength}`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
                IconButton { glyph: "restart_alt"; tip: "restart"; onActivated: root.restartTest() }
                IconButton { glyph: "history"; tip: "history"; onActivated: root.openHistory() }
                IconButton { glyph: "tune"; tip: "settings"; onActivated: root.openSettings() }
                IconButton { glyph: "close"; tip: "close"; onActivated: root.closeRequested() }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                TypingTestView {
                    id: testView
                    anchors.fill: parent
                    visible: root.page === "test"
                    engine: root.engine
                    settings: root.settings
                    theme: root.theme
                }

                Loader {
                    anchors.fill: parent
                    active: root.page === "result"
                    sourceComponent: TypingResultsView {
                        result: root.displayedResult
                        theme: root.theme
                        onRepeatRequested: root.repeatTest()
                        onNextRequested: root.nextTest()
                        onPracticeRequested: kind => root.practice(kind)
                        onCopyRequested: text => { Quickshell.clipboardText = text; root.showTransient("summary copied"); }
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: root.page === "settings"
                    sourceComponent: TypingSettingsView {
                        settings: root.settings
                        theme: root.theme
                        catalog: themeCatalog
                        onCloseRequested: root.closeOverlay()
                        onRestartRequested: root.nextTest()
                        onImportPackRequested: text => {
                            const result = root.engine.importPack(text);
                            root.showTransient(result.valid ? "pack imported" : result.message);
                        }
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: root.page === "history"
                    sourceComponent: TypingHistoryView {
                        store: root.resultStore
                        theme: root.theme
                        onCloseRequested: root.closeOverlay()
                        onResultRequested: id => root.openStoredResult(id)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                visible: root.settings.showKeyTips && root.page === "test"
                Item { Layout.fillWidth: true }
                StyledText { text: `${root.settings.quickRestart} restart`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                StyledText { text: "·"; color: root.theme.sub; font.pixelSize: 10 }
                StyledText { text: "ctrl backspace word"; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
            }
        }

        Rectangle {
            visible: root.settings.capsLockWarning && root.capsLockActive
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 18
            width: capsText.implicitWidth + 26
            height: 34
            radius: 10
            color: root.theme.error
            StyledText { id: capsText; anchors.centerIn: parent; text: "caps lock"; color: root.theme.bg; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
        }

        Rectangle {
            visible: root.transientMessage.length > 0
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: 20
            width: transientText.implicitWidth + 28
            height: 34
            radius: 10
            color: Qt.alpha(root.theme.subAlt, 0.96)
            StyledText { id: transientText; anchors.centerIn: parent; text: root.transientMessage; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
        }
    }

    component ModeButton: RippleButton {
        id: modeButton
        required property string label
        required property string value
        implicitWidth: 76
        implicitHeight: 34
        toggled: root.settings.mode === value
        buttonRadius: 9
        focusPolicy: Qt.NoFocus
        onClicked: { root.settings.mode = value; root.nextTest(); }
        contentItem: StyledText { text: modeButton.label; color: modeButton.toggled ? root.theme.bg : root.theme.sub; horizontalAlignment: Text.AlignHCenter; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
    }

    component IconButton: RippleButton {
        id: iconButton
        required property string glyph
        property string tip: ""
        signal activated
        implicitWidth: 38
        implicitHeight: 36
        buttonRadius: 10
        focusPolicy: Qt.NoFocus
        colBackground: "transparent"
        colBackgroundHover: root.theme.subAlt
        onClicked: activated()
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.text: tip
        contentItem: MaterialSymbol { text: iconButton.glyph; iconSize: 18; color: root.theme.sub; horizontalAlignment: Text.AlignHCenter }
    }
}
