pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root

    required property var settings
    required property var data
    property bool panelActive: true

    property string phase: "ready"
    property string targetText: ""
    property string typedText: ""
    property string testSource: ""
    property int testSeed: 1
    property int startedAt: 0
    property int elapsedMs: 0
    property int correctChars: 0
    property int incorrectChars: 0
    property int errorCount: 0
    property int keypressCount: 0
    property int backspaceCount: 0
    property int lastKeyAt: 0
    property string lastCharacter: ""
    property int lastKeySerial: 0
    property int currentWordStartedAt: 0
    property int peakBurst: 0
    property bool failed: false
    property string failureReason: ""
    property var undoStack: []
    property var inputEvents: []
    property var samples: []
    property var wordStats: []
    property var weakKeys: ({})
    property var latestResult: ({})
    property var practiceWords: []
    property string practiceKind: ""
    property string quoteSource: ""
    property string importedPackName: ""
    property var importedWords: []
    property var importedQuotes: []
    property int analyticsTicks: 0
    property int clockTicks: 0

    readonly property int typedLength: typedText.length
    readonly property real minutes: Math.max(1, elapsedMs) / 60000
    readonly property int wpm: Math.max(0, Math.round((correctChars / 5) / minutes))
    readonly property int rawWpm: Math.max(0, Math.round((typedLength / 5) / minutes))
    readonly property int accuracy: typedLength > 0 ? Math.round(correctChars * 100 / typedLength) : 100
    readonly property int currentWordIndex: {
        if (settings.trainer === "no_space" || settings.trainer === "underscore") {
            for (let i = wordOffsets.length - 1; i >= 0; --i)
                if (typedText.length >= wordOffsets[i]) return i;
            return 0;
        }
        if (typedText.length === 0) return 0;
        let count = 0;
        for (let i = 0; i < typedText.length; ++i) if (typedText[i] === " ") count++;
        return count;
    }
    readonly property var targetWords: targetText.length > 0 ? targetText.split(" ") : []
    readonly property var wordOffsets: {
        const offsets = [];
        let offset = 0;
        for (let i = 0; i < targetWords.length; ++i) {
            offsets.push(offset);
            offset += targetWords[i].length + 1;
        }
        return offsets;
    }
    readonly property int endOfTestIndex: {
        if (settings.mode !== "words" || targetWords.length === 0) return targetText.length;
        const count = Math.min(settings.testLength, targetWords.length);
        return wordOffsets[count - 1] + targetWords[count - 1].length;
    }
    readonly property int timeRemaining: settings.mode === "time"
        ? Math.max(0, settings.testLength - Math.floor(elapsedMs / 1000))
        : Math.floor(elapsedMs / 1000)
    readonly property real progress: settings.mode === "time"
        ? Math.min(1, elapsedMs / Math.max(1, settings.testLength * 1000))
        : (settings.mode === "words" ? Math.min(1, typedLength / Math.max(1, endOfTestIndex))
            : Math.min(1, typedLength / Math.max(1, targetText.length)))
    // A fixed upper bound for the virtualized typing viewport. This is large
    // enough for the visible three lines plus a line buffer on either side,
    // but it never grows with a timed or 1,000-word test.
    readonly property int visibleDelegateBudget: 360
    readonly property int paceCaretIndex: settings.paceCaret === "off" || phase !== "running" ? -1
        : Math.floor((resolvedPaceWpm() * 5) * elapsedMs / 60000)

    signal finished(var result)
    signal restarted
    signal inputRejected(string reason)

    function xorshift(value) {
        let x = value | 0;
        x ^= x << 13;
        x ^= x >>> 17;
        x ^= x << 5;
        return x >>> 0;
    }

    function seededIndex(seed, length) {
        return length > 0 ? xorshift(seed) % length : 0;
    }

    function quoteMatches(quote) {
        const words = quote.text.trim().split(/\s+/).length;
        const length = settings.quoteLength;
        const inBucket = length === "all"
            || (length === "short" && words <= 15)
            || (length === "medium" && words > 15 && words <= 30)
            || (length === "long" && words > 30 && words <= 60)
            || (length === "thicc" && words > 60);
        const search = settings.quoteSearch.trim().toLowerCase();
        return inBucket && (search.length === 0
            || quote.text.toLowerCase().includes(search)
            || String(quote.source || "").toLowerCase().includes(search));
    }

    function selectQuote(seed) {
        const source = importedQuotes.length > 0 ? importedQuotes : data.quotesFor(settings.language);
        let matches = source.filter(quote => quoteMatches(quote));
        if (matches.length === 0) matches = source;
        const quote = matches[seededIndex(seed, matches.length)] || {text: "Practice deliberately and keep a steady rhythm.", source: "Local trainer"};
        quoteSource = quote.source || "";
        return quote.text;
    }

    function punctuationWord(word, index, seed, previous) {
        let value = word;
        if (settings.punctuation) {
            if (index === 0 || /[.!?]$/.test(previous || "")) value = value.charAt(0).toUpperCase() + value.slice(1);
            const marks = [",", ".", ",", ".", "?", "!", ";", ":"];
            if (index > 0 && index % 8 === 7) value += marks[(seed >>> 8) % marks.length];
        }
        return value;
    }

    function trainerTransform(words, seed) {
        const trainer = settings.trainer;
        if (trainer === "off" || trainer === "weakspot" || trainer === "memory") return words;
        const symbols = ["!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "-", "+", "=", "?", "/"];
        const out = [];
        for (let i = 0; i < words.length; ++i) {
            let word = words[i];
            const localSeed = xorshift(seed + i * 97);
            if (trainer === "no_space" && i > 0) word = "" + word;
            else if (trainer === "capitals") word = word.charAt(0).toUpperCase() + word.slice(1);
            else if (trainer === "all_caps") word = word.toUpperCase();
            else if (trainer === "random_case") {
                let mixed = "";
                for (let c = 0; c < word.length; ++c) mixed += (xorshift(localSeed + c) & 1) ? word[c].toUpperCase() : word[c].toLowerCase();
                word = mixed;
            } else if (trainer === "ascii") word = String(33 + localSeed % 94);
            else if (trainer === "symbols") word = symbols[localSeed % symbols.length] + symbols[(localSeed >>> 4) % symbols.length];
            else if (trainer === "binary") word = (localSeed & 255).toString(2).padStart(8, "0");
            else if (trainer === "hexadecimal") word = "0x" + (localSeed & 65535).toString(16).padStart(4, "0");
            else if (trainer === "ipv4") word = `${localSeed & 255}.${(localSeed >>> 8) & 255}.${(localSeed >>> 16) & 255}.${(localSeed >>> 24) & 255}`;
            else if (trainer === "ipv6") word = `${(localSeed & 65535).toString(16)}:${((localSeed >>> 8) & 65535).toString(16)}::${((localSeed >>> 16) & 65535).toString(16)}`;
            else if (trainer === "backwards") word = word.split("").reverse().join("");
            else if (trainer === "doubled") word = word.split("").map(character => character + character).join("");
            else if (trainer === "underscore") word = i === words.length - 1 ? word : word + "_";
            out.push(word);
        }
        return out;
    }

    function weakCharacters() {
        const entries = Object.keys(weakKeys).map(key => ({key, score: Number(weakKeys[key].score || 0)}));
        entries.sort((a, b) => b.score - a.score);
        return entries.slice(0, 8).map(entry => entry.key);
    }

    function wordPool() {
        if (practiceWords.length > 0) return practiceWords;
        if (importedWords.length > 0) return importedWords;
        const base = data.wordsFor(settings.language);
        if (settings.trainer !== "weakspot") return base;
        const weak = weakCharacters();
        if (weak.length === 0) return base;
        const focused = base.filter(word => weak.some(character => word.toLowerCase().includes(character)));
        return focused.length >= 20 ? focused : base;
    }

    function buildWords(count, seed, continuation) {
        const pool = wordPool();
        const output = [];
        let state = seed;
        for (let i = 0; i < count; ++i) {
            state = xorshift(state + i + 1);
            let word = String(pool[state % Math.max(1, pool.length)] || "type");
            if (settings.numbers && i > 0 && i % 11 === 0) word = String(10 + state % 990);
            word = punctuationWord(word, i, state, output[i - 1]);
            output.push(word);
        }
        const transformed = trainerTransform(output, seed);
        if (settings.trainer === "no_space") return transformed.join("");
        if (settings.trainer === "underscore") return transformed.join("");
        return transformed.join(" ");
    }

    function buildTarget(seed, continuation) {
        if (settings.mode === "zen") return "";
        if (settings.mode === "custom") return settings.customText.trim() || "Paste or write your own text in the custom editor, then begin typing it here.";
        if (settings.mode === "quote") return selectQuote(seed);
        if (practiceWords.length > 0) return practiceWords.join(" ");
        const count = settings.mode === "words" ? Math.max(settings.testLength + 24, 60) : 120;
        return buildWords(count, seed, continuation);
    }

    function restart(seed) {
        clockTimer.stop();
        analyticsTimer.stop();
        if (seed !== undefined) testSeed = Math.max(1, Number(seed) | 0);
        else if (!(settings.repeatQuotes === "always" && settings.mode === "quote")) testSeed = Math.max(1, Date.now() & 0x7fffffff);
        phase = "ready";
        typedText = "";
        startedAt = 0;
        elapsedMs = 0;
        correctChars = 0;
        incorrectChars = 0;
        errorCount = 0;
        keypressCount = 0;
        backspaceCount = 0;
        lastKeyAt = 0;
        currentWordStartedAt = 0;
        peakBurst = 0;
        failed = false;
        failureReason = "";
        undoStack = [];
        inputEvents = [];
        samples = [];
        wordStats = [];
        latestResult = ({});
        quoteSource = "";
        targetText = buildTarget(testSeed, false);
        testSource = targetText;
        restarted();
    }

    function repeatTest() {
        const preserved = testSource;
        restart(testSeed);
        targetText = preserved;
        testSource = preserved;
    }

    function beginIfNeeded(now) {
        if (phase !== "ready") return;
        phase = "running";
        startedAt = now;
        currentWordStartedAt = now;
        if (panelActive) {
            clockTimer.start();
            analyticsTimer.start();
        }
    }

    function appendEvent(kind, text, correct, modifiers, now, beforeLength) {
        inputEvents = inputEvents.concat([{
            t: Math.max(0, now - startedAt), type: kind, text,
            correct, word: currentWordIndex, modifiers: modifiers || 0,
            before: beforeLength, after: typedText.length
        }]);
    }

    function updateWeakKey(character, wrong, latency) {
        const key = character.toLowerCase();
        if (!key || /\s/.test(key)) return;
        const previous = weakKeys[key] || {latency: latency, errors: 0, score: 0, count: 0};
        const safeLatency = Math.max(0, Math.min(2000, latency));
        const alpha = 0.18;
        const nextLatency = previous.count > 0 ? previous.latency * (1 - alpha) + safeLatency * alpha : safeLatency;
        const errors = previous.errors * 0.96 + (wrong ? 1 : 0);
        const copy = Object.assign({}, weakKeys);
        copy[key] = {latency: Math.round(nextLatency), errors, score: Math.round(nextLatency + errors * 420), count: previous.count + 1};
        weakKeys = copy;
    }

    function currentExpectedWord() {
        const index = currentWordIndex;
        return targetWords[index] || "";
    }

    function currentTypedWord() {
        const start = typedText.lastIndexOf(" ") + 1;
        return typedText.slice(start);
    }

    function finalizeWord(now) {
        const index = Math.max(0, currentWordIndex - 1);
        const expected = targetWords[index] || "";
        const end = typedText.lastIndexOf(" ");
        const before = end > 0 ? typedText.lastIndexOf(" ", end - 1) + 1 : 0;
        const typed = typedText.slice(before, end);
        const duration = Math.max(1, now - currentWordStartedAt);
        const correct = typed === expected;
        const burst = Math.round((typed.length / 5) / (duration / 60000));
        peakBurst = Math.max(peakBurst, burst);
        wordStats = wordStats.concat([{index, expected, typed, correct, missed: !correct, duration, burst}]);
        currentWordStartedAt = now;
    }

    function shouldRejectSpace() {
        if (settings.mode === "zen" || settings.freedomMode) return false;
        if (settings.strictSpace && currentTypedWord().length !== currentExpectedWord().length) return true;
        if (settings.stopOnError === "word" && currentTypedWord() !== currentExpectedWord()) return true;
        return false;
    }

    function applyDeleteOnError() {
        if (settings.deleteOnError === "off") return;
        if (settings.deleteOnError.startsWith("word")) {
            let target = typedText.length;
            while (target > 0 && /\s/.test(typedText[target - 1])) target--;
            while (target > 0 && !/\s/.test(typedText[target - 1])) target--;
            while (typedText.length > target) popCharacter();
        } else {
            // Monkeytype's delete-on-error removes the incorrect input and the
            // preceding correct letter, placing the user before the mistake.
            popCharacter();
            if (typedText.length > 0) popCharacter();
        }
        trimWordStats();
    }

    function acceptText(text, modifiers) {
        if (!text || phase === "finished") return false;
        let acceptedAny = false;
        for (let position = 0; position < text.length; ++position) {
            const character = text[position];
            const now = Date.now();
            const before = typedText.length;
            const expected = settings.mode === "zen" || settings.freedomMode ? character : (targetText[before] || "");
            const wrong = settings.mode !== "zen" && !settings.freedomMode && character !== expected;
            const latency = lastKeyAt > 0 ? now - lastKeyAt : 0;
            lastKeyAt = now;
            keypressCount++;
            if (wrong) errorCount++;
            updateWeakKey(expected || character, wrong, latency);
            lastCharacter = character.toLowerCase();
            lastKeySerial++;

            if (character === " " && shouldRejectSpace()) {
                appendEvent("reject", character, false, modifiers, now, before);
                inputRejected("space");
                continue;
            }
            if (wrong && settings.stopOnError === "letter") {
                appendEvent("reject", character, false, modifiers, now, before);
                inputRejected("letter");
                continue;
            }

            beginIfNeeded(now);
            typedText += character;
            if (wrong) incorrectChars++; else correctChars++;
            undoStack = undoStack.concat([{character, correct: !wrong, before, at: now}]);
            appendEvent("insert", character, !wrong, modifiers, now, before);
            acceptedAny = true;
            if (character === " ") finalizeWord(now);

            if (wrong && settings.deleteOnError !== "off") {
                applyDeleteOnError();
                if (settings.deleteOnError.endsWith("hard")) inputRejected("hard-delete");
            }
            if (wrong && settings.difficulty === "master") fail("master difficulty");
            else if (character === " " && settings.difficulty === "expert" && wordStats.length > 0 && !wordStats[wordStats.length - 1].correct) fail("expert difficulty");
            if (phase === "finished") break;

            if (settings.mode === "time" && typedText.length > targetText.length - 160)
                targetText += " " + buildWords(100, xorshift(testSeed + targetText.length), true);
            if (settings.mode === "words" && typedText.length >= endOfTestIndex) {
                const complete = typedText.slice(0, endOfTestIndex) === targetText.slice(0, endOfTestIndex);
                if (complete || settings.quickEnd) finishTest();
            } else if ((settings.mode === "quote" || settings.mode === "custom") && typedText.length >= targetText.length) finishTest();
        }
        return acceptedAny;
    }

    function acceptComposition(text, modifiers) {
        if (!text || phase === "finished") return false;
        return acceptText(text.normalize ? text.normalize("NFC") : text, modifiers);
    }

    function canDelete() {
        if (typedText.length === 0 || phase === "finished" || settings.confidenceMode === "max") return false;
        if (settings.confidenceMode === "on" && typedText.endsWith(" ")) return false;
        return true;
    }

    function popCharacter() {
        if (undoStack.length === 0 || typedText.length === 0) return false;
        const record = undoStack[undoStack.length - 1];
        undoStack = undoStack.slice(0, -1);
        typedText = typedText.slice(0, -1);
        if (record.correct) correctChars = Math.max(0, correctChars - 1);
        else incorrectChars = Math.max(0, incorrectChars - 1);
        return true;
    }

    function eraseCharacter(modifiers, automatic) {
        if (!canDelete()) return false;
        const now = Date.now();
        const beforeText = typedText;
        if (!popCharacter()) return false;
        if (!automatic) backspaceCount++;
        lastCharacter = "backspace";
        lastKeySerial++;
        appendEvent("delete", beforeText.slice(typedText.length), true, modifiers, now, beforeText.length);
        trimWordStats();
        return true;
    }

    function eraseWord(modifiers, automatic) {
        if (!canDelete()) return false;
        const now = Date.now();
        const beforeText = typedText;
        let target = typedText.length;
        while (target > 0 && /\s/.test(typedText[target - 1])) target--;
        while (target > 0 && !/\s/.test(typedText[target - 1])) target--;
        if (settings.confidenceMode === "on") target = Math.max(target, typedText.lastIndexOf(" ") + 1);
        while (typedText.length > target) popCharacter();
        if (beforeText === typedText) return false;
        if (!automatic) backspaceCount++;
        lastCharacter = "backspace";
        lastKeySerial++;
        appendEvent("deleteWord", beforeText.slice(typedText.length), true, modifiers, now, beforeText.length);
        trimWordStats();
        return true;
    }

    function trimWordStats() {
        const completed = typedText.split(" ").length - 1;
        if (wordStats.length > completed) wordStats = wordStats.slice(0, completed);
    }

    function makeSample() {
        const previous = samples.length > 0 ? samples[samples.length - 1] : null;
        const previousTime = previous ? previous.t : 0;
        const previousChars = previous ? previous.characters : 0;
        const interval = Math.max(1, elapsedMs - previousTime);
        const chars = Math.max(0, typedLength - previousChars);
        const burst = Math.round((chars / 5) / (interval / 60000));
        peakBurst = Math.max(peakBurst, burst);
        return {t: elapsedMs, wpm, raw: rawWpm, burst, errors: errorCount - (previous ? previous.totalErrors : 0), totalErrors: errorCount, characters: typedLength};
    }

    function appendSample() {
        const sample = makeSample();
        samples = samples.concat([sample]);
        checkThresholds(sample);
    }

    function checkThresholds(sample) {
        if (elapsedMs < 3000) return;
        if (settings.minWpm !== "off" && sample.wpm < settings.minWpmValue) fail("minimum wpm");
        else if (settings.minAcc !== "off" && accuracy < settings.minAccValue) fail("minimum accuracy");
        else if (settings.minBurst !== "off" && sample.burst < settings.minBurstValue) fail("minimum burst");
    }

    function fail(reason) {
        failed = true;
        failureReason = reason;
        finishTest();
    }

    function consistency() {
        if (samples.length < 2) return 100;
        const values = samples.slice(samples.length > 2 ? 1 : 0).map(sample => sample.wpm);
        const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
        if (mean <= 0) return 100;
        const variance = values.reduce((sum, value) => sum + Math.pow(value - mean, 2), 0) / values.length;
        return Math.max(0, Math.min(100, Math.round(100 - Math.sqrt(variance) / mean * 100)));
    }

    function characterBreakdown() {
        const resultLength = settings.mode === "time" || settings.mode === "zen" ? typedLength
            : (settings.mode === "words" ? endOfTestIndex : targetText.length);
        return {
            correct: correctChars,
            incorrect: incorrectChars,
            extra: Math.max(0, typedLength - resultLength),
            missed: Math.max(0, resultLength - typedLength)
        };
    }

    function finishTest() {
        if (phase === "finished") return latestResult;
        if (phase === "running") elapsedMs = Date.now() - startedAt;
        phase = "finished";
        clockTimer.stop();
        analyticsTimer.stop();
        if (samples.length === 0 || samples[samples.length - 1].t !== elapsedMs) appendSample();
        const breakdown = characterBreakdown();
        const missedWords = wordStats.filter(word => word.missed).map(word => word.expected);
        const sortedSlow = wordStats.slice().sort((a, b) => b.duration - a.duration).slice(0, 12);
        const weakest = Object.keys(weakKeys).map(key => ({key, score: weakKeys[key].score, latency: weakKeys[key].latency, errors: weakKeys[key].errors}))
            .sort((a, b) => b.score - a.score).slice(0, 10);
        latestResult = {
            version: 3, timestamp: Date.now(), seed: testSeed,
            mode: settings.mode, length: settings.testLength, language: settings.language,
            punctuation: settings.punctuation, numbers: settings.numbers, difficulty: settings.difficulty,
            trainer: settings.trainer, theme: settings.themeName, quoteSource,
            wpm, rawWpm, accuracy, consistency: consistency(), peakBurst,
            characters: typedLength, correct: breakdown.correct, incorrect: breakdown.incorrect,
            extra: breakdown.extra, missed: breakdown.missed,
            errors: errorCount, keypresses: keypressCount, backspaces: backspaceCount,
            durationMs: elapsedMs, failed, failureReason,
            samples, words: wordStats, missedWords, slowWords: sortedSlow,
            weakKeys: weakest, weakKeyState: weakKeys,
            events: inputEvents, typedSnapshot: typedText.slice(0, 12000),
            targetSnapshot: targetText.slice(0, 12000), sourceSnapshot: testSource.slice(0, 12000)
        };
        finished(latestResult);
        return latestResult;
    }

    function startPractice(kind, result) {
        practiceKind = kind;
        if (kind === "missed") practiceWords = (result.missedWords || []).slice();
        else if (kind === "slow") practiceWords = (result.slowWords || []).map(word => word.expected);
        else {
            const combined = (result.missedWords || []).concat((result.slowWords || []).map(word => word.expected));
            practiceWords = Array.from(new Set(combined));
        }
        if (practiceWords.length === 0) practiceWords = data.wordsFor(settings.language).slice(0, 20);
        restart();
    }

    function clearPractice() {
        practiceWords = [];
        practiceKind = "";
        restart();
    }

    function importPack(text) {
        const parsed = data.parsePack(text);
        if (!parsed.valid) return parsed;
        importedPackName = parsed.name || "Imported";
        if (parsed.kind === "words") importedWords = parsed.words;
        else importedQuotes = parsed.quotes;
        restart();
        return parsed;
    }

    function visibleWordsAround(index, radius) {
        const safeRadius = Math.max(8, Math.min(48, radius || 24));
        const first = Math.max(0, index - safeRadius);
        return visibleWordsFrom(first, visibleDelegateBudget, index + safeRadius + 1);
    }

    function visibleWordsFrom(index, budget, lastExclusive) {
        const first = Math.max(0, Math.min(targetWords.length, Number(index) || 0));
        const safeBudget = Math.max(48, Math.min(visibleDelegateBudget, Number(budget) || visibleDelegateBudget));
        const last = Math.min(targetWords.length, lastExclusive === undefined ? targetWords.length : lastExclusive);
        const output = [];
        let delegates = 0;
        for (let i = first; i < last && delegates < safeBudget; ++i) {
            const word = targetWords[i];
            if (output.length > 0 && delegates + word.length + 1 > safeBudget) break;
            output.push({index: i, word, offset: wordOffsets[i]});
            delegates += word.length + 1;
        }
        return output;
    }

    function resolvedPaceWpm() {
        if (settings.paceCaret === "custom") return settings.paceCaretWpm;
        if (settings.paceCaret === "previous" && latestResult.wpm) return latestResult.wpm;
        if (settings.paceCaret === "pb" && latestResult.comparablePb) return latestResult.comparablePb;
        if (settings.paceCaret === "recent" && latestResult.recentAverageWpm) return latestResult.recentAverageWpm;
        return settings.paceCaretWpm;
    }

    onPanelActiveChanged: {
        if (!panelActive) {
            clockTimer.stop();
            analyticsTimer.stop();
        } else if (phase === "running") {
            clockTimer.start();
            analyticsTimer.start();
        }
    }

    property Timer clockTimer: Timer {
        interval: 100
        repeat: true
        running: false
        onTriggered: {
            root.clockTicks++;
            if (root.phase !== "running" || !root.panelActive) return;
            root.elapsedMs = Date.now() - root.startedAt;
            if (root.settings.mode === "time" && root.elapsedMs >= root.settings.testLength * 1000) {
                root.elapsedMs = root.settings.testLength * 1000;
                root.finishTest();
            }
        }
    }

    property Timer analyticsTimer: Timer {
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            root.analyticsTicks++;
            if (root.phase === "running" && root.panelActive) root.appendSample();
        }
    }
}
