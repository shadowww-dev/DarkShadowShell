pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// V6.10 Vibe (Settings > Appearance > Vibe; ~/.config/rice/vibe.json, rice-vibe): the desktop goes with your music.
//   cover   while music plays, the shell takes its colors from the cover (VibeCover.qml finds them); a pause of
//           more than a few seconds gives your theme back
//   borders the window borders take them too (Hyprland; not when you picked your own border colors)
//   barStyle / barSize  the visualizer on the bar: bars | liquid | dots, small | medium | wide
//   edge    a soft light along the bottom of the screen that moves with the music (VibeEdge.qml), glow | liquid
//   island  the island's edge breathes with the beat
//   beat    the moving wallpapers move with the music (rice-scene reads vibe.json itself)
//   lock    a ring around the cover on the lock screen (the lock screen reads vibe.json itself)
//   weather rain, snow, a storm or fog on the desktop when it is like that outside (VibeWeather.qml);
//           weatherMode (V6.11): live (the weather outside) or always rain | snow | storm | fog | petals | fireflies
//   lyrics  (V6.11) the line being sung, big, low on the desktop (VibeLyrics.qml), lyricsSize small|medium|large
// level: the beat (the low notes), 0..1, rises at once and falls softly; only worked out while something
// shows it (need > 0) and music plays.
Singleton {
    id: vb
    property bool cover: true
    // V6.84: the cover's colors belong to "Auto" (Settings > Appearance > Color theme). A scheme you picked
    // (grey, ocean, ...) is yours: a song does not repaint the shell on top of it
    property string colorMode: "auto"
    FileView {
        path: Quickshell.env("HOME") + "/.config/rice/color-mode"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { const t = text().trim(); vb.colorMode = t !== "" ? t.split("\n")[0] : "auto" }
    }
    property bool borders: true
    property string barStyle: "liquid"
    property string barSize: "medium"
    property bool edge: false
    property string edgeStyle: "glow"
    property real edgeHeight: 0.16
    property bool island: true
    property bool weather: false
    property string weatherMode: "live"
    property bool lyrics: false
    property string lyricsSize: "medium"
    property real lyricsY: 0.16
    readonly property var modes: ["live", "rain", "snow", "storm", "fog", "petals", "fireflies"]
    property string tryWeather: ""        // a minute of rain, snow ... to see it (Settings > Vibe > Try)
    // what falls on the desktop now: what you try, else what you picked, else the weather outside
    readonly property string fall: tryWeather !== "" ? tryWeather : (!weather ? "" : (weatherMode !== "live" ? weatherMode : sky))
    // the weather outside, for VibeWeather: rain | storm | snow | fog | "" (shell.qml asks rice-weather)
    property string sky: ""
    property bool skyHeavy: false
    function skyOf(cond) {
        const c = (cond || "").toLowerCase()
        skyHeavy = /heavy|torrential|blizzard|moderate or heavy/.test(c)
        if (/thunder/.test(c)) return "storm"
        if (/snow|sleet|blizzard|ice pellets|freezing/.test(c)) return "snow"
        if (/rain|drizzle|shower/.test(c)) return "rain"
        if (/fog|mist|haze/.test(c)) return "fog"
        return ""
    }

    function apply(j) {
        cover = j.cover !== false
        borders = j.borders !== false
        barStyle = ["bars", "liquid", "dots"].indexOf(j.bar) >= 0 ? j.bar : "liquid"
        barSize = ["small", "medium", "wide"].indexOf(j.bar_size) >= 0 ? j.bar_size : "medium"
        edge = j.edge === true
        edgeStyle = j.edge_style === "liquid" ? "liquid" : "glow"
        edgeHeight = j.edge_height !== undefined ? Math.max(0.06, Math.min(0.4, Number(j.edge_height) || 0.16)) : 0.16
        island = j.island !== false
        weather = j.weather === true
        weatherMode = modes.indexOf(j.weather_mode) >= 0 ? j.weather_mode : "live"
        lyrics = j.lyrics === true
        lyricsSize = ["small", "medium", "large"].indexOf(j.lyrics_size) >= 0 ? j.lyrics_size : "medium"
    }

    // ---------- the cover's colors ----------
    property color tint: "#000000"
    property color tint2: "#000000"
    property bool tintOk: false
    property string tintOf: ""            // the cover these colors are from
    // music plays and its colors are known; a pause keeps them for a little while (a song ending, the next one
    // starting) so the desktop does not flash back and forth
    property bool holdOn: false
    readonly property bool wantTint: cover && tintOk && tintOf === Player.art && Player.art !== ""
    readonly property bool active: wantTint && colorMode === "auto" && (Player.playing || holdOn)
    property Timer grace: Timer { interval: 6000; onTriggered: vb.holdOn = false }
    property Connections pc: Connections {
        target: Player
        function onPlayingChanged() { if (Player.playing) { vb.grace.stop(); vb.holdOn = true } else vb.grace.restart() }
    }

    // ---------- the beat ----------
    property int need: 0
    property real level: 0
    property real kick: 0                 // a hit on the beat: jumps to 1 and fades
    property real avg: 0
    readonly property bool listening: need > 0 && Player.playing && !Look.lite
    property CavaUser cu: CavaUser { active: vb.listening }
    onListeningChanged: if (!listening) { level = 0; kick = 0; avg = 0 }
    property Connections cf: Connections {
        target: CavaFeed
        enabled: vb.listening
        function onFrame() {
            const b = CavaFeed.bands
            if (b.length < 8) return
            let s = 0
            const n = Math.max(3, Math.floor(b.length / 10))
            for (let i = 0; i < n; i++) s += b[i]
            const v = Math.min(1, s / n / 100 * 1.15)
            const nl = v >= vb.level ? vb.level + (v - vb.level) * 0.75 : vb.level * 0.86 + v * 0.14
            if (Math.abs(nl - vb.level) > 0.004 || (nl < 0.004 && vb.level !== 0)) vb.level = nl < 0.004 ? 0 : nl
            // a kick: well over the recent average
            if (v > 0.42 && v > vb.avg * 1.35 && vb.kick < 0.35) vb.kick = 1
            else if (vb.kick > 0) vb.kick = vb.kick < 0.05 ? 0 : vb.kick * 0.8
            vb.avg = vb.avg * 0.93 + v * 0.07
        }
    }
}
