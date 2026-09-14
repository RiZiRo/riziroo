import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    readonly property bool loading: IslandAiService.status === "loading"
    readonly property bool ready: IslandAiService.status === "ok"
    readonly property bool failed: IslandAiService.status === "failed" || IslandAiService.status === "nokey"
    implicitHeight: root.ready ? 380 : root.failed ? 230 : 218

    // A deliberately small formatting subset. Escape before adding markup:
    // provider text cannot inject HTML, images, or network-loaded resources.
    function answerHtml(text) {
        return StringUtils.escapeHtml(text)
            .replace(/```[^\n]*\n([\s\S]*?)```/g, "<pre>$1</pre>")
            .replace(/\*\*([^*\n]+)\*\*/g, "<b>$1</b>")
            .replace(/`([^`\n]+)`/g, "<tt>$1</tt>")
            .replace(/(^|\n)#{1,6}\s+([^\n]+)/g, "$1<b>$2</b>")
            .replace(/\n/g, "<br>");
    }

    ColumnLayout {
    anchors.fill: parent
    spacing: 12

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        MaterialSymbol {
            text: "smart_toy"
            iconSize: 24
            color: Appearance.colors.colPrimary
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: IslandAiService.modelName
                textFormat: Text.PlainText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            StyledText {
                text: root.loading ? "Thinking…" : root.ready ? "Answer ready"
                    : root.failed ? "Request needs attention" : "Ask a question · Enter to send"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        BusyIndicator {
            running: root.loading
            visible: running
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
        }
    }
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Appearance.colors.colOutlineVariant
    }
    ScrollView {
        id: answerScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        TextArea {
            width: answerScroll.availableWidth
            readOnly: true
            selectByMouse: true
            textFormat: root.ready ? TextEdit.RichText : TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            padding: 0
            background: null
            font.family: Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurface
            selectedTextColor: Appearance.colors.colOnPrimary
            selectionColor: Appearance.colors.colPrimary
            text: root.ready ? root.answerHtml(IslandAiService.result)
                : root.failed ? IslandAiService.error
                : root.loading ? "Your question has been sent. You can stop this request below."
                : "Quick answers, explanations, and writing help.\nType your question above, then press Enter or Ask.\nNothing is sent while you type."
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        RippleButton {
            implicitWidth: 86
            implicitHeight: 32
            buttonRadius: Appearance.rounding.small
            enabled: root.loading || IslandAiService.text.length > 0
            colBackground: Appearance.colors.colPrimaryContainer
            onClicked: root.loading ? IslandAiService.cancel() : IslandAiService.submit()
            contentItem: StyledText {
                text: root.loading ? "Stop" : root.ready || root.failed ? "Retry" : "Ask"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        RippleButton {
            implicitWidth: 80
            implicitHeight: 32
            visible: root.ready
            buttonRadius: Appearance.rounding.small
            onClicked: Quickshell.clipboardText = IslandAiService.result
            contentItem: StyledText {
                text: "Copy"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        Item { Layout.fillWidth: true }
        RippleButton {
            implicitWidth: 126
            implicitHeight: 32
            buttonRadius: Appearance.rounding.small
            onClicked: IslandAiService.openSidebar()
            contentItem: StyledText {
                text: "Open full chat"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        text: "Uses your selected sidebar model · No file or desktop access"
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        elide: Text.ElideRight
    }
    }
}
