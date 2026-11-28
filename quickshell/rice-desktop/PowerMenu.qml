import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The power menu: click the power icon on the bar and it drops down under it.
// Lock, Sleep, Log out, Restart, Shut down. The last three need a second click, so nothing happens by accident.
PanelWindow {
    screen: Mon.screen
    id: pw
    // Minimal mode: the bar's own tinted surface, so the menu matches the bar (V5.02: it was near black)
    NPal { id: sqPal; theme: "shell"; alpha: Math.min(1, BarSvc.barAlpha + 0.04) }
    property bool open: false
    property real t: 0
    // V7.14: the Dynamic island's motion, 520 ms both ways; DropCard does the growing shape and the gap
    Behavior on t { NumberAnimation { duration: Look.lite ? 240 : 520; easing.type: Easing.InOutCubic } }
    readonly property real et: t
    onOpenChanged: t = open ? 1 : 0

    readonly property color fg: "#F6F5F4"
    readonly property color dim: Qt.rgba(0.965, 0.961, 0.957, 0.6)
    readonly property color line: Qt.rgba(1, 1, 1, 0.09)
    readonly property color bg: sqPal.surface
    property var bc: ({})
    // V4.95: opened from the dock ("dock:SPACE" after the place): it opens above the dock, not by the bar
    property real dockSpace: -1
    readonly property bool fromDock: dockSpace >= 0
    readonly property bool atBottom: fromDock || bc.position === "bottom"
    readonly property real barSpace: fromDock ? dockSpace : ((bc.enabled === false ? 34 : (bc.height ? bc.height : 38)) + (bc.style === "flat" ? 0 : 16) + 8)
    property real cx: 0
    // the bar on the left or right edge (VBar.qml): the menu opens beside the bar, level with the icon (cy)
    property real cy: -1
    readonly property bool side: !fromDock && (bc.position === "left" || bc.position === "right")
    readonly property bool atRight: bc.position === "right"
    readonly property real sideSpace: (bc.enabled === false ? 34 : (bc.height ? bc.height + 4 : 42)) + (bc.style === "flat" ? 0 : 16) + 8
    property string armed: ""          // the action that waits for its second click
    property int hover: -1

    readonly property var items: [
        { key: "lock", label: Tr.t("Lock"), icon: "lock", glyph: 0xF033E, cmd: "\"$HOME/.local/bin/rice-power\" lock", ask: false },
        { key: "suspend", label: Tr.t("Sleep"), icon: "bedtime", glyph: 0xF0904, cmd: "\"$HOME/.local/bin/rice-power\" lock; sleep 0.6; \"$HOME/.local/bin/rice-sys\" suspend", ask: false },
        { key: "logout", label: Tr.t("Log out"), icon: "logout", glyph: 0xF0343, cmd: "\"$HOME/.local/bin/logout\"", ask: true },
        { key: "reboot", label: Tr.t("Restart"), icon: "restart_alt", glyph: 0xF0709, cmd: "\"$HOME/.local/bin/rice-sys\" reboot", ask: true },
        { key: "poweroff", label: Tr.t("Shut down"), icon: "power_settings_new", glyph: 0xF0425, cmd: "\"$HOME/.local/bin/rice-sys\" poweroff", ask: true }
    ]
    function run(it) {
        if (it.ask && armed !== it.key) { armed = it.key; Sfx.play("click"); disarm.restart(); return }
        Sfx.play("select")
        hide()
        Quickshell.execDetached(["bash", "-c", "sleep 0.15; " + it.cmd])
    }
    Timer { id: disarm; interval: 3000; onTriggered: pw.armed = "" }

    Process {
        id: barProc
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-bar\" state 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { pw.bc = JSON.parse(text) } catch (e) { } } }
    }
    function show(x, y) { cy = (y === undefined || isNaN(y)) ? -1 : y; cx = x; armed = ""; barProc.running = true; open = true }
    function hide() { open = false; armed = "" }
    Trigger {
        name: "power-open"; fresh: true
        onFired: function(o) {
            const x = parseFloat(o.split(" ")[1]), y2 = o.split(" ")[2] || "", yv = parseFloat(y2)
            pw.dockSpace = y2.indexOf("dock:") === 0 ? (parseFloat(y2.substring(5)) || 80) : -1
            if (pw.open) pw.hide(); else pw.show(isNaN(x) ? pw.width - 120 : x, yv)
        }
    }

    visible: open || (t > 0.01 && !closeT.done)
    // if the closing animation ever stalls (the compositor sent no frames for a moment), it still goes away
    Timer { id: closeT; property bool done: false; interval: 600; running: !open; onRunningChanged: if (running) done = false; onTriggered: done = true }
    // niri: blur behind the card (Hyprland blurs this layer with its own rule)
    NiriBlur { win: pw; items: [card.shapeItem]; radius: card.radius; on: pw.open && pw.et > 0.94 }
    color: "transparent"
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "rice-power"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    MouseArea { anchors.fill: parent; onClicked: pw.hide() }

    DropCard {
        id: card
        anchors.fill: parent
        t: pw.et
        openW: 220
        openH: col.height + 16
        fromW: 38; pillH: 26
        ax: pw.cx; ay: pw.cy
        side: pw.side; atRight: pw.atRight; down: !pw.atBottom
        barSpace: pw.barSpace; sideSpace: pw.sideSpace
        rad: Look.sq ? 0 : 20
        bg: pw.bg; line: pw.line
        focus: true
        Keys.onEscapePressed: pw.hide()
        MouseArea { anchors.fill: parent }

        Column {
            id: col
            x: 8; y: 8; width: parent.width - 16
            Repeater {
                model: pw.items
                delegate: Item {
                    id: row
                    readonly property bool hot: pw.armed === modelData.key
                    readonly property bool danger: modelData.key === "poweroff" || modelData.key === "reboot"
                    readonly property bool red: modelData.key === "poweroff"           // Shut down is always red
                    width: col.width; height: 44
                    opacity: 0
                    property real slide: -8
                    transform: Translate { y: row.slide }
                    Component.onCompleted: enter.start()
                    SequentialAnimation { id: enter
                        PauseAnimation { duration: index * 28 }
                        ParallelAnimation {
                            NumberAnimation { target: row; property: "opacity"; to: 1; duration: 180 }
                            NumberAnimation { target: row; property: "slide"; to: 0; duration: 240; easing.type: Easing.OutCubic }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2; radius: Look.sq ? 0 : (13)
                        color: row.hot ? (row.danger ? Qt.rgba(1, 0.42, 0.42, 0.22) : Qt.rgba(1, 1, 1, 0.14)) : (rm.containsMouse ? (row.red ? Qt.rgba(1, 0.42, 0.42, 0.14) : Qt.rgba(1, 1, 1, 0.07)) : "transparent")
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                    MIcon { x: 14; anchors.verticalCenter: parent.verticalCenter; size: 19; name: modelData.icon; glyph: String.fromCodePoint(modelData.glyph)
                        color: (row.hot && row.danger) || row.red ? "#ff8a8a" : pw.fg }
                    Text { x: 46; anchors.verticalCenter: parent.verticalCenter; font.family: Fonts.main; font.pixelSize: 14
                        text: row.hot ? Tr.t("Click again: ") + modelData.label.toLowerCase() : modelData.label
                        color: (row.hot && row.danger) || row.red ? "#ff8a8a" : pw.fg }
                    MouseArea { id: rm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pw.run(modelData) }
                }
            }
        }
    }
}
