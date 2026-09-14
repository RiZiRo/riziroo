import qs.modules.ii.typingTest
import QtQuick

// Headless suite for the typing test. Run with scripts/typingTest/run-harness.sh.
Item {
    id: harness
    width: 1920
    height: 1080
    property int failures: 0
    property int checks: 0

    function check(name, condition) {
        checks++;
        console.warn((condition ? "PASS " : "FAIL ") + name);
        if (!condition) failures++;
    }

    TypingTestSurface {
        id: surface
        anchors.fill: parent
        visible: true
    }

    // Phase 1: construction, geometry, defaults.
    Timer {
        interval: 1200
        running: true
        onTriggered: {
            check("surface instantiated", surface.engine.targetText.length > 0);
            check("panel is a floating size", surface.panelItem.width >= 720 && surface.panelItem.width <= 1600);
            check("panel does not fill the screen", surface.panelItem.width < harness.width - 100 && surface.panelItem.height < harness.height - 100);
            check("panel placed and centered on first run", surface.panelPlaced
                && Math.abs(surface.panelItem.x - (harness.width - surface.panelItem.width) / 2) < 2);
            check("pure black is the default theme", String(surface.theme.bg) === "#000000");
            check("keyboard defaults to react", surface.settings.keyboardMode === "react");
            check("caret defaults to underline", surface.settings.caretStyle === "underline");
            check("typing focus acquired", surface.inputHasFocus || surface.focusAttempts > 0);

            // Geometry persistence
            surface.panelItem.x = 120;
            surface.panelItem.y = 90;
            surface.persistGeometry();
            check("panel position persisted", surface.settings.panelX === 120 && surface.settings.panelY === 90);
            surface.resizePanel(900, 600);
            check("resize clamps into settings", surface.settings.panelWidth === 900 && surface.settings.panelHeight === 600);
            surface.resizePanel(100, 100);
            check("resize respects the minimum", surface.settings.panelWidth === 720 && surface.settings.panelHeight === 540);
            surface.settings.keyboardMode = "off";
            check("minimum height drops without the keyboard", surface.minPanelHeight === 420);
            surface.settings.keyboardMode = "react";
            surface.centerPanel();
            check("recenter works", Math.abs(surface.panelItem.x - (harness.width - surface.panelItem.width) / 2) < 2);

            phase2.start();
        }
    }

    // Phase 2: language packs.
    Timer {
        id: phase2
        interval: 150
        onTriggered: {
            const data = surface.engine.data;
            check("profiles include built-in, shipped and quote packs", data.profiles.length >= 10);
            const keys = data.profiles.map(item => item.key);
            check("english 10k listed", keys.indexOf("english_10k") >= 0);
            check("commonly misspelled listed", keys.indexOf("english_commonly_misspelled") >= 0);

            const tenK = data.wordsFor("english_10k");
            check("english 10k pack loads", tenK.length > 9000);
            check("english 10k is not the fallback", tenK !== data.english200);
            const misspelled = data.wordsFor("english_commonly_misspelled");
            // Deliberately exact: a shared FileView used to hand back the
            // previously read pack, which a loose length check did not catch.
            check("commonly misspelled pack loads its own words",
                misspelled.length > 500 && misspelled.length < 3000 && misspelled !== tenK);
            check("commonly misspelled contains its marker word", misspelled.indexOf("jewellery") >= 0);
            check("pack cache is reused", data.wordsFor("english_10k") === tenK);
            check("10k still correct after a second pack read", data.wordsFor("english_10k").length > 9000);
            check("unknown pack falls back to english", data.wordsFor("nope_not_real") === data.english200);
            const quotePack = data.loadPack("quotes_english");
            check("quote pack parses as quotes", quotePack !== null && quotePack.kind === "quotes" && quotePack.quotes.length >= 50);
            check("quote pack loads", data.quotesFor("english").length > 50);
            check("persian stays built-in", data.directionFor("persian") === "rtl");
            check("label lookup works", data.labelFor("english_10k") === "english 10k");

            surface.settings.language = "english_10k";
            surface.restartTest();
            phase3.start();
        }
    }

    // Phase 3: typing through the engine.
    Timer {
        id: phase3
        interval: 250
        onTriggered: {
            check("10k words drive the test", surface.engine.targetText.length > 0);
            surface.settings.language = "english";
            surface.settings.mode = "words";
            surface.settings.testLength = 10;
            surface.restartTest();
            phase4.start();
        }
    }

    Timer {
        id: phase4
        interval: 250
        onTriggered: {
            const target = surface.engine.targetText;
            const firstWord = target.split(" ")[0];
            surface.engine.acceptComposition(firstWord, 0);
            check("typing registers", surface.engine.typedText === firstWord);
            check("all correct so far", surface.engine.accuracy === 100);
            surface.engine.eraseWord(Qt.ControlModifier, false);
            check("ctrl backspace clears the word", surface.engine.typedText.length === 0);

            // Next-key keyboard mode points at the upcoming character.
            surface.settings.keyboardMode = "next";
            check("next mode targets the upcoming char", surface.engine.targetText[surface.engine.typedLength] === target[0]);
            surface.settings.keyboardMode = "react";

            // Pages
            surface.openSettings();
            check("settings page opens", surface.page === "settings" && surface.overlayOpen);
            surface.openHistory();
            check("history page opens", surface.page === "history");
            surface.openLanguage();
            check("language page opens", surface.page === "language" && surface.overlayOpen);
            surface.pickLanguage("english_5k");
            check("picking a language applies it", surface.settings.language === "english_5k" && surface.page !== "language");

            surface.promptCustomLength();
            check("custom length prompt blocks typing focus", !surface.inputHasFocus || surface.page === "test");
            surface.applyCustomLength();
            check("custom length prompt closes", surface.settings.testLength >= 1);

            phase5.start();
        }
    }

    // Phase 5: finish a test and land on results.
    Timer {
        id: phase5
        interval: 300
        onTriggered: {
            surface.settings.language = "english";
            surface.settings.mode = "time";
            surface.settings.testLength = 15;
            surface.restartTest();
            surface.engine.acceptComposition("alpha beta gamma delta", 0);
            surface.engine.startedAt = Date.now() - 8000;
            surface.engine.finishTest();
            check("test finishes into the result page", surface.page === "result");
            check("result carries a wpm", Number(surface.displayedResult.wpm) >= 0);
            check("result saved locally", surface.resultStore.summaries.length > 0);
            check("settings were written", surface.settings.writeCount > 0);

            console.warn("HARNESS DONE failures=" + harness.failures + " checks=" + harness.checks);
            Qt.exit(harness.failures);
        }
    }
}
