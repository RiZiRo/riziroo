pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick

Item {
    id: root
    property var samples: []
    property color mainColor: "#eeeeee"
    property color rawColor: "#777777"
    property color burstColor: "#e2b714"
    property color errorColor: "#ca4754"
    property color mutedColor: "#444444"
    property bool showWpm: true
    property bool showRaw: true
    property bool showBurst: true
    property bool showErrors: true
    property bool showPb: true
    property real personalBest: 0
    property int hoverIndex: -1

    function maximum() {
        let value = Math.max(20, personalBest);
        for (const sample of samples) value = Math.max(value, sample.wpm || 0, sample.raw || 0, sample.burst || 0);
        return Math.ceil(value / 20) * 20;
    }

    function point(index, field) {
        if (samples.length === 0) return Qt.point(0, height);
        const left = 42;
        const right = width - 16;
        const top = 16;
        const bottom = height - 28;
        const x = samples.length === 1 ? (left + right) / 2 : left + index * (right - left) / (samples.length - 1);
        const y = bottom - Number(samples[index][field] || 0) / maximum() * (bottom - top);
        return Qt.point(x, y);
    }

    function drawLine(ctx, field, color, dashed) {
        if (samples.length === 0) return;
        ctx.strokeStyle = color;
        ctx.lineWidth = field === "wpm" ? 2.5 : 1.5;
        ctx.setLineDash(dashed ? [5, 5] : []);
        ctx.beginPath();
        for (let i = 0; i < samples.length; ++i) {
            const p = point(i, field);
            if (i === 0) ctx.moveTo(p.x, p.y); else ctx.lineTo(p.x, p.y);
        }
        ctx.stroke();
        ctx.setLineDash([]);
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const left = 42;
            const right = width - 16;
            const top = 16;
            const bottom = height - 28;
            const max = root.maximum();
            ctx.font = "11px monospace";
            ctx.textAlign = "right";
            ctx.textBaseline = "middle";
            for (let value = 0; value <= max; value += Math.max(20, max / 4)) {
                const y = bottom - value / max * (bottom - top);
                ctx.strokeStyle = Qt.alpha(root.mutedColor, 0.42);
                ctx.lineWidth = 1;
                ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke();
                ctx.fillStyle = root.mutedColor;
                ctx.fillText(String(Math.round(value)), left - 7, y);
            }
            if (root.showPb && root.personalBest > 0) {
                const y = bottom - root.personalBest / max * (bottom - top);
                ctx.strokeStyle = Qt.alpha(root.mainColor, 0.45);
                ctx.setLineDash([7, 6]);
                ctx.beginPath(); ctx.moveTo(left, y); ctx.lineTo(right, y); ctx.stroke();
                ctx.setLineDash([]);
            }
            if (root.showRaw) root.drawLine(ctx, "raw", root.rawColor, true);
            if (root.showBurst) root.drawLine(ctx, "burst", root.burstColor, false);
            if (root.showWpm) root.drawLine(ctx, "wpm", root.mainColor, false);
            if (root.showErrors) {
                for (let i = 0; i < root.samples.length; ++i) {
                    if (Number(root.samples[i].errors || 0) <= 0) continue;
                    const p = root.point(i, "wpm");
                    ctx.fillStyle = root.errorColor;
                    ctx.beginPath(); ctx.arc(p.x, bottom - 4, 3.5, 0, Math.PI * 2); ctx.fill();
                }
            }
            if (root.hoverIndex >= 0 && root.hoverIndex < root.samples.length) {
                const p = root.point(root.hoverIndex, "wpm");
                ctx.strokeStyle = Qt.alpha(root.mainColor, 0.35);
                ctx.beginPath(); ctx.moveTo(p.x, top); ctx.lineTo(p.x, bottom); ctx.stroke();
                ctx.fillStyle = root.mainColor;
                ctx.beginPath(); ctx.arc(p.x, p.y, 4, 0, Math.PI * 2); ctx.fill();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: mouse => {
            if (root.samples.length === 0) return;
            const ratio = Math.max(0, Math.min(1, (mouse.x - 42) / Math.max(1, root.width - 58)));
            root.hoverIndex = Math.round(ratio * (root.samples.length - 1));
            canvas.requestPaint();
        }
        onExited: { root.hoverIndex = -1; canvas.requestPaint(); }
    }

    Rectangle {
        visible: root.hoverIndex >= 0 && root.hoverIndex < root.samples.length
        anchors.top: parent.top
        anchors.right: parent.right
        color: "#e6121212"
        radius: 7
        width: tooltip.implicitWidth + 20
        height: 31
        StyledText {
            id: tooltip
            anchors.centerIn: parent
            text: root.hoverIndex < 0 ? "" : `${((root.samples[root.hoverIndex]?.t || 0) / 1000).toFixed(0)}s  ${root.samples[root.hoverIndex]?.wpm || 0} wpm  ${root.samples[root.hoverIndex]?.burst || 0} burst`
            color: root.mainColor
            font.family: Appearance.font.family.monospace
            font.pixelSize: 11
        }
    }

    onSamplesChanged: canvas.requestPaint()
    onShowWpmChanged: canvas.requestPaint()
    onShowRawChanged: canvas.requestPaint()
    onShowBurstChanged: canvas.requestPaint()
    onShowErrorsChanged: canvas.requestPaint()
    onShowPbChanged: canvas.requestPaint()
    onPersonalBestChanged: canvas.requestPaint()
}
