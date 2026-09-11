pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property int schemaVersion: 3
    property bool loaded: false
    property int writeCount: 0
    property var summaries: []
    property var details: ({})
    property var weakKeys: ({})
    property var missedWords: ({})
    property string selectedId: ""
    property var selectedDetail: ({})
    readonly property int retentionLimit: 2000
    readonly property string historyPath: Directories.typingTestHistoryPath
    readonly property string dataDir: Directories.typingTestDataDir
    readonly property string indexPath: Directories.typingTestIndexPath
    readonly property string detailsPath: Directories.typingTestDetailsPath

    signal resultSaved(string id)
    signal migrated(int count)

    function makeId(timestamp) {
        const random = Math.floor(Math.random() * 0xffffff).toString(36);
        return `tt-${timestamp.toString(36)}-${random}`;
    }

    function summaryFor(result) {
        return {
            id: result.id, timestamp: result.timestamp, mode: result.mode, length: result.length,
            language: result.language || "english", punctuation: Boolean(result.punctuation),
            numbers: Boolean(result.numbers), difficulty: result.difficulty || "normal",
            trainer: result.trainer || "off", theme: result.theme || "pure_black",
            wpm: Number(result.wpm || 0), rawWpm: Number(result.rawWpm || result.wpm || 0),
            accuracy: Number(result.accuracy ?? 100), consistency: Number(result.consistency ?? 100),
            durationMs: Number(result.durationMs || 0), characters: Number(result.characters || 0),
            failed: Boolean(result.failed), saved: result.saved === undefined ? false : Boolean(result.saved),
            pb: Boolean(result.newPb || result.pb), seed: Number(result.seed || 0)
        };
    }

    function normalizeOld(item, index) {
        const timestamp = Number(item.timestamp || Date.now() - index);
        const id = item.id || makeId(timestamp);
        const detail = Object.assign({version: 1, id, timestamp}, item);
        if (!detail.samples) detail.samples = [];
        if (!detail.events) detail.events = [];
        if (!detail.words) detail.words = [];
        if (!detail.missedWords) detail.missedWords = [];
        if (!detail.slowWords) detail.slowWords = [];
        if (!detail.weakKeys) detail.weakKeys = [];
        return detail;
    }

    function loadPayload(text) {
        try {
            const value = JSON.parse(text || "[]");
            if (Array.isArray(value)) {
                migrateLegacy(value);
                return true;
            }
            if (value && Array.isArray(value.summaries)) {
                summaries = value.summaries.slice(0, retentionLimit);
                weakKeys = value.weakKeys || ({});
                missedWords = value.missedWords || ({});
                loaded = true;
                return true;
            }
        } catch (error) {
            console.warn("Typing history parse failed:", error);
        }
        summaries = [];
        loaded = true;
        return false;
    }

    function migrateLegacy(items) {
        const nextDetails = Object.assign({}, details);
        const nextSummaries = [];
        for (let i = 0; i < items.length; ++i) {
            const detail = normalizeOld(items[i], i);
            nextDetails[detail.id] = detail;
            nextSummaries.push(summaryFor(detail));
        }
        details = nextDetails;
        summaries = nextSummaries.slice(0, retentionLimit);
        loaded = true;
        persistNow();
        migrated(nextSummaries.length);
    }

    function aggregateWeakKeys(result) {
        const state = Object.assign({}, weakKeys);
        const incoming = result.weakKeyState || ({});
        for (const key in incoming) state[key] = incoming[key];
        weakKeys = state;
        const misses = Object.assign({}, missedWords);
        for (const word of (result.missedWords || [])) misses[word] = Number(misses[word] || 0) + 1;
        missedWords = misses;
    }

    function bestFor(result) {
        let best = 0;
        for (const item of summaries) {
            if (item.mode === result.mode && Number(item.length) === Number(result.length)
                && item.language === (result.language || "english")
                && Boolean(item.punctuation) === Boolean(result.punctuation)
                && Boolean(item.numbers) === Boolean(result.numbers)
                && item.difficulty === (result.difficulty || "normal") && !item.failed)
                best = Math.max(best, Number(item.wpm || 0));
        }
        return best;
    }

    function addResult(raw) {
        const timestamp = Number(raw.timestamp || Date.now());
        const result = Object.assign({}, raw, {id: raw.id || makeId(timestamp), timestamp});
        const prior = bestFor(result);
        result.comparablePb = prior;
        result.newPb = !result.failed && result.wpm > prior;
        result.pbDelta = prior > 0 ? result.wpm - prior : 0;
        const map = Object.assign({}, details);
        map[result.id] = result;
        const nextSummaries = [summaryFor(result)].concat(summaries.filter(item => item.id !== result.id));
        const removed = nextSummaries.slice(retentionLimit);
        for (const stale of removed) delete map[stale.id];
        details = map;
        summaries = nextSummaries.slice(0, retentionLimit);
        aggregateWeakKeys(result);
        persistTimer.restart();
        resultSaved(result.id);
        return result;
    }

    function detail(id) {
        return details[id] || ({});
    }

    function select(id) {
        selectedId = id;
        selectedDetail = detail(id);
        return selectedDetail;
    }

    function toggleSaved(id) {
        const map = Object.assign({}, details);
        if (map[id]) map[id] = Object.assign({}, map[id], {saved: !map[id].saved});
        details = map;
        summaries = summaries.map(item => item.id === id ? Object.assign({}, item, {saved: !item.saved}) : item);
        persistTimer.restart();
    }

    function filter(criteria) {
        const value = criteria || ({});
        return summaries.filter(item => {
            if (value.mode && value.mode !== "all" && item.mode !== value.mode) return false;
            if (value.language && value.language !== "all" && item.language !== value.language) return false;
            if (value.difficulty && value.difficulty !== "all" && item.difficulty !== value.difficulty) return false;
            if (value.length && Number(item.length) !== Number(value.length)) return false;
            if (value.punctuation !== undefined && Boolean(item.punctuation) !== Boolean(value.punctuation)) return false;
            if (value.numbers !== undefined && Boolean(item.numbers) !== Boolean(value.numbers)) return false;
            if (value.saved === true && !item.saved) return false;
            if (value.failed === false && item.failed) return false;
            if (value.failed === true && !item.failed) return false;
            if (value.pb === true && !item.pb) return false;
            if (value.since && item.timestamp < value.since) return false;
            return true;
        });
    }

    function aggregates() {
        let time = 0;
        let tests = 0;
        let wpm = 0;
        let accuracy = 0;
        const pbs = ({});
        for (const item of summaries) {
            tests++;
            time += item.durationMs;
            wpm += item.wpm;
            accuracy += item.accuracy;
            const key = `${item.mode}:${item.length}:${item.language}:${item.punctuation}:${item.numbers}:${item.difficulty}`;
            pbs[key] = Math.max(Number(pbs[key] || 0), item.wpm);
        }
        return {
            tests, timeTypedMs: time, averageWpm: tests ? Math.round(wpm / tests) : 0,
            averageAccuracy: tests ? Math.round(accuracy / tests) : 100, pbs,
            weakKeys: Object.keys(weakKeys).map(key => ({key, score: weakKeys[key].score || 0})).sort((a, b) => b.score - a.score).slice(0, 12),
            missedWords: Object.keys(missedWords).map(word => ({word, count: missedWords[word]})).sort((a, b) => b.count - a.count).slice(0, 20)
        };
    }

    function resultSummaryText(result) {
        return `${result.wpm} wpm · ${result.rawWpm} raw · ${result.accuracy}% accuracy · ${result.consistency}% consistency · ${result.mode} ${result.length} · ${result.language}`;
    }

    function persistNow() {
        if (!loaded) return;
        indexFile.setText(JSON.stringify({version: schemaVersion, summaries, weakKeys, missedWords}));
        detailsFile.setText(JSON.stringify({version: schemaVersion, results: details}));
        writeCount++;
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", dataDir]);
        indexFile.reload();
        detailsFile.reload();
    }

    property Timer persistTimer: Timer { interval: 250; repeat: false; onTriggered: root.persistNow() }

    property FileView indexFile: FileView {
        path: Qt.resolvedUrl(root.indexPath)
        onLoaded: root.loadPayload(indexFile.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) legacyFile.reload();
            else { root.summaries = []; root.loaded = true; }
        }
    }

    property FileView detailsFile: FileView {
        path: Qt.resolvedUrl(root.detailsPath)
        onLoaded: {
            try {
                const value = JSON.parse(detailsFile.text());
                root.details = value.results || ({});
            } catch (error) { root.details = ({}); }
        }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.details = ({}); }
    }

    property FileView legacyFile: FileView {
        path: Qt.resolvedUrl(root.historyPath)
        onLoaded: root.loadPayload(legacyFile.text())
        onLoadFailed: error => {
            root.summaries = [];
            root.details = ({});
            root.loaded = true;
            root.persistNow();
        }
    }
}
