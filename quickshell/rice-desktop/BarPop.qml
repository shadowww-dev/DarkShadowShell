import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Shapes

// The small cards the bar's own modules open under them (Bar layout > Music, Weather, System, Date):
//   music     the song, its lyrics, the progress and the buttons (MusicPop.qml)
//   weather   now, how it feels, high / low and the next hours (rice-weather json)
//   system    CPU, RAM, disk and swap, each in a tile with the numbers; CPU and RAM with a graph of the last two
//             minutes (V6.55), disk and swap with a bar (rice-stats)
//   calendar  the month, this week with today, your to-do tasks (rice-todo) and how long the computer is up
// It grows out of the bar under the module and closes with Esc, a click outside or the same module again.
Item {
    id: bp
    property var pal: null
    property string kind: ""
    property real ax: 0
    property bool down: true
    property real areaW: 1920
    property bool open: false
    property var wx: null                       // the weather (the bar fetches it)
    property var st: ({})                       // the numbers (the bar reads them)
    property var sink: null                     // the speakers (the music card's volume)
    function toggle(k, x) { if (open && kind === k) { open = false; return } kind = k; ax = x; open = true; if (k === "calendar") { todoProc.running = true; upProc.running = true; now = new Date() } }
    function close() { open = false }

    // the module it grows out of: its width on the bar and the bar's height (the card starts as that pill)
    property real fromW: 60
    property real barH: 38
    // t: 0 closed .. 1 open. Like the Dynamic island: the module's pill stretches out of the bar into the card (it
    // stays joined with the bar for the first two thirds), the corners round off, and the content comes in once
    // there is room for it
    property real t: 0
    // V7.15: the Dynamic island's own motion (520 ms InOutCubic, both ways), so the Music card opens and closes like
    // the island's cards and the bar's menus; OutBack/InBack bounced the whole card, which the island never does
    onOpenChanged: { tAnim.stop(); tAnim.to = open ? 1 : 0; tAnim.duration = Look.lite ? 240 : 520
        tAnim.easing.type = Easing.InOutCubic; tAnim.start() }
    NumberAnimation { id: tAnim; target: bp; property: "t" }
    // a new card while one is open (another module): the content cross-fades
    onKindChanged: { swap.restart() }
    property real cf: 1
    SequentialAnimation { id: swap; NumberAnimation { target: bp; property: "cf"; to: 0; duration: 70 } NumberAnimation { target: bp; property: "cf"; to: 1; duration: 220; easing.type: Easing.OutCubic } }
    visible: t > 0.01
    width: kind === "music" ? 412 : 330
    Behavior on width { enabled: bp.t > 0.98; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    height: (kind === "weather" ? wxCol.implicitHeight : (kind === "system" ? 228 : (kind === "music" ? musicCol.implicitHeight : calCol.implicitHeight))) + 28
    Behavior on height { enabled: bp.t > 0.98; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    x: Math.max(12, Math.min(areaW - width - 12, ax - width / 2))
    readonly property color fg: pal ? pal.fg : "#ECEDEE"
    readonly property color dim: pal ? pal.dim : "#A9ADB2"
    readonly property color acc: pal ? pal.primary : "#9ec9bd"
    readonly property color chip: pal ? pal.card : "#2a2c30"

    function gb(v) { return v === undefined ? "?" : (v >= 100 ? Math.round(v) : Number(v).toFixed(1)) }
    readonly property var sys: [
        { n: "CPU", icon: "memory", g: 0xF035B, v: st.cpu || 0, d: st.temp ? st.temp + "°C" : "" },
        { n: "RAM", icon: "memory_alt", g: 0xF061A, v: st.ram || 0, d: gb(st.ramu) + " / " + gb(st.ramt) + " GB" },
        { n: Tr.t("Disk"), icon: "hard_drive", g: 0xF02CA, v: st.disk || 0, d: gb(st.disku) + " / " + gb(st.diskt) + " GB" },
        { n: "Swap", icon: "swap_horiz", g: 0xF04E1, v: st.swap || 0, d: st.swapt ? gb(st.swapu) + " / " + gb(st.swapt) + " GB" : Tr.t("Off") }
    ]
    property var now: new Date()
    property var todos: []
    property string up: ""
    readonly property var week: {
        const o = [], n = now, mon = new Date(n.getFullYear(), n.getMonth(), n.getDate() - ((n.getDay() + 6) % 7))
        for (let i = 0; i < 7; i++) o.push(new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + i))
        return o
    }

    // V7.15: the same timeline as DropCard (the Wi-Fi, Bluetooth, sound and power menus, and the island): the pill
    // grows joined with the bar, and only at two thirds does it pull 8 px away while the strand thins to nothing.
    // It used to start as a pill above the bar and drop in, which is why the Music card did not move like the rest
    readonly property real tc: Math.max(0, t)
    readonly property real openE: { const p = Math.max(0, Math.min(1, (tc - 0.08) / 0.64)); return p * p * (3 - 2 * p) }
    readonly property real dp: { const p = Math.max(0, Math.min(1, (tc - 0.66) / 0.34)); return p * p * (3 - 2 * p) }
    // the same 26 px pill the DropCard menus start from (the island's own is a little shorter)
    readonly property real pillH: Math.min(26, Math.max(22, barH - 10))
    // the bar's near edge is 8 px above this item (it is placed barH + 8 under the bar, or -height - 8 above a
    // bottom one). The pill is the module's pill inside the bar: centered on it, so it starts at the bar's far edge
    readonly property real hang: down ? -8 : height + 8
    readonly property real pillTop: (down ? -8 - barH : height + 8) + (barH - pillH) / 2
    readonly property real baseY: pillTop + (hang - pillTop) * Math.min(1, openE * 3)
    readonly property real sy: baseY * (1 - dp)

    // ---------- the strand: one shape with the bar until the card lets go ----------
    Shape {
        id: strand
        x: shape.x
        y: shape.y - height
        width: Math.max(1, shape.width)
        height: Math.max(0, bp.down ? shape.y + 8 : 0)
        readonly property real tw0: Math.min(width * 0.62, bp.fromW * 0.9)
        readonly property real letgo: Math.max(0, Math.min(1, (bp.tc - 0.55) / 0.45))
        readonly property real tw: tw0 * Math.pow(1 - letgo, 2.2)
        readonly property real cx: Math.max(4, Math.min(width - 4, bp.ax - bp.x - shape.x))
        readonly property bool joined: bp.down && bp.tc > 0.02 && height > 0.05 && tw >= 0.15
        visible: joined
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: bp.pal ? bp.pal.surface : "#141414"
            strokeColor: "transparent"
            fillRule: ShapePath.WindingFill
            PathSvg { path: {
                const W = strand.width, H = strand.height, tw = strand.tw
                if (H < 0.05 || tw < 0.15 || W < 1) return ""
                const cx = strand.cx, tb = Math.min(W, tw * 1.45)
                const midUp = H * 0.52, midDn = H * 0.58
                return "M" + (cx - tw / 2) + " 0" +
                  " C" + (cx - tw * 0.42) + " " + midUp + " " + (cx - tb * 0.5) + " " + midDn + " " + (cx - tb / 2) + " " + H +
                  " L" + (cx + tb / 2) + " " + H +
                  " C" + (cx + tb * 0.5) + " " + midDn + " " + (cx + tw * 0.42) + " " + midUp + " " + (cx + tw / 2) + " 0 Z"
            } }
        }
    }

    Item {
        id: shape
        readonly property real cx: bp.ax - bp.x
        width: bp.fromW + (bp.width - bp.fromW) * bp.openE
        height: bp.pillH + (bp.height - bp.pillH) * bp.openE
        x: cx + (bp.width / 2 - cx) * bp.openE - width / 2
        y: bp.sy
        // it lands on the module's pill inside the bar and fades there over the last frames
        opacity: Math.min(1, bp.t * 6)
        clip: true
        Shadow { anchors.fill: bg; radius: Look.sq ? 0 : (bg.radius); on: Look.shadows && Look.shadowPanels; size: Look.shadowSize * 0.8; strength: Look.shadowStrength * bp.openE }
        Rectangle { id: bg; anchors.fill: parent; radius: Look.sq ? 0 : (Math.min(height / 2, bp.pillH / 2 + (24 - bp.pillH / 2) * bp.openE)); color: bp.pal ? bp.pal.surface : "#141414" }
        // the glass line: only once the card is clearly away, so it is never drawn across the strand (the island
        // and DropCard do the same; a border on the shape itself made the Music card the odd one out)
        Rectangle {
            anchors.fill: parent
            radius: bg.radius
            color: "transparent"; border.width: 1; border.color: bp.pal ? bp.pal.line : Qt.rgba(1, 1, 1, 0.06)
            visible: opacity > 0.01
            opacity: bp.dp > 0.9 && !strand.joined ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent }        // clicks inside do not fall through to the desktop
        // the content stays where it belongs while the shape opens over it
        Item {
            id: cont
            x: -shape.x; y: -shape.y
            width: bp.width; height: bp.height
            opacity: Math.max(0, (bp.openE - 0.45) / 0.55) * bp.cf

    // ---------- music ----------
    MusicPop {
        id: musicCol
        visible: bp.kind === "music"
        x: 16; y: 14; width: parent.width - 32
        bp: bp
        sink: bp.sink
    }

    // ---------- weather ----------
    Column {
        id: wxCol
        visible: bp.kind === "weather"
        x: 14; y: 14; width: parent.width - 28; spacing: 10
        Item {
            width: parent.width; height: 92
            Column {
                x: 6; y: 2; spacing: 0
                Row { spacing: 4
                    MIcon { anchors.verticalCenter: parent.verticalCenter; size: 14; name: "location_on"; glyph: String.fromCodePoint(0xF034E); color: bp.acc }
                    Text { anchors.verticalCenter: parent.verticalCenter; text: bp.wx ? bp.wx.place : Tr.t("Looking outside..."); color: bp.dim; font.family: Fonts.main; font.pixelSize: 12 } }
                Row { spacing: 2
                    Text { text: bp.wx ? String(bp.wx.temp) : "--"; color: bp.fg; font.family: Fonts.numbers; font.pixelSize: 46; font.weight: Font.Medium }
                    Text { y: 8; text: "°" + (bp.wx ? bp.wx.unit : ""); color: bp.dim; font.family: Fonts.numbers; font.pixelSize: 18 } }
                Text { text: bp.wx ? bp.wx.cond + " · " + Tr.t("Feels") + " " + bp.wx.feels + "°" : ""; color: bp.dim; font.family: Fonts.main; font.pixelSize: 11 }
            }
            Item {
                width: 78; height: 78; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                Blob { anchors.fill: parent; kind: Look.shape; color: bp.pal ? bp.pal.container : "#333"
                    SlowSpin { turn: 360; period: 46000; running: bp.open && !Look.lite } }
                WxIcon { anchors.centerIn: parent; size: 38; cond: bp.wx ? bp.wx.cond : ""; color: bp.pal ? bp.pal.inkContainer : "white"
                    night: { const h = new Date().getHours(); return h < 6 || h >= 19 } }
            }
        }
        Row {
            spacing: 6
            Repeater {
                model: [["arrow_upward", 0xF005D, bp.wx ? bp.wx.hi + "°" : "--"], ["arrow_downward", 0xF0045, bp.wx ? bp.wx.lo + "°" : "--"],
                        ["humidity_percentage", 0xF058E, bp.wx ? bp.wx.hum + "%" : "--"], ["air", 0xF059D, bp.wx ? bp.wx.wind + (bp.wx.unit === "F" ? " mph" : " km/h") : "--"]]
                delegate: Rectangle {
                    width: (wxCol.width - 18) / 4; height: 30; radius: Look.sq ? 0 : (15); color: bp.chip
                    Row { anchors.centerIn: parent; spacing: 3
                        MIcon { anchors.verticalCenter: parent.verticalCenter; size: 13; name: modelData[0]; glyph: String.fromCodePoint(modelData[1]); color: bp.acc }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: modelData[2]; color: bp.fg; font.family: Fonts.main; font.pixelSize: 11 } }
                }
            }
        }
        Row {
            id: wxh
            spacing: 6
            readonly property var list: bp.wx && bp.wx.hours ? bp.wx.hours : []
            Repeater {
                model: wxh.list
                delegate: Rectangle {
                    width: (wxCol.width - 6 * Math.max(0, wxh.list.length - 1)) / Math.max(1, wxh.list.length); height: 66; radius: Look.sq ? 0 : (18)
                    color: index === 0 ? bp.pal.container : bp.chip
                    Column { anchors.centerIn: parent; spacing: 2
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: (modelData.h < 10 ? "0" : "") + modelData.h + ":00"; color: bp.dim; font.family: Fonts.main; font.pixelSize: 10 }
                        WxIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 18; cond: modelData.c; night: modelData.h < 6 || modelData.h >= 19; color: bp.acc }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.t + "°"; color: bp.fg; font.family: Fonts.numbers; font.pixelSize: 13; font.weight: Font.DemiBold } }
                }
            }
        }
    }

    // ---------- system ----------
    Grid {
        visible: bp.kind === "system"
        x: 14; y: 14; width: parent.width - 28; height: 228
        columns: 2; spacing: 8
        Repeater {
            model: 4          // fixed: the tiles stay, their numbers change (bp.sys rebuilt them every reading)
            delegate: Rectangle {
                readonly property var md: bp.sys[index]
                width: (bp.width - 28 - 8) / 2; height: (228 - 8) / 2
                radius: Look.sq ? 0 : (20); color: bp.chip
                MIcon { x: 14; y: 12; size: 18; name: md.icon; glyph: String.fromCodePoint(md.g); color: bp.acc }
                Text { anchors.right: parent.right; anchors.rightMargin: 14; y: 9; text: md.v + "%"; color: bp.fg; font.family: Fonts.numbers; font.pixelSize: 19; font.weight: Font.DemiBold }
                Column { x: 14; y: 42; width: parent.width - 28; spacing: 1
                    Text { text: md.n; color: bp.fg; font.family: Fonts.main; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { width: parent.width; elide: Text.ElideRight; text: md.d; color: bp.dim; font.family: Fonts.main; font.pixelSize: 10 } }
                // V6.55: CPU and RAM show the last two minutes as a graph; disk and swap keep their bar
                Sparkline {
                    visible: index < 2
                    x: 14; width: parent.width - 28; height: 26
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 10
                    values: index === 0 ? Stats.hist.cpu : Stats.hist.ram
                    color: md.v >= 90 ? "#e06c75" : bp.acc
                }
                Rectangle {
                    visible: index >= 2
                    x: 14; width: parent.width - 28; height: 6; radius: Look.sq ? 0 : (3)
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 13
                    color: Qt.rgba(bp.acc.r, bp.acc.g, bp.acc.b, 0.2)
                    Rectangle { width: Math.max(6, parent.width * Math.min(1, md.v / 100)); height: 6; radius: Look.sq ? 0 : (3); color: md.v >= 90 ? "#e06c75" : bp.acc
                        Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } } }
                }
            }
        }
    }

    // ---------- calendar ----------
    Process { id: todoProc; command: [Quickshell.env("HOME") + "/.local/bin/rice-todo", "list"]
        stdout: StdioCollector { onStreamFinished: { try { bp.todos = JSON.parse(text).filter(function(x) { return !x.done }) } catch (e) { bp.todos = [] } } } }
    Process { id: upProc; command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { onStreamFinished: {
            const s = Math.floor(parseFloat(text.split(" ")[0]) || 0), d = Math.floor(s / 86400), h = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60
            bp.up = (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m" } } }
    Column {
        id: calCol
        visible: bp.kind === "calendar"
        x: 14; y: 14; width: parent.width - 28; spacing: 10
        Text { x: 6; text: Qt.locale().standaloneMonthName(bp.now.getMonth()) + " " + bp.now.getFullYear(); color: bp.fg; font.family: Fonts.main; font.pixelSize: 18; font.weight: Font.DemiBold
            font.capitalization: Font.Capitalize }
        Row {
            spacing: 4
            Repeater {
                model: bp.week
                delegate: Rectangle {
                    readonly property bool today: modelData.toDateString() === bp.now.toDateString()
                    width: (calCol.width - 24) / 7; height: 56; radius: Look.sq ? 0 : (16)
                    color: today ? bp.acc : "transparent"
                    Column { anchors.centerIn: parent; spacing: 4
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Qt.locale().dayName(modelData.getDay(), Locale.ShortFormat).slice(0, 2)
                            color: today ? (bp.pal ? bp.pal.inkPrimary : "black") : bp.dim; font.family: Fonts.main; font.pixelSize: 11 }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.getDate()
                            color: today ? (bp.pal ? bp.pal.inkPrimary : "black") : bp.fg; font.family: Fonts.numbers; font.pixelSize: 16; font.weight: today ? Font.Bold : Font.Medium }
                    }
                }
            }
        }
        // your to-do tasks (the To-do widget's list)
        Rectangle {
            width: parent.width; height: 62; radius: Look.sq ? 0 : (18); color: bp.chip
            Rectangle { x: 10; anchors.verticalCenter: parent.verticalCenter; width: 42; height: 42; radius: Look.sq ? 0 : (14); color: bp.pal ? bp.pal.container : "#333"
                Column { anchors.centerIn: parent; spacing: -2
                    MIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 13; name: "checklist"; glyph: String.fromCodePoint(0xF0AB8); color: bp.acc }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: bp.todos.length; color: bp.fg; font.family: Fonts.numbers; font.pixelSize: 15; font.weight: Font.Bold } } }
            Column { x: 64; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 76; spacing: 2
                Text { width: parent.width; elide: Text.ElideRight; color: bp.fg; font.family: Fonts.main; font.pixelSize: 13; font.weight: Font.DemiBold
                    text: bp.todos.length ? bp.todos[0].t : Tr.t("Nothing to do") }
                Text { width: parent.width; elide: Text.ElideRight; color: bp.dim; font.family: Fonts.main; font.pixelSize: 11
                    text: bp.todos.length > 1 ? Tr.t("and %1 more").replace("%1", bp.todos.length - 1) : Tr.t("To-do") } }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 6; visible: bp.up !== ""
            MIcon { anchors.verticalCenter: parent.verticalCenter; size: 13; name: "schedule"; glyph: String.fromCodePoint(0xF0954); color: bp.dim }
            Text { anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Up for") + " " + bp.up; color: bp.dim; font.family: Fonts.main; font.pixelSize: 11 }
        }
    }
        }
    }
}
