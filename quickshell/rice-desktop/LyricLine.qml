import QtQuick

// V6.11: the line being sung, alone and big (Lyrics.cur). Its words rise in one after another, they fill with
// color as they are sung (word by word, worked out from when the next line starts), and the line floats up and
// fades when the next one comes. A pause in the song shows three notes that bob. Long lines get smaller until
// they fit on `maxRows` rows.
// It shows Lyrics; something around it keeps a LyricsUser active.
Item {
    id: ll
    property real size: 26
    property real minSize: 15
    property int maxRows: 2
    property color sung: "white"
    property color dim: Qt.rgba(1, 1, 1, 0.36)
    // the reading font (Settings > Fonts) and the weight the rest of the shell uses: ExtraBold read as someone
    // else's type next to the cards
    property string family: Fonts.reading
    property int weight: Font.DemiBold
    property real lift: 18              // how far the words rise in
    property bool live: true            // the animations (off: the words just appear)
    property int align: Text.AlignHCenter
    readonly property int cur: Lyrics.cur
    readonly property bool has: Lyrics.lines.length > 0
    property bool flip: false
    clip: false

    onCurChanged: show()
    onHasChanged: show()
    Component.onCompleted: show()
    onWidthChanged: { la.relayoutLater(); lb.relayoutLater() }
    function show() {
        const front = flip ? lb : la, back = flip ? la : lb
        if (!has || cur < 0) { front.leave(); back.leave(); return }
        if (front.shown && front.idx === cur) return
        front.leave()
        back.enter(cur)
        flip = !flip
    }

    component Line: Item {
        id: ln
        width: ll.width; height: ll.height
        property int idx: -2
        property bool shown: false
        property real out: 0
        property real fs: ll.size
        property var list: []
        property var xs: []
        property var ys: []
        property bool note: false
        // how much of the line each word is (letters), to fill them in time
        property var cum: []
        property var wts: []
        property real total: 1
        property real dur: 2
        opacity: shown ? 1 - out : 0
        visible: opacity > 0.01
        transform: Translate { y: -ll.lift * 1.2 * ln.out }
        scale: 1 - 0.05 * out
        NumberAnimation { id: outA; target: ln; property: "out"; to: 1; duration: 380; easing.type: Easing.InCubic; onFinished: { ln.shown = false; ln.list = [] } }

        function enter(i) {
            outA.stop(); out = 0
            fs = ll.size; idx = i
            const t = Lyrics.textAt(i).trim()
            note = t === ""
            const w = note ? ["♪", "♪", "♪"] : t.split(/\s+/)
            const c = [], ws = []
            let s = 0
            for (let k = 0; k < w.length; k++) { c.push(s); const x = w[k].length + 1; ws.push(x); s += x }
            cum = c; wts = ws; total = Math.max(1, s)
            const span = Lyrics.endAt(i) - Lyrics.startAt(i)
            dur = Math.max(0.8, Math.min(span - 0.25, s * 0.075 + 0.4))
            xs = []; ys = []
            list = []
            list = w
            shown = true
            relayoutLater()
        }
        function leave() { if (shown && !outA.running) outA.restart() }
        function fillOf(k) {
            if (note || k >= wts.length) return 0
            const p = Math.max(0, Math.min(1, (Lyrics.now - Lyrics.startAt(idx)) / dur)) * total
            return Math.max(0, Math.min(1, (p - cum[k]) / wts[k]))
        }
        function relayoutLater() { Qt.callLater(ln.relayout) }
        function relayout() {
            const n = rep.count
            if (n === 0 || ll.width <= 0) return
            const sp = fs * 0.28, W = ll.width, lh = fs * 1.2
            const rows = [[]], rw = [0]
            for (let i = 0; i < n; i++) {
                const it = rep.itemAt(i)
                const w = it ? it.width : 0
                const r = rows.length - 1
                if (rows[r].length > 0 && rw[r] + sp + w > W) { rows.push([i]); rw.push(w) }
                else { rw[r] += (rows[r].length > 0 ? sp : 0) + w; rows[r].push(i) }
            }
            if (rows.length > ll.maxRows && fs > ll.minSize) { fs = Math.max(ll.minSize, fs - 2); relayoutLater(); return }
            const x = [], y = [], top = (ll.height - rows.length * lh) / 2
            for (let r = 0; r < rows.length; r++) {
                let cx = ll.align === Text.AlignLeft ? 0 : (ll.align === Text.AlignRight ? W - rw[r] : (W - rw[r]) / 2)
                for (const i of rows[r]) { const it = rep.itemAt(i); x[i] = cx; y[i] = top + r * lh + (lh - (it ? it.height : lh)) / 2; cx += (it ? it.width : 0) + sp }
            }
            xs = x; ys = y
        }

        Repeater {
            id: rep
            model: ln.list
            delegate: Item {
                id: wd
                required property string modelData
                required property int index
                x: ln.xs[index] !== undefined ? ln.xs[index] : 0
                y: ln.ys[index] !== undefined ? ln.ys[index] : 0
                width: base.implicitWidth; height: base.implicitHeight
                onWidthChanged: ln.relayoutLater()
                readonly property real f: ln.fillOf(index)
                readonly property bool singing: f > 0.02 && f < 0.98
                // in: each word a moment after the one before, with a little bounce
                property real e: 0
                property real bob: 0
                opacity: e * (ln.xs.length > 0 ? 1 : 0)
                transform: Translate { y: (1 - wd.e) * ll.lift + wd.bob - (wd.singing ? ln.fs * 0.05 : 0)
                    Behavior on y { enabled: wd.e >= 1; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
                scale: 0.86 + 0.14 * e
                SequentialAnimation {
                    id: inA
                    PauseAnimation { duration: wd.index * 55 }
                    NumberAnimation { target: wd; property: "e"; to: 1; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
                }
                // a pause in the song: the notes bob, one after another
                SequentialAnimation on bob {
                    running: ln.note && ln.shown && ll.live; loops: Animation.Infinite
                    PauseAnimation { duration: Math.min(2, wd.index) * 160 }
                    NumberAnimation { to: -ln.fs * 0.22; duration: 420; easing.type: Easing.OutQuad }
                    NumberAnimation { to: 0; duration: 420; easing.type: Easing.InQuad }
                    PauseAnimation { duration: Math.max(0, 2 - wd.index) * 160 + 200 }
                }
                Component.onCompleted: { if (ll.live) inA.start(); else e = 1 }
                Text {
                    id: base
                    text: wd.modelData
                    color: ln.note ? ll.sung : ll.dim
                    opacity: ln.note ? 0.8 : 1
                    font.family: ll.family; font.pixelSize: ln.fs; font.weight: ll.weight
                }
                // the sung part, the same word in the bright color over it
                Item {
                    width: wd.width * wd.f; height: wd.height
                    clip: true
                    visible: wd.f > 0
                    Text {
                        text: wd.modelData; color: ll.sung
                        font.family: ll.family; font.pixelSize: ln.fs; font.weight: ll.weight
                    }
                }
            }
        }
    }
    Line { id: la }
    Line { id: lb }
}
