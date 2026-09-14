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

    readonly property bool overlayOpen: page === "settings" || page === "history" || page === "language"
    readonly property bool inputHasFocus: inputSink.activeFocus
    readonly property var theme: themeCatalog.active

    // Floating panel geometry. The panel is the only part of the layer surface
    // that paints or takes input, so these bounds are also the window's mask.
    readonly property real minPanelWidth: 720
    // The on-screen keyboard needs roughly 190px of its own, so the floor moves
    // with it rather than letting the board be squeezed into nothing.
    readonly property real minPanelHeight: settingsModel.keyboardMode === "off" ? 420 : 540
    property real panelWidth: Math.max(minPanelWidth, Math.min(width, settingsModel.panelWidth))
    property real panelHeight: Math.max(minPanelHeight, Math.min(height, settingsModel.panelHeight))
    property bool panelPlaced: false

    function clampPanel() {
        if (width <= 0 || height <= 0) return;
        appPanel.x = Math.max(0, Math.min(width - appPanel.width, appPanel.x));
        appPanel.y = Math.max(0, Math.min(height - appPanel.height, appPanel.y));
    }

    function centerPanel() {
        appPanel.x = Math.max(0, (width - appPanel.width) / 2);
        appPanel.y = Math.max(0, (height - appPanel.height) / 2);
        panelPlaced = true;
        persistGeometry();
    }

    // Restores the remembered position, or centers on the first ever open.
    function placePanel() {
        if (width <= 0 || height <= 0) return;
        if (settingsModel.panelX < 0 || settingsModel.panelY < 0) {
            centerPanel();
            return;
        }
        appPanel.x = settingsModel.panelX;
        appPanel.y = settingsModel.panelY;
        clampPanel();
        panelPlaced = true;
    }

    function persistGeometry() {
        settingsModel.panelX = Math.round(appPanel.x);
        settingsModel.panelY = Math.round(appPanel.y);
    }

    // Writes through to the settings model so panelWidth/panelHeight stay plain
    // bindings; TypingSettings debounces the disk write until the drag stops.
    function resizePanel(newWidth, newHeight) {
        settingsModel.panelWidth = Math.max(root.minPanelWidth, Math.min(root.width - appPanel.x, Math.round(newWidth)));
        settingsModel.panelHeight = Math.max(root.minPanelHeight, Math.min(root.height - appPanel.y, Math.round(newHeight)));
    }

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
        if (!root.visible || root.overlayOpen || customLengthPrompt.open) return;
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

    function openLanguage() {
        page = "language";
        inputSink.focus = false;
    }

    function pickLanguage(key) {
        settingsModel.language = key;
        closeOverlay();
        showTransient(typingData.labelFor(key));
    }

    function toggleKeyboard() {
        settingsModel.keyboardMode = settingsModel.keyboardMode === "off" ? "react" : "off";
        showTransient(settingsModel.keyboardMode === "off" ? "keyboard hidden" : "keyboard shown");
        Qt.callLater(focusTyping);
    }

    function promptCustomLength() {
        customLengthField.text = String(settingsModel.testLength);
        customLengthPrompt.open = true;
        inputSink.focus = false;
        Qt.callLater(() => customLengthField.forceActiveFocus());
    }

    function applyCustomLength() {
        const value = Math.max(1, Math.min(10000, Math.round(Number(customLengthField.text) || settingsModel.testLength)));
        customLengthPrompt.open = false;
        settingsModel.testLength = value;
        nextTest();
    }

    function closeOverlay() {
        customLengthPrompt.open = false;
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
        if (event.key === Qt.Key_Escape && customLengthPrompt.open) {
            customLengthPrompt.open = false;
            Qt.callLater(focusTyping);
            event.accepted = true;
            return;
        }
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
        placePanel();
        if (visible) opened();
    }
    onVisibleChanged: {
        engine.panelActive = visible;
        if (visible) {
            if (!panelPlaced) placePanel();
            else clampPanel();
            opened();
        } else {
            inputSink.focus = false;
        }
    }
    // The surface fills the layer window, so these fire when the monitor changes.
    onWidthChanged: panelPlaced ? clampPanel() : placePanel()
    onHeightChanged: panelPlaced ? clampPanel() : placePanel()

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
        focus: root.visible && !root.overlayOpen && !customLengthPrompt.open
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
            if (!activeFocus && root.visible && !root.overlayOpen && !customLengthPrompt.open) {
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
        width: root.panelWidth
        height: root.panelHeight
        radius: Math.max(20, Appearance.rounding.windowRounding)
        color: Qt.alpha(root.theme.bg, root.settings.panelOpacity)
        clip: true

        HoverHandler { id: panelHover }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.theme.sub, 0.28)
            z: 10
        }

        // Grab strip. Layer-shell surfaces cannot be moved by the compositor, so
        // the panel moves itself inside the (transparent) full-screen surface.
        Item {
            id: dragStrip
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 30
            z: 6

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                drag.target: appPanel
                drag.axis: Drag.XAndYAxis
                drag.minimumX: 0
                drag.minimumY: 0
                drag.maximumX: Math.max(0, root.width - appPanel.width)
                drag.maximumY: Math.max(0, root.height - appPanel.height)
                onReleased: {
                    root.clampPanel();
                    root.persistGeometry();
                }
                onDoubleClicked: root.centerPanel()
            }

            MaterialSymbol {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                text: "drag_indicator"
                iconSize: 16
                color: Qt.alpha(root.theme.sub, panelHover.hovered ? 0.9 : 0.35)
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            RowLayout {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                IconButton {
                    glyph: "keyboard"
                    tip: root.settings.keyboardMode === "off" ? "show keyboard" : "hide keyboard"
                    highlight: root.settings.keyboardMode !== "off"
                    onActivated: root.toggleKeyboard()
                }
                IconButton { glyph: "restart_alt"; tip: "restart (tab)"; onActivated: root.restartTest() }
                IconButton { glyph: "history"; tip: "history"; highlight: root.page === "history"; onActivated: root.page === "history" ? root.closeOverlay() : root.openHistory() }
                IconButton { glyph: "tune"; tip: "settings"; highlight: root.page === "settings"; onActivated: root.page === "settings" ? root.closeOverlay() : root.openSettings() }
                IconButton { glyph: "close"; tip: "close (esc)"; onActivated: root.closeRequested() }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: dragStrip.height
            anchors.leftMargin: 26
            anchors.rightMargin: 26
            anchors.bottomMargin: 12
            spacing: 0

            TypingConfigBar {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                Layout.topMargin: 6
                visible: root.page === "test" || root.page === "language"
                settings: root.settings
                theme: root.theme
                onRestartRequested: root.nextTest()
                onSettingsRequested: root.openSettings()
                onCustomLengthRequested: root.promptCustomLength()
            }

            // The globe line Monkeytype puts directly above the words.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                Layout.topMargin: 14
                visible: root.page === "test" || root.page === "language"

                Rectangle {
                    anchors.centerIn: parent
                    width: languageRow.implicitWidth + 20
                    height: 26
                    radius: Appearance.rounding.full
                    color: languageArea.containsMouse ? Qt.alpha(root.theme.text, 0.07) : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }

                    RowLayout {
                        id: languageRow
                        anchors.centerIn: parent
                        spacing: 7

                        MaterialSymbol {
                            text: "language"
                            iconSize: 15
                            color: languageArea.containsMouse ? root.theme.text : root.theme.sub
                        }
                        StyledText {
                            text: typingData.labelFor(root.settings.language)
                            color: languageArea.containsMouse ? root.theme.text : root.theme.sub
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 13
                        }
                        StyledText {
                            visible: root.settings.mode === "quote" && root.engine.quoteSource.length > 0
                            text: `· ${root.engine.quoteSource}`
                            color: root.theme.sub
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: languageArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openLanguage()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: root.page === "test" ? 6 : 14

                TypingTestView {
                    id: testView
                    anchors.fill: parent
                    visible: root.page === "test" || root.page === "language"
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
                        typingData: typingData
                        onCloseRequested: root.closeOverlay()
                        onRestartRequested: root.nextTest()
                        onResetPanelRequested: root.centerPanel()
                        onReloadPacksRequested: {
                            typingData.refreshUserPacks();
                            root.showTransient("language packs reloaded");
                        }
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
                Layout.preferredHeight: 20
                Layout.topMargin: 6
                visible: root.settings.showKeyTips && root.page === "test"
                Item { Layout.fillWidth: true }
                StyledText { text: `${root.settings.quickRestart} restart`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                StyledText { text: "·"; color: root.theme.sub; font.pixelSize: 10 }
                StyledText { text: "ctrl backspace word"; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                StyledText { text: "·"; color: root.theme.sub; font.pixelSize: 10 }
                StyledText { text: "esc close"; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
                Item { Layout.fillWidth: true }
            }
        }

        Loader {
            anchors.fill: parent
            anchors.topMargin: dragStrip.height
            z: 8
            active: root.page === "language"
            sourceComponent: TypingLanguagePicker {
                typingData: typingData
                settings: root.settings
                theme: root.theme
                onCloseRequested: root.closeOverlay()
                onPicked: key => root.pickLanguage(key)
            }
        }

        Rectangle {
            id: customLengthPrompt
            property bool open: false
            visible: open
            anchors.centerIn: parent
            width: 260
            height: 128
            radius: Appearance.rounding.large
            color: root.theme.bg
            border.width: 1
            border.color: Qt.alpha(root.theme.sub, 0.4)
            z: 9

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                StyledText {
                    text: root.settings.mode === "time" ? "seconds" : "word count"
                    color: root.theme.text
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 13
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: Appearance.rounding.small
                    color: root.theme.subAlt

                    TextInput {
                        id: customLengthField
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: root.theme.text
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: 14
                        selectByMouse: true
                        validator: IntValidator { bottom: 1; top: 10000 }
                        onAccepted: root.applyCustomLength()
                        Keys.onEscapePressed: {
                            customLengthPrompt.open = false;
                            Qt.callLater(root.focusTyping);
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "1 to 10000 · enter to apply"
                    color: root.theme.sub
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: 10
                }
            }
        }

        ResizeHandler {
            anchorItem: appPanel
            hoverActive: panelHover.hovered
            currentWidth: appPanel.width
            currentHeight: appPanel.height
            resizeMode: "free"
            // Keep the grip inside the panel: the window mask follows the panel
            // rect, so anything hanging outside it would not receive clicks.
            anchors.rightMargin: 0
            anchors.bottomMargin: 0
            onResizedFree: (newWidth, newHeight) => root.resizePanel(newWidth, newHeight)
            onResizeFinished: root.persistGeometry()
        }

        Rectangle {
            visible: root.settings.capsLockWarning && root.capsLockActive
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 38
            width: capsText.implicitWidth + 26
            height: 30
            radius: 10
            z: 7
            color: root.theme.error
            StyledText { id: capsText; anchors.centerIn: parent; text: "caps lock"; color: root.theme.bg; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
        }

        Rectangle {
            visible: root.transientMessage.length > 0
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            // Clears the key-hint row at the bottom of the panel.
            anchors.bottomMargin: 48
            width: transientText.implicitWidth + 28
            height: 30
            radius: 10
            z: 7
            color: Qt.alpha(root.theme.subAlt, 0.96)
            StyledText { id: transientText; anchors.centerIn: parent; text: root.transientMessage; color: root.theme.text; font.family: Appearance.font.family.monospace; font.pixelSize: 10 }
        }
    }

    component IconButton: RippleButton {
        id: iconButton
        required property string glyph
        property string tip: ""
        property bool highlight: false
        signal activated
        implicitWidth: 34
        implicitHeight: 30
        buttonRadius: 9
        focusPolicy: Qt.NoFocus
        colBackground: "transparent"
        colBackgroundHover: Qt.alpha(root.theme.text, 0.08)
        onClicked: activated()
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.text: tip
        contentItem: MaterialSymbol {
            text: iconButton.glyph
            iconSize: 17
            horizontalAlignment: Text.AlignHCenter
            color: iconButton.highlight ? root.theme.main : (iconButton.hovered ? root.theme.text : root.theme.sub)
            Behavior on color { ColorAnimation { duration: 130 } }
        }
    }
}
