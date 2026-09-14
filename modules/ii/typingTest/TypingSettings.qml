pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick

QtObject {
    id: root

    property int schemaVersion: 5
    property bool restoring: true
    property int writeCount: 0

    property string mode: "words"
    property int testLength: 100
    property bool punctuation: false
    property bool numbers: false
    property string language: "english"
    property string customText: ""
    property string quoteLength: "all"
    property string quoteSearch: ""
    property string difficulty: "normal"
    property string quickRestart: "tab"
    property string repeatQuotes: "off"
    property bool resultSaving: true
    property bool freedomMode: false
    property bool strictSpace: false
    property string stopOnError: "off"
    property string deleteOnError: "off"
    property string confidenceMode: "off"
    property bool blindMode: false
    property bool quickEnd: false
    property string indicateTypos: "below"
    property bool hideExtraLetters: false
    property string minWpm: "off"
    property int minWpmValue: 100
    property string minAcc: "off"
    property int minAccValue: 90
    property string minBurst: "off"
    property int minBurstValue: 100
    property string timerStyle: "mini"
    property string liveSpeedStyle: "off"
    property string liveAccStyle: "off"
    property string liveBurstStyle: "off"
    property string caretStyle: "underline"
    property string smoothCaret: "medium"
    property string paceCaret: "off"
    property int paceCaretWpm: 100
    property string paceCaretStyle: "line"
    property string keyboardMode: "react"
    property real keyboardScale: 1
    property string keyboardLabels: "lowercase"
    property string typedEffect: "keep"
    property string readAhead: "off"
    property string tapeMode: "off"
    property string trainer: "off"
    property string themeName: "pure_black"
    property bool customTheme: false
    property string customThemeJson: ""
    property real panelOpacity: 0.96
    property bool showKeyTips: true
    property bool capsLockWarning: true
    property bool focusWarning: true
    property real panelX: -1
    property real panelY: -1
    property real panelWidth: 1040
    property real panelHeight: 700
    property bool followShellColors: false
    property bool closeOnClickOutside: false
    property real fontScale: 1

    signal settingsWritten

    function enumValue(value, allowed, fallback) {
        return allowed.indexOf(value) >= 0 ? value : fallback;
    }

    function numberValue(value, fallback, minimum, maximum) {
        const number = Number(value);
        return isFinite(number) ? Math.max(minimum, Math.min(maximum, number)) : fallback;
    }

    function migrate(saved) {
        if (!saved) return;
        const version = Number(saved.schemaVersion || 0);
        mode = enumValue(saved.mode, ["time", "words", "quote", "zen", "custom"], version < 1 ? "words" : "words");
        testLength = Math.round(numberValue(saved.testLength, mode === "time" ? 30 : 100, 1, 10000));
        punctuation = Boolean(saved.punctuation);
        numbers = Boolean(saved.numbers);
        language = saved.language || saved.languageProfile || "english";
        customText = saved.customText || "";
        difficulty = enumValue(saved.difficulty, ["normal", "expert", "master"], "normal");
        stopOnError = enumValue(saved.stopOnError, ["off", "letter", "word"], "off");
        deleteOnError = enumValue(saved.deleteOnError, ["off", "letter", "letter_hard", "word", "word_hard"], "off");
        confidenceMode = enumValue(saved.confidenceMode, ["off", "on", "max"], "off");
        blindMode = Boolean(saved.blindMode);
        quickEnd = Boolean(saved.quickEnd);
        resultSaving = version < 2 ? true : Boolean(saved.resultSaving);
        caretStyle = enumValue(saved.caretStyle, ["off", "line", "block", "outline", "underline"], "underline");
        smoothCaret = enumValue(saved.smoothCaret, ["off", "fast", "medium", "slow"], "medium");
        keyboardMode = enumValue(saved.keyboardMode, ["off", "static", "react", "next"], "react");
        const storedTheme = saved.themeName || saved.theme || "pure_black";
        themeName = storedTheme === "monkeyBlack" ? "pure_black" : storedTheme;
        quickRestart = saved.quickRestart || "tab";
        freedomMode = Boolean(saved.freedomMode);
        strictSpace = Boolean(saved.strictSpace);
        indicateTypos = saved.indicateTypos || "below";
        timerStyle = saved.timerStyle || "mini";
        liveSpeedStyle = saved.liveSpeedStyle || (saved.showLiveStats ? "text" : "off");
        liveAccStyle = saved.liveAccStyle || (saved.showLiveStats ? "text" : "off");
        trainer = saved.trainer || "off";
        quoteLength = saved.quoteLength || "all";
        quoteSearch = saved.quoteSearch || "";
        repeatQuotes = saved.repeatQuotes || "off";
        minWpm = saved.minWpm || "off";
        minWpmValue = Math.round(numberValue(saved.minWpmValue, 100, 1, 1000));
        minAcc = saved.minAcc || "off";
        minAccValue = Math.round(numberValue(saved.minAccValue, 90, 1, 100));
        minBurst = saved.minBurst || "off";
        minBurstValue = Math.round(numberValue(saved.minBurstValue, 100, 1, 1000));
        liveBurstStyle = saved.liveBurstStyle || "off";
        paceCaret = saved.paceCaret || "off";
        paceCaretWpm = Math.round(numberValue(saved.paceCaretWpm, 100, 1, 1000));
        paceCaretStyle = saved.paceCaretStyle || "line";
        keyboardScale = numberValue(saved.keyboardScale, 1, 0.5, 2);
        keyboardLabels = saved.keyboardLabels || "lowercase";
        typedEffect = saved.typedEffect || "keep";
        readAhead = saved.readAhead || "off";
        tapeMode = saved.tapeMode || "off";
        customTheme = Boolean(saved.customTheme);
        customThemeJson = saved.customThemeJson || "";
        panelOpacity = numberValue(saved.panelOpacity, 0.96, 0.55, 1);
        showKeyTips = saved.showKeyTips === undefined ? true : Boolean(saved.showKeyTips);
        capsLockWarning = saved.capsLockWarning === undefined ? true : Boolean(saved.capsLockWarning);
        focusWarning = saved.focusWarning === undefined ? true : Boolean(saved.focusWarning);
        panelX = numberValue(saved.panelX, -1, -1, 20000);
        panelY = numberValue(saved.panelY, -1, -1, 20000);
        panelWidth = numberValue(saved.panelWidth, 1040, 720, 20000);
        panelHeight = numberValue(saved.panelHeight, 700, 460, 20000);
        followShellColors = Boolean(saved.followShellColors);
        closeOnClickOutside = Boolean(saved.closeOnClickOutside);
        fontScale = numberValue(saved.fontScale, 1, 0.7, 1.8);
    }

    function scheduleWrite() {
        if (!restoring) persistTimer.restart();
    }

    function persistNow() {
        if (restoring) return;
        const saved = Persistent.states.typingTest;
        saved.schemaVersion = schemaVersion;
        const values = snapshot();
        for (const key in values) if (key !== "schemaVersion" && saved[key] !== undefined) saved[key] = values[key];
        writeCount++;
        settingsWritten();
    }

    function snapshot() {
        return {
            schemaVersion, mode, testLength, punctuation, numbers, language, customText,
            quoteLength, quoteSearch, difficulty, quickRestart, repeatQuotes, resultSaving,
            freedomMode, strictSpace, stopOnError, deleteOnError, confidenceMode, blindMode,
            quickEnd, indicateTypos, hideExtraLetters, minWpm, minWpmValue, minAcc, minAccValue,
            minBurst, minBurstValue, timerStyle, liveSpeedStyle, liveAccStyle, liveBurstStyle,
            caretStyle, smoothCaret, paceCaret, paceCaretWpm, paceCaretStyle, keyboardMode,
            keyboardScale, keyboardLabels, typedEffect, readAhead, tapeMode, trainer,
            theme: themeName, themeName,
            customTheme, customThemeJson, panelOpacity, showKeyTips, capsLockWarning, focusWarning,
            panelX, panelY, panelWidth, panelHeight, followShellColors, closeOnClickOutside, fontScale
        };
    }

    Component.onCompleted: {
        migrate(Persistent.states.typingTest);
        restoring = false;
        scheduleWrite();
    }

    property Timer persistTimer: Timer { interval: 250; repeat: false; onTriggered: root.persistNow() }

    onModeChanged: scheduleWrite(); onTestLengthChanged: scheduleWrite(); onPunctuationChanged: scheduleWrite()
    onNumbersChanged: scheduleWrite(); onLanguageChanged: scheduleWrite(); onCustomTextChanged: scheduleWrite()
    onQuoteLengthChanged: scheduleWrite(); onQuoteSearchChanged: scheduleWrite(); onDifficultyChanged: scheduleWrite()
    onQuickRestartChanged: scheduleWrite(); onRepeatQuotesChanged: scheduleWrite(); onResultSavingChanged: scheduleWrite()
    onFreedomModeChanged: scheduleWrite(); onStrictSpaceChanged: scheduleWrite(); onStopOnErrorChanged: scheduleWrite()
    onDeleteOnErrorChanged: scheduleWrite(); onConfidenceModeChanged: scheduleWrite(); onBlindModeChanged: scheduleWrite()
    onQuickEndChanged: scheduleWrite(); onIndicateTyposChanged: scheduleWrite(); onHideExtraLettersChanged: scheduleWrite()
    onMinWpmChanged: scheduleWrite(); onMinWpmValueChanged: scheduleWrite(); onMinAccChanged: scheduleWrite()
    onMinAccValueChanged: scheduleWrite(); onMinBurstChanged: scheduleWrite(); onMinBurstValueChanged: scheduleWrite()
    onTimerStyleChanged: scheduleWrite(); onLiveSpeedStyleChanged: scheduleWrite(); onLiveAccStyleChanged: scheduleWrite()
    onLiveBurstStyleChanged: scheduleWrite(); onCaretStyleChanged: scheduleWrite(); onSmoothCaretChanged: scheduleWrite()
    onPaceCaretChanged: scheduleWrite(); onPaceCaretWpmChanged: scheduleWrite(); onPaceCaretStyleChanged: scheduleWrite()
    onKeyboardModeChanged: scheduleWrite(); onKeyboardScaleChanged: scheduleWrite(); onKeyboardLabelsChanged: scheduleWrite()
    onTypedEffectChanged: scheduleWrite(); onReadAheadChanged: scheduleWrite(); onTapeModeChanged: scheduleWrite()
    onTrainerChanged: scheduleWrite(); onThemeNameChanged: scheduleWrite(); onCustomThemeChanged: scheduleWrite()
    onCustomThemeJsonChanged: scheduleWrite(); onPanelOpacityChanged: scheduleWrite(); onShowKeyTipsChanged: scheduleWrite()
    onCapsLockWarningChanged: scheduleWrite(); onFocusWarningChanged: scheduleWrite()
    onPanelXChanged: scheduleWrite(); onPanelYChanged: scheduleWrite(); onPanelWidthChanged: scheduleWrite()
    onPanelHeightChanged: scheduleWrite(); onFollowShellColorsChanged: scheduleWrite()
    onCloseOnClickOutsideChanged: scheduleWrite(); onFontScaleChanged: scheduleWrite()
}
