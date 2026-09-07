pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * AmneziaVPN status and control.
 *
 * Two sources, both usable without privileges:
 *  - /sys/class/net/<iface>/statistics for instant up/down state and byte counters
 *  - the helper daemon's local socket (/run/amneziavpn/daemon.socket, world-writable)
 *    which answers {"type":"status"} with connected/rxBytes/txBytes/date/gateway and
 *    accepts {"type":"deactivate"} to drop the tunnel.
 *
 * Connecting launches the GUI by default (it auto-connects). The daemon can also be
 * asked to bring the tunnel up directly, but that request is assembled from field names
 * read out of the helper binary and is untested, so it sits behind `daemonConnect`.
 */
Singleton {
    id: root

    readonly property string vpnConfigPath: FileUtils.trimFileProtocol(`${Directories.config}/AmneziaVPN.ORG/AmneziaVPN.conf`)
    readonly property var options: Config.options?.background?.widgets?.amneziaVpn ?? null
    readonly property bool daemonControlAllowed: root.options?.daemonControl ?? true
    // Off by default: connecting through the daemon is built from field names found in
    // the helper binary and has never been exercised, so opt in deliberately.
    readonly property bool daemonConnectAllowed: root.options?.daemonConnect ?? false

    // Which interfaces count as the Amnezia tunnel. Narrow by default so other tunnels
    // (Clash, plain WireGuard, containers) are not mistaken for a VPN connection.
    readonly property string ifacePattern: {
        const raw = root.options?.interfacePrefixes ?? "amn* awg*";
        const parts = raw.split(/[\s,|]+/)
            .map(p => p.replace(/[^A-Za-z0-9*?_.\-]/g, ""))
            .filter(p => p.length > 0);
        return parts.length > 0 ? parts.join("|") : "amn*";
    }

    // Live state
    property string interfaceName: ""
    property bool daemonConnected: false
    property bool daemonReachable: false
    readonly property bool connected: root.interfaceName.length > 0 || root.daemonConnected
    property bool appRunning: false
    property bool busy: false

    property real rxBytes: 0
    property real txBytes: 0
    property real rxSpeed: 0 // bytes/sec
    property real txSpeed: 0

    property string serverGateway: ""
    property var connectedSince: null
    property int uptimeTick: 0
    readonly property string uptimeText: {
        root.uptimeTick; // re-evaluate once per poll
        if (!root.connected || !root.connectedSince)
            return "";
        const secs = Math.max(0, Math.floor((Date.now() - root.connectedSince.getTime()) / 1000));
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        const s = secs % 60;
        const pad = n => (n < 10 ? "0" + n : "" + n);
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
    }

    // Server metadata from AmneziaVPN's own settings file
    property string serverName: ""
    property string serverHost: ""
    property string containerName: ""
    // The AmneziaWG/WireGuard parameters of the selected server, used to build an
    // "activate" request for the helper daemon. Never displayed.
    property var lastConfig: null
    property string lastError: ""

    readonly property string protocolName: {
        const c = root.containerName;
        if (c.includes("awg")) return "AmneziaWG";
        if (c.includes("wireguard")) return "WireGuard";
        if (c.includes("cloak")) return "OpenVPN + Cloak";
        if (c.includes("openvpn")) return "OpenVPN";
        if (c.includes("shadowsocks")) return "Shadowsocks";
        if (c.includes("xray")) return "XRay";
        if (c.includes("ipsec")) return "IKEv2";
        if (c.includes("socks")) return "SOCKS5";
        if (c.includes("sftp")) return "SFTP";
        const i = root.interfaceName;
        if (i.startsWith("amn") || i.startsWith("awg")) return "AmneziaWG";
        if (i.startsWith("wg")) return "WireGuard";
        if (i.startsWith("tun")) return "OpenVPN";
        return "";
    }

    readonly property string statusText: root.busy
        ? (root.connected ? Translation.tr("Disconnecting…") : Translation.tr("Connecting…"))
        : (root.connected ? Translation.tr("Connected") : Translation.tr("Disconnected"))

    // What the primary button will actually do, so the widget can label it honestly.
    // Connecting means launching the app (it auto-connects); if it is already running
    // there is no way to tell it to connect, so the click just focuses its window.
    readonly property string actionText: {
        if (root.busy)
            return Translation.tr("Working…");
        if (root.connected)
            return Translation.tr("Disconnect");
        if (root.daemonConnectAllowed)
            return Translation.tr("Connect");
        return root.appRunning ? Translation.tr("Open app") : Translation.tr("Connect");
    }

    function formatBytes(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"];
        let value = Math.max(0, bytes);
        let unit = 0;
        while (value >= 1024 && unit < units.length - 1) {
            value /= 1024;
            unit++;
        }
        const decimals = (unit === 0 || value >= 100) ? 0 : (value >= 10 ? 1 : 2);
        return value.toFixed(decimals) + " " + units[unit];
    }

    function formatSpeed(bytesPerSec) {
        return root.formatBytes(bytesPerSec) + "/s";
    }

    property real lastPollTime: 0

    function applyPoll(raw) {
        const parts = raw.trim().split("|");
        if (parts.length < 4)
            return;
        root.uptimeTick++;
        const iface = parts[0];
        const rx = parseFloat(parts[1]) || 0;
        const tx = parseFloat(parts[2]) || 0;
        root.appRunning = parts[3] === "1";

        const now = Date.now();
        const dt = root.lastPollTime > 0 ? (now - root.lastPollTime) / 1000 : 0;
        root.lastPollTime = now;

        if (iface !== root.interfaceName) {
            // Tunnel came up, went down or switched protocol
            root.interfaceName = iface;
            root.rxSpeed = 0;
            root.txSpeed = 0;
            if (iface.length === 0)
                root.connectedSince = null;
            root.busy = false;
            busyTimeout.stop();
            statusPoll.restart();
        } else if (dt > 0 && iface.length > 0 && rx >= root.rxBytes && tx >= root.txBytes) {
            root.rxSpeed = (rx - root.rxBytes) / dt;
            root.txSpeed = (tx - root.txBytes) / dt;
        }
        root.rxBytes = rx;
        root.txBytes = tx;
        if (iface.length === 0) {
            root.rxSpeed = 0;
            root.txSpeed = 0;
        }
    }

    Process {
        id: pollProc
        command: ["sh", "-c",
            "i=\"\"; for n in /sys/class/net/*; do b=${n##*/}; case \"$b\" in " + root.ifacePattern + ") i=\"$b\"; break;; esac; done; "
            + "r=0; t=0; if [ -n \"$i\" ]; then read r < \"/sys/class/net/$i/statistics/rx_bytes\" 2>/dev/null; read t < \"/sys/class/net/$i/statistics/tx_bytes\" 2>/dev/null; fi; "
            + "a=0; pgrep -x AmneziaVPN >/dev/null 2>&1 && a=1; "
            + "echo \"$i|$r|$t|$a\""]
        stdout: StdioCollector {
            id: pollCollector
            onStreamFinished: root.applyPoll(pollCollector.text)
        }
    }

    Timer {
        running: true
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!pollProc.running)
                pollProc.running = true;
        }
    }

    // Authoritative state from the helper daemon: connection flag, tunnel counters,
    // when the tunnel came up, and the server address actually in use.
    Process {
        id: statusProc
        command: ["sh", "-c",
            "s=/run/amneziavpn/daemon.socket; [ -S \"$s\" ] || s=/var/run/amneziavpn/daemon.socket; "
            + "[ -S \"$s\" ] || exit 1; command -v socat >/dev/null 2>&1 || exit 1; "
            + "{ printf '{\"type\":\"status\"}\\n'; sleep 1; } | socat -t2 - UNIX-CONNECT:\"$s\" 2>/dev/null | grep -m1 '\"type\"'"]
        stdout: StdioCollector {
            id: statusCollector
            onStreamFinished: root.applyStatus(statusCollector.text)
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.daemonReachable = false;
        }
    }

    Timer {
        id: statusPoll
        running: true
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProc.running)
                statusProc.running = true;
        }
    }

    function applyStatus(raw) {
        const line = raw.trim();
        if (line.length === 0 || line.charAt(0) !== "{") {
            root.daemonReachable = false;
            return;
        }
        try {
            const s = JSON.parse(line);
            root.daemonReachable = true;
            root.daemonConnected = s.connected === true;
            if (typeof s.serverIpv4Gateway === "string")
                root.serverGateway = s.serverIpv4Gateway;
            if (typeof s.date === "string") {
                const started = new Date(s.date);
                root.connectedSince = isNaN(started.getTime()) ? null : started;
            }
            if (!root.daemonConnected)
                root.connectedSince = null;
        } catch (e) {
            root.daemonReachable = false;
        }
    }

    // Assemble a daemon "activate" request from the selected server's tunnel parameters.
    // Field names follow the Mozilla VPN daemon protocol that AmneziaVPN's helper derives
    // from, plus AmneziaWG's obfuscation parameters.
    function buildActivatePayload() {
        const c = root.lastConfig;
        if (!c)
            return null;
        const addrs = String(c.client_ip ?? "").split(",").map(a => a.trim()).filter(a => a.length > 0);
        const v4 = addrs.find(a => !a.includes(":")) ?? "";
        const v6 = addrs.find(a => a.includes(":")) ?? "";
        if (v4.length === 0 && v6.length === 0)
            return null;

        const cidrs = Array.isArray(c.allowed_ips) && c.allowed_ips.length > 0
            ? c.allowed_ips
            : ["0.0.0.0/0", "::/0"];
        const ranges = cidrs.map(cidr => {
            const bits = String(cidr).split("/");
            const isIpv6 = bits[0].includes(":");
            return {
                address: bits[0],
                range: parseInt(bits[1] ?? (isIpv6 ? "128" : "32"), 10),
                isIpv6: isIpv6
            };
        });

        let dns = "";
        const dnsMatch = String(c.config ?? "").match(/^DNS\s*=\s*(.+)$/m);
        if (dnsMatch)
            dns = dnsMatch[1].split(",")[0].trim();
        if (dns.length === 0)
            dns = "1.1.1.1";

        const host = String(c.hostName ?? root.serverHost);
        const payload = {
            "type": "activate",
            "hopindex": 0,
            "privateKey": c.client_priv_key ?? "",
            "deviceIpv4Address": v4,
            "deviceIpv6Address": v6,
            "serverPublicKey": c.server_pub_key ?? "",
            "serverIpv4AddrIn": host,
            "serverIpv6AddrIn": "",
            "serverPort": parseInt(c.port ?? 0, 10),
            "serverIpv4Gateway": root.serverGateway.length > 0 ? root.serverGateway : host,
            "serverIpv6Gateway": "",
            "dnsServer": dns,
            "allowedIPAddressRanges": ranges,
            "excludedAddresses": [],
            "vpnDisabledApps": [],
            "mtu": parseInt(c.mtu ?? 1280, 10),
            "persistentKeepalive": parseInt(c.persistent_keep_alive ?? 0, 10)
        };
        const junk = {
            "Jc": "jc", "Jmin": "jmin", "Jmax": "jmax",
            "S1": "s1", "S2": "s2", "S3": "s3", "S4": "s4",
            "H1": "h1", "H2": "h2", "H3": "h3", "H4": "h4",
            "I1": "i1", "I2": "i2", "I3": "i3", "I4": "i4", "I5": "i5"
        };
        for (const key in junk) {
            if (c[key] !== undefined && String(c[key]).length > 0)
                payload[junk[key]] = c[key];
        }
        return payload;
    }

    function openApp() {
        Quickshell.execDetached(["sh", "-c",
            "command -v AmneziaVPN >/dev/null 2>&1 && exec AmneziaVPN || exec /opt/AmneziaVPN/bin/AmneziaVPN"]);
    }

    function connectVpn() {
        if (root.connected)
            return;
        root.lastError = "";
        if (root.daemonConnectAllowed) {
            const payload = root.buildActivatePayload();
            if (payload) {
                root.busy = true;
                busyTimeout.restart();
                activateProc.payload = JSON.stringify(payload);
                activateProc.running = true;
                return;
            }
            root.lastError = Translation.tr("Tunnel parameters unavailable");
        }
        // Only a fresh launch connects on its own; an already-running app just gets focus,
        // so don't pretend to be busy in that case.
        if (!root.appRunning) {
            root.busy = true;
            busyTimeout.restart();
        }
        root.openApp();
    }

    function disconnectVpn() {
        if (!root.connected)
            return;
        root.busy = true;
        busyTimeout.restart();
        if (root.daemonControlAllowed) {
            deactivateProc.running = true;
        } else {
            root.busy = false;
            root.openApp();
        }
    }

    function toggle() {
        if (root.busy)
            return;
        if (root.connected)
            root.disconnectVpn();
        else
            root.connectVpn();
    }

    function applyActivateReply(raw) {
        const text = raw.trim();
        console.log("[AmneziaVpn] activate reply:", text);
        if (text.length === 0) {
            root.lastError = Translation.tr("No reply from the helper");
            return;
        }
        try {
            const line = text.split("\n").find(l => l.trim().startsWith("{")) ?? "";
            const reply = JSON.parse(line);
            if (reply.connected === true) {
                root.lastError = "";
                root.daemonConnected = true;
            } else {
                root.lastError = String(reply.error ?? reply.message ?? Translation.tr("Helper refused the request"));
            }
        } catch (e) {
            root.lastError = Translation.tr("Unexpected reply from the helper");
        }
        statusPoll.restart();
    }

    Process {
        id: activateProc
        property string payload: ""
        command: ["sh", "-c",
            "s=/run/amneziavpn/daemon.socket; [ -S \"$s\" ] || s=/var/run/amneziavpn/daemon.socket; "
            + "[ -S \"$s\" ] || exit 1; command -v socat >/dev/null 2>&1 || exit 1; "
            + "{ printf '%s\\n' \"$1\"; sleep 2; } | socat -t3 - UNIX-CONNECT:\"$s\" 2>/dev/null",
            "amneziavpn-activate", activateProc.payload]
        stdout: StdioCollector {
            id: activateCollector
            onStreamFinished: root.applyActivateReply(activateCollector.text)
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = Translation.tr("Helper daemon unreachable");
                root.busy = false;
                root.openApp();
            }
            statusPoll.restart();
        }
    }

    Process {
        id: deactivateProc
        command: ["sh", "-c",
            "s=/run/amneziavpn/daemon.socket; [ -S \"$s\" ] || s=/var/run/amneziavpn/daemon.socket; "
            + "[ -S \"$s\" ] || exit 1; command -v socat >/dev/null 2>&1 || exit 1; "
            + "{ printf '{\"type\":\"deactivate\"}\\n'; sleep 1; } | socat -t2 - UNIX-CONNECT:\"$s\" >/dev/null 2>&1"]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.daemonConnected = false;
                root.connectedSince = null;
            } else {
                console.log("[AmneziaVpn] helper daemon unreachable, opening the app instead");
                root.busy = false;
                root.openApp();
            }
            statusPoll.restart();
        }
    }

    Timer {
        id: busyTimeout
        interval: 20000
        onTriggered: root.busy = false
    }

    // QSettings escapes its string values; undo that so the blob parses as JSON
    function unescapeQtSetting(s) {
        let out = "";
        for (let i = 0; i < s.length; i++) {
            const c = s.charAt(i);
            if (c !== "\\") {
                out += c;
                continue;
            }
            const n = s.charAt(++i);
            switch (n) {
            case "n": out += "\n"; break;
            case "t": out += "\t"; break;
            case "r": out += "\r"; break;
            case "0": out += "\0"; break;
            case "x": {
                out += String.fromCharCode(parseInt(s.substr(i + 1, 2), 16));
                i += 2;
                break;
            }
            default: out += n;
            }
        }
        return out;
    }

    function parseVpnConfig(text) {
        try {
            const idMatch = text.match(/^defaultServerId=(.*)$/m);
            const defaultId = idMatch ? idMatch[1].trim() : "";
            const blobMatch = text.match(/^serversList="@ByteArray\((.*)\)"\s*$/m);
            if (!blobMatch)
                return;
            const servers = JSON.parse(root.unescapeQtSetting(blobMatch[1]));
            if (!Array.isArray(servers) || servers.length === 0)
                return;
            const server = servers.find(s => s.storageServerId === defaultId) ?? servers[0];
            root.serverName = server.description ?? "";
            root.serverHost = server.hostName ?? "";
            root.containerName = server.defaultContainer ?? "";
            root.lastConfig = root.extractLastConfig(server);
        } catch (e) {
            console.log("[AmneziaVpn] Could not parse AmneziaVPN.conf:", e);
        }
    }

    // Pull the protocol block of the server's default container and parse its last_config
    function extractLastConfig(server) {
        try {
            const container = server.defaultContainer ?? "";
            const entry = (server.containers ?? []).find(c => c.container === container);
            if (!entry)
                return null;
            for (const key in entry) {
                if (key === "container")
                    continue;
                const raw = entry[key]?.last_config;
                if (typeof raw === "string" && raw.length > 0)
                    return JSON.parse(raw);
            }
        } catch (e) {
            console.log("[AmneziaVpn] Could not read the server's tunnel parameters:", e);
        }
        return null;
    }

    FileView {
        id: vpnConfigView
        path: Qt.resolvedUrl(root.vpnConfigPath)
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseVpnConfig(vpnConfigView.text())
        onLoadFailed: {
            root.serverName = "";
            root.serverHost = "";
            root.containerName = "";
        }
    }
}
