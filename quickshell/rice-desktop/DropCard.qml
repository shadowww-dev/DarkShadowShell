import Quickshell
import QtQuick
import QtQuick.Shapes

// V7.14 the card the bar's menus open, moving like the Dynamic island: the module's pill on the bar stretches into
// the card (its content is clipped in and comes in once there is room), and once it is open the card pulls away from
// the bar while the strand between them thins to nothing. Closing is the same shape backwards, so it is smooth both
// ways. The card's glass line is off while it is joined, otherwise it would be drawn straight across the strand.
// V7.15: the closed shape is the module's pill itself, inside the bar (not a nub under it), and the last frames fade,
// so the close ends on the module the way the island's panel ends on the island.
Item {
    id: dc
    property real t: 0                  // 0 closed .. 1 open
    property real openW: 360            // the finished card
    property real openH: 160
    property real fromW: 38             // the module's pill on the bar
    property real pillH: 26
    property real ax: 0                 // the module's centre, in the window
    property real ay: -1                // side bars: the module's middle
    property bool side: false
    property bool atRight: false
    property bool down: true            // the bar is at the top
    property real barSpace: 62          // the bar's spacing .. the card's near edge at rest
    property real sideSpace: 50
    property real rad: 20
    property color bg: "#1c1c1c"
    property color line: Qt.rgba(1, 1, 1, 0.09)
    default property alias content: host.data
    // what the window's blur should follow, and its corner radius
    readonly property alias shapeItem: shape
    readonly property real radius: face.radius

    // the island's timeline: it grows for the first two thirds, joined with the bar, and only then pulls away
    readonly property real tc: Math.max(0, t)
    readonly property real openE: { const p = Math.max(0, Math.min(1, (tc - 0.08) / 0.64)); return p * p * (3 - 2 * p) }
    readonly property real dp: { const p = Math.max(0, Math.min(1, (tc - 0.66) / 0.34)); return p * p * (3 - 2 * p) }
    readonly property real w: fromW + (openW - fromW) * openE
    readonly property real h: pillH + (openH - pillH) * openE
    readonly property real x0: Math.max(12, Math.min(dc.width - openW - 12, ax - openW / 2))
    // the bar's own edges are in BarSvc (the menus are other windows and cannot read the bar). V7.15: the card is
    // the module's pill when it is small, inside the bar, and hangs from the bar's edge once it has width; so the
    // close lands the last pill on the module instead of dropping a nub under the bar, and the open never paints a
    // wide dark block over the bar's other modules
    readonly property real barLo: BarSvc.barInset
    readonly property real barHi: BarSvc.barInset + BarSvc.barH
    readonly property real pillTop: down ? barLo + (BarSvc.barH - pillH) / 2 : height - barHi + (BarSvc.barH - pillH) / 2
    readonly property real hang: down ? barHi : height - barHi
    readonly property real nearE: Math.min(1, openE * 3)
    readonly property real baseY: pillTop + (hang - pillTop) * nearE
    readonly property real restY: down ? barSpace + 8 : height - barSpace - openH - 8
    readonly property real sy: baseY + dp * (restY - baseY)
    readonly property real sideTop: Math.max(12, Math.min(height - openH - 12, (ay < 0 ? height / 2 : ay) - 30))
    // where the content sits in the window once the card is open (the shape moves over it)
    readonly property real hx: side ? (atRight ? width - sideSpace - openW - 8 : sideSpace + 8) : x0
    readonly property real hy: side ? sideTop : restY
    visible: t > 0.01
    // V7.15: it lands on the module as a small pill and fades into the bar over the last frames, as the island does;
    // without it the last pill (and the pop when the card was let go) sat under the bar instead of in it
    opacity: Math.min(1, tc * 6)
    Behavior on openH { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    // ---------- the strand: the card is one shape with the bar until it lets go ----------
    Shape {
        id: strand
        x: shape.x
        y: shape.y - height
        width: Math.max(1, shape.width)
        // from the card's top up to the bar's bottom edge: the card is one piece with the bar until it lets go
        height: Math.max(0, (dc.down ? shape.y - dc.barHi : 0))
        readonly property real tw0: Math.min(width * 0.62, dc.fromW * 0.9)
        readonly property real letgo: Math.max(0, Math.min(1, (dc.tc - 0.55) / 0.45))
        readonly property real tw: tw0 * Math.pow(1 - letgo, 2.2)
        readonly property real cx: Math.max(4, Math.min(width - 4, dc.ax - shape.x))
        readonly property bool joined: dc.down && !dc.side && dc.tc > 0.02 && height > 0.05 && tw >= 0.15
        visible: joined
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: dc.bg
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

    // ---------- the card ----------
    Item {
        id: shape
        x: dc.side ? (dc.atRight ? dc.width - dc.sideSpace - width : dc.sideSpace) + (dc.atRight ? -dc.dp * 8 : dc.dp * 8)
                   : (dc.ax + (dc.x0 + dc.openW / 2 - dc.ax) * dc.openE) - width / 2
        y: dc.side ? dc.sideTop + (dc.openH - height) / 2
                   : dc.sy
        width: Math.max(1, dc.w)
        height: Math.max(1, dc.h)
        clip: true
        Rectangle {
            id: face
            anchors.fill: parent
            radius: dc.rad <= 0.5 ? 0 : Math.min(height / 2, dc.pillH / 2 + (dc.rad - dc.pillH / 2) * dc.openE)
            color: dc.bg
            Frame { }      // V4.98 Minimal mode
        }
        // the content keeps its place while the shape opens over it
        Item {
            id: host
            x: dc.hx - shape.x; y: dc.hy - shape.y
            width: dc.openW; height: dc.openH
            opacity: Math.max(0, (dc.openE - 0.45) / 0.55)
        }
        // the glass line: only once the card is clearly away, so no line is ever drawn across the join
        Rectangle {
            anchors.fill: parent
            radius: face.radius
            color: "transparent"; border.width: 1; border.color: dc.line
            visible: opacity > 0.01
            opacity: dc.dp > 0.9 && !strand.joined ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }
}