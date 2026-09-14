import qs.modules.ii.typingTest
import QtQuick
import Quickshell

// Renders the floating panel offscreen to PNGs so the layout can be reviewed
// without taking over the live shell. Run with:
//   scripts/typingTest/run-harness.sh scripts/typingTest/harness-shot.qml
// The runner creates <harness config>/shots and copies the PNGs out afterwards.
Item {
    id: harness
    width: 1920
    height: 1080

    readonly property string outDir: Quickshell.shellPath("shots")

    TypingTestSurface {
        id: surface
        anchors.fill: parent
        visible: true
    }

    function shoot(name, done) {
        const path = `${harness.outDir}/${name}.png`;
        surface.panelItem.grabToImage(result => {
            console.warn("SHOT " + name + " " + (result.saveToFile(path) ? "ok" : "FAILED") + " " + path);
            if (done) done();
        });
    }

    Timer {
        interval: 1400
        running: true
        onTriggered: {
            surface.settings.language = "english_commonly_misspelled";
            surface.settings.mode = "words";
            surface.settings.testLength = 100;
            surface.settings.keyboardMode = "react";
            surface.restartTest();
            step2.start();
        }
    }

    Timer {
        id: step2
        interval: 600
        onTriggered: harness.shoot("01-ready", () => step3.start())
    }

    Timer {
        id: step3
        interval: 400
        onTriggered: {
            // Type two full words plus a deliberate typo, so both the correct
            // and error colors and the caret offset all show up.
            const words = surface.engine.targetText.split(" ");
            surface.engine.acceptComposition(`${words[0]} ${words[1]} `, 0);
            surface.engine.acceptComposition("zzz", 0);
            step4.start();
        }
    }

    Timer {
        id: step4
        interval: 400
        onTriggered: harness.shoot("02-typing", () => step5.start())
    }

    Timer {
        id: step5
        interval: 300
        onTriggered: {
            surface.settings.keyboardMode = "off";
            surface.settings.mode = "time";
            surface.settings.testLength = 30;
            surface.settings.language = "english";
            surface.restartTest();
            step6.start();
        }
    }

    Timer {
        id: step6
        interval: 600
        onTriggered: harness.shoot("03-no-keyboard", () => step7.start())
    }

    Timer {
        id: step7
        interval: 300
        onTriggered: { surface.openLanguage(); step8.start(); }
    }

    Timer {
        id: step8
        interval: 500
        onTriggered: harness.shoot("04-language", () => step9.start())
    }

    Timer {
        id: step9
        interval: 300
        onTriggered: { surface.closeOverlay(); surface.openSettings(); step10.start(); }
    }

    Timer {
        id: step10
        interval: 600
        onTriggered: harness.shoot("05-settings", () => step11.start())
    }

    Timer {
        id: step11
        interval: 300
        onTriggered: {
            surface.closeOverlay();
            surface.settings.mode = "quote";
            surface.restartTest();
            step12.start();
        }
    }

    Timer {
        id: step12
        interval: 600
        onTriggered: harness.shoot("06-quote", () => step13.start())
    }

    Timer {
        id: step13
        interval: 300
        onTriggered: {
            // A real finish rather than previewResult(), so the graph has samples.
            surface.settings.mode = "words";
            surface.settings.testLength = 10;
            surface.settings.language = "english";
            surface.restartTest();
            typeRun.start();
        }
    }

    // Feed words one per tick so the engine's analytics timer records samples.
    Timer {
        id: typeRun
        interval: 120
        repeat: true
        property int typed: 0
        onTriggered: {
            const words = surface.engine.targetText.split(" ");
            if (typed >= 10 || typed >= words.length) {
                stop();
                surface.engine.finishTest();
                step14.start();
                return;
            }
            surface.engine.acceptComposition(words[typed] + (typed < 9 ? " " : ""), 0);
            typed++;
        }
    }

    Timer {
        id: step14
        interval: 600
        onTriggered: harness.shoot("07-result", () => finish.start())
    }

    Timer {
        id: finish
        interval: 500
        onTriggered: { console.warn("HARNESS DONE failures=0"); Qt.exit(0); }
    }
}
