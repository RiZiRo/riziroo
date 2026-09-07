pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

/**
 * The best cover art each player has offered for the track it is playing.
 *
 * One track does not mean one picture. Firefox publishes the first artwork the page lists -- for
 * YouTube Music a 544x544 cover -- and then replaces it a second later with the 60x60 thumbnail
 * from the same list, which is what a widget would otherwise keep showing, blown up, for the rest
 * of the song. So every picture a player offers is copied to disk and measured, and only the
 * largest one seen for the current track is published.
 *
 * Copying is not only about caching: Firefox deletes the file it published as soon as it publishes
 * the next one, so the better picture exists for only as long as it takes to copy it. That is also
 * why Directories.mediaArt survives across runs while Directories.coverArt is wiped.
 *
 * Snapshots are named after their own contents, never after their source URL, because a URL is no
 * identity here: Firefox writes <n>_<counter>.png and starts the counter over every browser
 * session, so a URL seen today names a file it wrote yesterday for something else entirely.
 *
 * What comes out of urlFor() is a file:// URL, which is what every media widget's own download step
 * already passes through untouched.
 */
Singleton {
    id: root

    // dbusName -> { key, src, path, url, pixels }: the best picture so far for that player's track
    property var bestByPlayer: ({})
    // content path -> pixels, so the same picture is never measured twice
    property var pixelsByPath: ({})
    // http(s) url -> content path. Only remote URLs are memoised: those keep meaning one picture,
    // unlike the local files a browser writes and then reuses the names of.
    property var pathByUrl: ({})
    // dbusName -> "key\nsrc" already dealt with, so a picture that lost the size comparison is not
    // fetched again every time its player mentions it
    property var seenByPlayer: ({})

    /**
     * The art to show for a player, or "" when nothing has been measured for its current track
     * yet, which is also what a track with no art at all reports.
     */
    function urlFor(player: MprisPlayer): string {
        if (!player)
            return "";
        const best = root.bestByPlayer[player.dbusName];
        return (best && best.key === root.keyFor(player)) ? best.url : "";
    }

    // Art and title arrive as separate property updates, and not always in that order, so pictures
    // are filed under the track they were paired with rather than assumed to belong to the current
    // one. The album is deliberately left out: players fill it in a beat after the rest, and a key
    // that changes between two pictures of the same track defeats the size comparison in adopt().
    function keyFor(player: MprisPlayer): string {
        return player ? `${player.trackTitle} ${player.trackArtist}` : "";
    }

    function isRemote(url: string): bool {
        return url.startsWith("http://") || url.startsWith("https://");
    }

    function consider(player: MprisPlayer): void {
        const url = player?.trackArtUrl ?? "";
        if (url.length === 0)
            return;
        const name = player.dbusName;
        const key = root.keyFor(player);
        if (root.seenByPlayer[name] === `${key}\n${url}`)
            return;
        const known = root.pathByUrl[url];
        if (known !== undefined) {
            root.remember(name, key, url);
            root.adopt(name, key, url, known, root.pixelsByPath[known] ?? 0);
            return;
        }
        if (root.pending(name, key, url))
            return;
        root.queue = [...root.queue, { name: name, key: key, src: url, path: "" }];
        root.pump();
    }

    function pending(name: string, key: string, src: string): bool {
        const same = job => !!job && job.name === name && job.key === key && job.src === src;
        return same(root.job) || root.queue.some(same);
    }

    function remember(name: string, key: string, src: string): void {
        root.seenByPlayer = Object.assign({}, root.seenByPlayer, { [name]: `${key}\n${src}` });
    }
    function adopt(name: string, key: string, src: string, path: string, pixels: int): void {
        const best = root.bestByPlayer[name];
        // The whole point: a smaller picture of a track already shown at a better size is no update.
        // Equal sizes do replace, because two same-sized pictures for one track means the earlier one
        // was almost certainly the previous track's art, filed here while the title had changed and
        // the art URL had not caught up yet.
        if (best && best.key === key && best.pixels > pixels)
            return;
        root.bestByPlayer = Object.assign({}, root.bestByPlayer, {
            [name]: { key: key, src: src, path: path, pixels: pixels, url: `file://${path}` }
        });
    }

    // Copies and measurements run one at a time. Art changes a couple of times per track, so a queue
    // costs nothing here, and it keeps the single copier and the single probe below from being handed
    // a second job while the first is still in flight.
    property var queue: []
    property var job: null

    // The picture is stored under the md5 of its own contents, so two different pictures cannot end
    // up sharing a name however their source URLs are reused. Everything the script needs arrives as
    // an argument rather than pasted into it, so a quote in a URL cannot be read as shell syntax.
    readonly property string copyScript: `set -e
dir="$1"; url="$2"; local="$3"
mkdir -p "$dir"
tmp=$(mktemp "$dir/.fetch.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ -n "$local" ]; then cp -f -- "$local" "$tmp"; else curl -sSL --max-time 20 "$url" -o "$tmp"; fi
[ -s "$tmp" ]
name=$(md5sum < "$tmp" | cut -d' ' -f1)
mv -f "$tmp" "$dir/$name"
printf '%s' "$dir/$name"`

    function pump(): void {
        if (root.job || root.queue.length === 0)
            return;
        root.job = root.queue[0];
        root.queue = root.queue.slice(1);
        copier.command = ["bash", "-c", root.copyScript, "mediaart", Directories.mediaArt, root.job.src,
            root.job.src.startsWith("file://") ? FileUtils.trimFileProtocol(root.job.src) : ""];
        copier.running = true;
        jobTimeout.restart();
    }
    // Where the picture ended up is a name the script worked out from the contents, so the script
    // printing it is the only way to learn it
    function copied(path: string): void {
        if (!root.job)
            return;
        if (path.length === 0) {
            root.finish("", 0);
            return;
        }
        root.job.path = path;
        probe.source = "";
        probe.source = `file://${path}`;
        probeTimeout.restart();
    }

    function finish(path: string, pixels: int): void {
        const job = root.job;
        root.job = null;
        jobTimeout.stop();
        probeTimeout.stop();
        if (job) {
            root.remember(job.name, job.key, job.src);
            if (path.length > 0) {
                if (pixels > 0)
                    root.pixelsByPath = Object.assign({}, root.pixelsByPath, { [path]: pixels });
                if (root.isRemote(job.src))
                    root.pathByUrl = Object.assign({}, root.pathByUrl, { [job.src]: path });
                // Adopted even when unmeasured: a size that could not be read should leave whatever
                // the track already had in place rather than blank the art out
                root.adopt(job.name, job.key, job.src, path, pixels);
            }
        }
        root.pump();
    }

    Process {
        id: copier
        // An empty collector means the script failed, and the stream closing is the first moment both
        // that and the printed path are settled
        stdout: StdioCollector {
            id: copierOutput
            onStreamFinished: root.copied(copierOutput.text.trim().split("\n").pop().trim())
        }
    }
    Image {
        id: probe
        // Nothing draws this. An Image with sourceSize left alone reports the picture's own pixel size
        // once it has loaded, which is the only thing being asked of it.
        visible: false
        asynchronous: true
        cache: false
        onStatusChanged: {
            if (probe.status === Image.Loading || probe.status === Image.Null || !root.job)
                return;
            root.finish(root.job.path, probe.status === Image.Ready
                ? probe.sourceSize.width * probe.sourceSize.height : 0);
        }
    }

    Timer {
        id: probeTimeout
        // A picture that never resolves either way must not stall every track after it
        interval: 4000
        onTriggered: {
            probe.source = "";
            root.finish(root.job?.path ?? "", 0);
        }
    }

    Timer {
        id: jobTimeout
        // Covers a copy that never finishes at all: curl has its own limit, a stuck cp does not
        interval: 25000
        onTriggered: {
            copier.running = false;
            root.finish("", 0);
        }
    }

    Timer {
        id: settle
        // One metadata update reaches QML as several separate property changes, and the art URL can
        // still be the previous track's when the title has already changed. Reading the two together
        // only once they have stopped moving is what keeps a picture off the wrong track.
        interval: 200
        onTriggered: {
            for (const player of Mpris.players.values)
                root.consider(player);
        }
    }

    Instantiator {
        model: Mpris.players

        Connections {
            required property MprisPlayer modelData
            target: modelData
            ignoreUnknownSignals: true

            function onTrackArtUrlChanged(): void { settle.restart(); }
            function onTrackTitleChanged(): void { settle.restart(); }
            function onPostTrackChanged(): void { settle.restart(); }

            Component.onCompleted: settle.restart()
        }
    }
}
