import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects

// The music card the bar's Music module opens (inside BarPop.qml): the cover in a turning halo of your shape,
// the song, its lyrics running with it (rice-lyrics, LRCLIB; fetched only while the card is open; V6.11: one big
// line at a time, its words rising in and filling as they are sung), a wavy
// progress line you can drag, the buttons and the volume. Everything comes in one after another as the card opens.
Item {
    id: mp
    property var bp: null                       // the card it lives in (colors, open, t)
    property var sink: null                     // the speakers (the volume buttons)
    readonly property bool on: !!bp && bp.open && bp.kind === "music"
    readonly property color fg: bp ? bp.fg : "white"
    readonly property color dim: bp ? bp.dim : "#aaa"
    readonly property color acc: bp ? bp.acc : "#9ec9bd"
    readonly property color chip: bp ? bp.chip : "#2a2c30"
    readonly property color ink: bp && bp.pal ? bp.pal.inkPrimary : "#10201c"
    width: 380
    implicitHeight: 360

    Instantiator { model: mp.on ? 1 : 0; delegate: QtObject { Component.onCompleted: Player.hold(); Component.onDestruction: Player.release() } }

    // V7.16: the content follows the card's own shape (BarPop.openE), exactly like Weather/System/Date. It used to
    // run its own 760 ms stagger, so Music was the only card still moving after the shape had finished opening.
    readonly property real e: mp.bp ? mp.bp.openE : 0
    function st(i) { return mp.e }

    // ---------- the lyrics ----------
    // V6.11: from Lyrics (one lookup per song for the whole shell), while the card is open
    LyricsUser { active: mp.on }
    readonly property var lines: Lyrics.lines
    readonly property string plain: Lyrics.plain
    readonly property bool lyOff: Lyrics.lyOff
    readonly property bool loading: Lyrics.loading
    readonly property bool hasSong: Player.has

    // ---------- the cover and the song ----------
    Item {
        id: cov
        x: 10; y: 4; width: 118; height: 118
        opacity: mp.st(0)
        scale: 0.55 + 0.45 * mp.st(0)
        rotation: -24 * (1 - mp.st(0))
        // V6.88: the one cover that is a rounded square cropped to fill (the shape ate the edges of the picture).
        // V7.15: the same cover as the desktop "Music card" widget (ShapeImage kind "square"), not a Rectangle:
        // one Look, and the fallback note comes with it
        ShapeImage { anchors.fill: parent; kind: "square"; source: Player.art; empty: mp.chip; fallbackColor: mp.dim }
    }
    Column {
        x: cov.x + cov.width + 16; y: 10
        width: mp.width - x - 4
        spacing: 4
        opacity: mp.st(1)
        transform: Translate { x: (1 - mp.st(1)) * 26 }
        Rectangle {
            visible: Player.has
            height: 22; radius: Look.sq ? 0 : (11); width: idt.implicitWidth + 30
            color: Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.18)
            Row { anchors.centerIn: parent; spacing: 5
                Item { width: 12; height: 12; anchors.verticalCenter: parent.verticalCenter
                    // three small bars that dance while it plays
                    Row { anchors.centerIn: parent; spacing: 1.5
                        Repeater { model: 3
                            Rectangle { width: 2.5; radius: Look.sq ? 0 : (1.25); anchors.bottom: parent.bottom; color: mp.acc
                                property real h: 4
                                height: h
                                SequentialAnimation on h { running: mp.on && Player.playing && !Look.lite; loops: Animation.Infinite
                                    NumberAnimation { to: 12; duration: 260 + index * 90; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 3; duration: 300 + index * 70; easing.type: Easing.InOutSine } } } } } }
                Text { id: idt; anchors.verticalCenter: parent.verticalCenter; text: Player.p ? (Player.p.identity || "Music") : ""; color: mp.acc
                    font.family: Fonts.main; font.pixelSize: 11; font.weight: Font.DemiBold } }
        }
        // V6.85: the island's player typography (17 demi-bold, 13 for the artist), not the tight bold 19
        Text { width: parent.width; text: Player.title; color: mp.fg; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            font.family: Fonts.main; font.pixelSize: 17; font.weight: Font.DemiBold }
        Text { width: parent.width; text: Player.artist + (Player.album !== "" ? "  ·  " + Player.album : ""); color: mp.dim; elide: Text.ElideRight
            font.family: Fonts.main; font.pixelSize: 13 }
    }

    // ---------- the lyrics ----------
    Rectangle {
        id: words
        x: 0; y: cov.y + cov.height + 12; width: mp.width; height: 112
        // V6.88: the block was a solid panel next to the glass card; it shows the card through it now
        radius: Look.sq ? 0 : (22); color: Qt.rgba(mp.chip.r, mp.chip.g, mp.chip.b, 0.42); clip: true
        opacity: mp.st(2)
        transform: Translate { y: (1 - mp.st(2)) * 22 }
        // V6.11: only the line being sung, big; its words rise in and fill as they are sung
        Item {
            anchors.fill: parent; anchors.margins: 8
            // V6.88: a soft glow in the song's color, so the words sit on the card instead of in a box
            layer.enabled: mp.on && mp.lines.length > 0
            layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.85; shadowColor: Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.5)
                shadowVerticalOffset: 0; shadowHorizontalOffset: 0 }
            LyricLine {
                anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                visible: mp.hasSong && mp.lines.length > 0
                size: 24; minSize: 15; maxRows: 2
                sung: mp.acc; dim: Qt.rgba(mp.fg.r, mp.fg.g, mp.fg.b, 0.34)
                live: mp.on && !Look.lite
            }
        }
        Flickable {
            anchors.fill: parent; anchors.margins: 12
            visible: mp.hasSong && mp.lines.length === 0 && mp.plain !== ""
            contentHeight: ptx.implicitHeight
            contentY: Math.max(0, (ptx.implicitHeight - height) * Player.frac)
            interactive: false
            Text { id: ptx; width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: mp.plain
                color: mp.dim; font.family: Fonts.main; font.pixelSize: 12; lineHeight: 1.3 }
        }
        Row {
            anchors.centerIn: parent
            visible: mp.lines.length === 0 && mp.plain === ""
            spacing: 8
            Blob { id: lyrBlob; width: 16; height: 16; kind: Look.shape; color: mp.dim; anchors.verticalCenter: parent.verticalCenter
                RotationAnimator on rotation { from: 0; to: 360; duration: 1600; loops: Animation.Infinite; running: mp.loading && mp.on
                    onRunningChanged: if (running) lyrSettle.stop(); else Qt.callLater(lyrSettle.go) }
                NumberAnimation { id: lyrSettle; target: lyrBlob; property: "rotation"; to: 360; duration: 500; easing.type: Easing.OutCubic
                    function go() { const r = ((lyrBlob.rotation % 360) + 360) % 360; lyrBlob.rotation = r; from = r; restart() }
                    onFinished: lyrBlob.rotation = 0 } }
            Text { anchors.verticalCenter: parent.verticalCenter; color: mp.dim; font.family: Fonts.main; font.pixelSize: 12
                text: !Player.has ? Tr.t("Nothing playing") : (mp.loading ? Tr.t("Looking for the lyrics...") : (mp.lyOff ? Tr.t("Lyrics are off: Settings > Language & region") : Tr.t("No lyrics for this song"))) }
        }
        // soft edges for the plain words that scroll
        Rectangle { visible: mp.lines.length === 0; anchors.top: parent.top; width: parent.width; height: 30; radius: Look.sq ? 0 : (words.radius); gradient: Gradient {
            GradientStop { position: 0; color: mp.chip } GradientStop { position: 1; color: Qt.rgba(mp.chip.r, mp.chip.g, mp.chip.b, 0) } } }
        Rectangle { visible: mp.lines.length === 0; anchors.bottom: parent.bottom; width: parent.width; height: 30; radius: Look.sq ? 0 : (words.radius); gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(mp.chip.r, mp.chip.g, mp.chip.b, 0) } GradientStop { position: 1; color: mp.chip } } }
    }

    // ---------- where the song is ----------
    Item {
        id: prog
        x: 0; y: words.y + words.height + 12; width: mp.width; height: 20
        opacity: mp.st(3)
        transform: Translate { y: (1 - mp.st(3)) * 18 }
        Text { id: tA; anchors.left: parent.left; anchors.leftMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Player.clock(Player.pos)
            color: mp.dim; font.family: Fonts.numbers; font.pixelSize: 11 }
        WavyLine {
            anchors.left: tA.right; anchors.leftMargin: 10; anchors.right: tB.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter; height: 18
            value: Player.frac; moving: Player.playing && mp.on; seekable: true
            color: mp.acc; track: Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.2)
            onMoved: function(v) { Player.seekTo(v) }
        }
        Text { id: tB; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: Player.clock(Player.length)
            color: mp.dim; font.family: Fonts.numbers; font.pixelSize: 11 }
    }

    // ---------- the buttons ----------
    Row {
        id: btns
        anchors.horizontalCenter: parent.horizontalCenter
        y: prog.y + prog.height + 14
        spacing: 8
        opacity: mp.st(4)
        transform: Translate { y: (1 - mp.st(4)) * 18 }
        readonly property real vol: Vol.of(mp.sink)
        function setVol(d) { Vol.nudge(mp.sink, d) }
        Btn { w: 46; icon: "volume_down"; g: 0xF075E; onHit: btns.setVol(-0.05) }
        Btn { w: 56; icon: "skip_previous"; g: 0xF04AE; onHit: Player.prev() }
        Btn { w: 84; icon: Player.playing ? "pause" : "play_arrow"; g: Player.playing ? 0xF03E4 : 0xF040A; strong: true; onHit: Player.toggle() }
        Btn { w: 56; icon: "skip_next"; g: 0xF04AD; onHit: Player.next() }
        Btn { w: 46; icon: "volume_up"; g: 0xF057E; onHit: btns.setVol(0.05) }
    }
    // the volume, as a thin line under the buttons. V6.85: it sets the volume too (drag it or tap a point on it);
    // before, only the + / - buttons could change it
    Item {
        anchors.horizontalCenter: parent.horizontalCenter
        y: btns.y + 48; width: 150; height: 20
        opacity: mp.st(5)
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: Look.sq ? 0 : (2)
            color: Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.18) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: Math.max(4, parent.width * Math.min(1, btns.vol)); height: 4; radius: Look.sq ? 0 : (2); color: mp.acc
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } } }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            function put(m) { Vol.set(mp.sink, Math.max(0, Math.min(1, m.x / width))) }
            onPressed: function(m) { put(m) }
            onPositionChanged: function(m) { if (pressed) put(m) }
        }
    }

    component Btn: Item {
        id: b
        property real w: 50
        property string icon: ""
        property int g: 0
        property bool strong: false
        signal hit()
        width: w; height: 46
        Rectangle {
            anchors.fill: parent
            // pressed: the corners tighten; the play button is a pill that turns into a rounder square while it plays
            radius: Look.sq ? 0 : (bm.pressed ? 12 : (b.strong && Player.playing ? 16 : height / 2))
            Behavior on radius { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
            color: b.strong ? mp.acc : (bm.containsMouse ? Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.3) : Qt.rgba(mp.acc.r, mp.acc.g, mp.acc.b, 0.16))
            Behavior on color { ColorAnimation { duration: 140 } }
            scale: bm.pressed ? 0.94 : 1
            Behavior on scale { NumberAnimation { duration: 140 } }
        }
        MIcon { anchors.centerIn: parent; size: b.strong ? 24 : 20; name: b.icon; glyph: String.fromCodePoint(b.g); color: b.strong ? mp.ink : mp.fg }
        MouseArea { id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { Sfx.play("click"); b.hit() } }
    }
}
