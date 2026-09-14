pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var engine
    required property var settings
    required property var theme
    property bool activeFocusTarget: false
    property var visibleWords: []
    property int windowStartWord: 0
    property int windowEndWord: -1
    property real windowBaseY: 0
    property real targetContentY: 0
    property int lastCurrentWordIndex: 0
    property int lastProcessedWordIndex: -1
    property int currentRenderedLine: 0
    property int logicalCurrentLine: 0
    property int currentLineStartWord: 0
    property int previousLineStartWord: 0
    property real currentLineY: 0
    property real previousLineY: 0
    property int viewportRebuilds: 0
    property int viewportTransitions: 0
    property string lastRebuildReason: "initial"
    property bool smoothViewport: true
    readonly property bool memoryHidden: settings.trainer === "memory" && engine.phase === "running"
    // Tuned so a default-width floating panel fits roughly 50 characters per
    // line, which is what Monkeytype shows at its default font size.
    readonly property real glyphSize: Math.max(20, Math.min(40, width / 31)) * settings.fontScale
    readonly property real glyphWidth: Math.max(12, glyphSize * 0.61)
    readonly property real lineHeight: glyphSize * 1.55
    // Monkeytype counts down seconds in time mode and counts words otherwise.
    readonly property string progressLabel: {
        if (settings.mode === "time") return `${engine.timeRemaining}`;
        if (settings.mode === "words") return `${engine.currentWordIndex}/${settings.testLength}`;
        if (settings.mode === "zen") return `${engine.currentWordIndex}`;
        return `${engine.currentWordIndex}/${Math.max(1, engine.targetWords.length)}`;
    }
    readonly property int activeDelegateCount: {
        let total = 0;
        for (const item of visibleWords) total += item.word.length + 1;
        return total;
    }

    function lineAnchorForWord(wordIndex, linesBefore) {
        const available = Math.max(1, typingViewport.width);
        const starts = [0];
        let line = 0;
        let used = 0;
        const finalWord = Math.max(0, Math.min(root.engine.targetWords.length - 1, wordIndex));
        for (let i = 0; i <= finalWord; ++i) {
            const wordWidth = (root.engine.targetWords[i].length + 1) * root.glyphWidth;
            if (used > 0 && used + wordWidth > available + 0.5) {
                line++;
                starts.push(i);
                used = 0;
            }
            used += wordWidth;
        }
        const anchorLine = Math.max(0, line - Math.max(0, linesBefore));
        return {word: starts[anchorLine], line: anchorLine, currentLine: line};
    }

    function currentLayoutAnchor() {
        if (root.engine.targetWords.length === 0)
            return {currentWord: 0, previousWord: 0, currentY: 0, previousY: 0, currentLine: 0};
        const current = root.lineAnchorForWord(root.engine.currentWordIndex, 0);
        const previous = root.lineAnchorForWord(root.engine.currentWordIndex, 1);
        return {
            currentWord: current.word,
            previousWord: previous.word,
            currentY: current.line * root.lineHeight,
            previousY: previous.line * root.lineHeight,
            currentLine: current.line
        };
    }

    function installWindow(startWord, baseY, reason) {
        const words = root.engine.visibleWordsFrom(startWord, root.engine.visibleDelegateBudget);
        root.windowStartWord = words.length > 0 ? words[0].index : 0;
        root.windowEndWord = words.length > 0 ? words[words.length - 1].index : -1;
        root.visibleWords = words;
        root.windowBaseY = Math.max(0, baseY);
        root.viewportRebuilds++;
        root.lastRebuildReason = reason;
        Qt.callLater(() => root.reconcileViewport(0, false));
    }

    function rebuildAroundCurrent(reason) {
        if (root.engine.targetWords.length === 0) {
            root.installWindow(0, 0, reason);
            return;
        }
        const anchor = root.lineAnchorForWord(root.engine.currentWordIndex, 1);
        root.installWindow(anchor.word, anchor.line * root.lineHeight, reason);
    }

    function renderedLines() {
        const lines = [];
        if (!wordRepeater || wordRepeater.count === 0) return lines;
        for (let i = 0; i < wordRepeater.count; ++i) {
            const item = wordRepeater.itemAt(i);
            if (item && (lines.length === 0 || Math.abs(lines[lines.length - 1].y - item.y) > 0.5))
                lines.push({y: item.y, startWord: item.wordIndex});
        }
        return lines;
    }

    function setScrollTarget(wanted, direction, animate) {
        let next = Math.max(0, wanted);
        if (direction > 0) next = Math.max(root.targetContentY, next);
        root.smoothViewport = animate;
        root.targetContentY = next;
        typingViewport.contentY = next;
        if (!animate) Qt.callLater(() => root.smoothViewport = true);
    }

    function reconcileViewport(direction, allowRebase) {
        if (!wordRepeater || wordRepeater.count === 0) return;
        const localIndex = root.engine.currentWordIndex - root.windowStartWord;
        const current = localIndex >= 0 && localIndex < wordRepeater.count
            ? wordRepeater.itemAt(localIndex) : null;
        if (!current) {
            root.rebuildAroundCurrent(direction < 0 ? "backward-range" : "forward-range");
            return;
        }

        const lines = root.renderedLines();
        let lineIndex = 0;
        for (let i = 0; i < lines.length; ++i) {
            if (Math.abs(lines[i].y - current.y) <= 0.5) {
                lineIndex = i;
                break;
            }
        }
        const layoutAnchor = root.currentLayoutAnchor();
        root.currentLineStartWord = layoutAnchor.currentWord;
        root.previousLineStartWord = layoutAnchor.previousWord;
        root.currentLineY = layoutAnchor.currentY;
        root.previousLineY = layoutAnchor.previousY;
        const globalY = layoutAnchor.currentY;
        root.currentRenderedLine = lineIndex;
        root.logicalCurrentLine = Math.max(0, Math.round(globalY / root.lineHeight));
        root.setScrollTarget(Math.max(0, globalY - root.lineHeight), direction, direction !== 0);

        // Rebase when fewer than three complete lines remain after the active
        // line. Keeping a deeper tail means users never watch the last visible
        // row being assembled word by word, while the previous line remains
        // available for natural Backspace navigation.
        if (allowRebase && direction > 0 && lines.length >= 6 && lineIndex >= lines.length - 3) {
            if (layoutAnchor.previousWord > root.windowStartWord) {
                root.viewportTransitions++;
                root.installWindow(layoutAnchor.previousWord,
                    layoutAnchor.previousY, "forward-line");
            }
        }
    }

    function restartViewport() {
        root.smoothViewport = false;
        root.targetContentY = 0;
        typingViewport.contentY = 0;
        root.lastCurrentWordIndex = 0;
        root.lastProcessedWordIndex = 0;
        root.installWindow(0, 0, "restart");
    }

    ColumnLayout {
        anchors.fill: parent
        // Kept tight: six rows at 16px spacing cost 80px, which is the
        // difference between the keyboard fitting and overlapping the hints
        // at the minimum panel height.
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 20
            spacing: 14
            visible: root.settings.timerStyle !== "off" || root.settings.liveSpeedStyle !== "off" || root.settings.liveAccStyle !== "off" || root.settings.liveBurstStyle !== "off"
            // Monkeytype shows nothing until the first keystroke, but the row
            // keeps its height so the words do not jump when it appears.
            opacity: root.engine.phase === "ready" ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 140 } }
            StyledText { visible: root.settings.timerStyle !== "off"; text: root.progressLabel; color: root.theme.main; font.family: Appearance.font.family.monospace; font.pixelSize: root.settings.timerStyle === "mini" ? 14 : 18 }
            StyledText { visible: root.settings.liveSpeedStyle !== "off"; text: `${root.engine.wpm} wpm`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 12 }
            StyledText { visible: root.settings.liveAccStyle !== "off"; text: `${root.engine.accuracy}% acc`; color: root.engine.accuracy < 90 ? root.theme.error : root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 12 }
            StyledText { visible: root.settings.liveBurstStyle !== "off"; text: `${root.engine.peakBurst} burst`; color: root.theme.sub; font.family: Appearance.font.family.monospace; font.pixelSize: 12 }
            Item { Layout.fillWidth: true }
            StyledText { visible: root.engine.practiceKind.length > 0; text: `practice: ${root.engine.practiceKind}`; color: root.theme.main; font.family: Appearance.font.family.monospace; font.pixelSize: 11 }
        }

        Rectangle {
            visible: root.settings.timerStyle === "bar"
            Layout.fillWidth: true
            Layout.preferredHeight: 3
            radius: 2
            color: root.theme.subAlt
            Rectangle { height: parent.height; width: parent.width * root.engine.progress; radius: parent.radius; color: root.theme.main }
        }

        // Spacers above and below the word block centre it in whatever space the
        // keyboard leaves, the way Monkeytype does.
        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }

        Flickable {
            id: typingViewport
            Layout.fillWidth: true
            // Exactly three lines: a partially visible fourth line reads as a
            // rendering bug rather than as more text to come.
            Layout.preferredHeight: root.lineHeight * 3
            Layout.maximumHeight: root.lineHeight * 3
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: Math.max(height, wordFlow.y + wordFlow.implicitHeight)

            Behavior on contentY {
                enabled: root.smoothViewport
                NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
            }

            Flow {
                id: wordFlow
                y: root.windowBaseY
                width: typingViewport.width
                spacing: 0

                Repeater {
                    id: wordRepeater
                    model: root.visibleWords
                    delegate: Item {
                        id: wordItem
                        required property var modelData
                        property int wordIndex: Number(modelData?.index ?? 0)
                        property string word: String(modelData?.word ?? "")
                        property int offset: Number(modelData?.offset ?? 0)
                        property bool current: root.engine.typedLength >= offset && root.engine.typedLength <= offset + word.length
                        width: (word.length + 1) * root.glyphWidth
                        height: root.lineHeight

                        Row {
                            y: (root.lineHeight - root.glyphSize * 1.15) / 2
                            Repeater {
                                model: wordItem.word.length
                                delegate: Text {
                                    required property int index
                                    width: root.glyphWidth
                                    height: root.glyphSize * 1.2
                                    text: wordItem.word[index]
                                    color: {
                                        const typed = root.engine.typedText[wordItem.offset + index];
                                        if (root.memoryHidden && typed === undefined) return "transparent";
                                        if (typed === undefined) {
                                            const ahead = root.settings.readAhead === "one" ? 1 : root.settings.readAhead === "two" ? 2 : root.settings.readAhead === "three" ? 3 : 9999;
                                            return wordItem.wordIndex > root.engine.currentWordIndex + ahead ? Qt.alpha(root.theme.sub, 0.16) : root.theme.sub;
                                        }
                                        if (root.settings.typedEffect === "hide") return "transparent";
                                        if (typed === wordItem.word[index]) return root.settings.typedEffect === "fade" ? Qt.alpha(root.theme.text, 0.42) : root.theme.text;
                                        if (root.settings.blindMode) return root.theme.text;
                                        return root.theme.error;
                                    }
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: root.glyphSize
                                    renderType: Text.NativeRendering
                                    Rectangle {
                                        visible: {
                                            const typed = root.engine.typedText[wordItem.offset + index];
                                            return typed !== undefined && typed !== wordItem.word[index]
                                                && !root.settings.blindMode
                                                && (root.settings.indicateTypos === "below" || root.settings.indicateTypos === "both");
                                        }
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.bottom
                                        anchors.topMargin: -2
                                        width: Math.max(4, parent.width * 0.6)
                                        height: 3
                                        radius: 2
                                        color: root.theme.error
                                    }
                                }
                            }
                        }

                        Rectangle {
                            visible: wordItem.current && root.settings.caretStyle !== "off" && root.engine.phase !== "finished"
                            x: Math.max(0, Math.min(root.engine.typedLength - wordItem.offset, wordItem.word.length)) * root.glyphWidth
                            y: root.settings.caretStyle === "underline" ? root.lineHeight - 9 : (root.lineHeight - root.glyphSize * 1.12) / 2
                            width: root.settings.caretStyle === "line" ? 4 : Math.max(14, root.glyphWidth - 1)
                            height: root.settings.caretStyle === "underline" ? 6 : root.glyphSize * 1.12
                            radius: root.settings.caretStyle === "underline" ? 3 : 2
                            color: root.settings.caretStyle === "outline" ? "transparent" : (root.settings.caretStyle === "block" ? Qt.alpha(root.theme.caret, 0.30) : root.theme.caret)
                            border.width: root.settings.caretStyle === "outline" ? 2 : 0
                            border.color: root.theme.caret
                            Behavior on x { NumberAnimation { duration: root.settings.smoothCaret === "off" ? 0 : (root.settings.smoothCaret === "fast" ? 55 : root.settings.smoothCaret === "slow" ? 175 : 105); easing.type: Easing.OutQuart } }
                            SequentialAnimation on opacity {
                                running: root.engine.phase === "ready"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.25; duration: 500 }
                                NumberAnimation { to: 1; duration: 500 }
                            }
                        }

                        Rectangle {
                            visible: root.engine.paceCaretIndex >= wordItem.offset && root.engine.paceCaretIndex <= wordItem.offset + wordItem.word.length
                            x: Math.min(root.engine.paceCaretIndex - wordItem.offset, wordItem.word.length) * root.glyphWidth
                            y: (root.lineHeight - root.glyphSize) / 2
                            width: 2
                            height: root.glyphSize
                            color: Qt.alpha(root.theme.main, 0.46)
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 10
            // Drops out first when the panel is too short for everything.
            visible: root.engine.phase === "ready" && root.height > 400
            text: "start typing"
            color: root.theme.sub
            font.family: Appearance.font.family.monospace
            font.pixelSize: 11
        }

        Item { Layout.fillHeight: true; Layout.minimumHeight: 0 }

        TypingKeyboard {
            visible: root.settings.keyboardMode !== "off"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.fillWidth: true
            Layout.maximumWidth: Math.min(root.width, 680) * root.settings.keyboardScale
            // Four 40px rows plus three 7px gaps at full size. The board scales
            // itself down inside this box rather than clipping its last row.
            Layout.preferredHeight: 181 * root.settings.keyboardScale
            Layout.maximumHeight: 181 * root.settings.keyboardScale
            Layout.minimumHeight: 84
            highlightedCharacter: root.settings.keyboardMode === "next" ? (root.engine.targetText[root.engine.typedLength] || "") : root.engine.lastCharacter
            keySerial: root.engine.lastKeySerial
            mode: root.settings.keyboardMode
            labelStyle: root.settings.keyboardLabels
            mainColor: root.theme.main
            textColor: root.theme.text
            mutedColor: root.theme.sub
            keyColor: root.theme.subAlt
        }
    }

    Connections {
        target: root.engine
        function onCurrentWordIndexChanged(): void {
            if (root.engine.currentWordIndex === root.lastProcessedWordIndex) return;
            const direction = root.engine.currentWordIndex >= root.lastCurrentWordIndex ? 1 : -1;
            root.lastCurrentWordIndex = root.engine.currentWordIndex;
            root.lastProcessedWordIndex = root.engine.currentWordIndex;
            viewportUpdate.restartDirection = direction;
            viewportUpdate.restart();
        }
        // Timed tests append target text before the current window runs out.
        // Deliberately do not replace the visible model here.
        function onRestarted(): void { root.restartViewport(); }
    }

    Timer {
        id: viewportUpdate
        property int restartDirection: 0
        interval: 0
        repeat: false
        onTriggered: root.reconcileViewport(restartDirection, true)
    }

    Timer {
        id: relayoutUpdate
        interval: 35
        repeat: false
        onTriggered: root.rebuildAroundCurrent("layout")
    }

    onWidthChanged: if (width > 0) relayoutUpdate.restart()
    onGlyphWidthChanged: if (width > 0) relayoutUpdate.restart()
    Component.onCompleted: restartViewport()
}
