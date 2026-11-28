import Quickshell
import Quickshell.Io
import QtQuick

// Settings > System > Care (V6.00): what the shell uses right now and how to make it lighter (rice-perf), cleaning
// up (rice-care), and the whole setup in one file (rice-backup). Updates live in one place: Update Center.
// Anything that needs your password opens in a terminal: nothing runs as root from here.
Item {
    id: page
    property var ctl
    property var perf: ({ rows: [], total: 0, fixes: [] })
    property var scan: null
    property bool scanning: false
    property var picked: ({})            // clean-up ids that are ticked
    property var backups: ({ folder: "", backups: [] })
    property string confirm: ""          // the backup asked to restore, waiting for "sure?"
    property bool busy: false
    property string waiting: ""          // V6.01: "clean" while its terminal works (then it looks again)

    function mb(b) { return b >= 1073741824 ? (b / 1073741824).toFixed(1) + " GB" : Math.max(0, Math.round(b / 1048576)) + " MB" }
    function status(s) { if (page.ctl) page.ctl.status = s }

    // ---------- what the shell uses: every few seconds while this page is on screen ----------
    Process {
        id: perfP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-perf\" json 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { page.perf = JSON.parse(text) } catch (e) { } } }
    }
    Timer { interval: 5000; repeat: true; triggeredOnStart: true; running: page.visible; onTriggered: if (!perfP.running) perfP.running = true }

    // ---------- the commands ----------
    Process {
        id: scanP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-care\" scan 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.scan = JSON.parse(text)
                    const p = {}
                    for (let i = 0; i < page.scan.items.length; i++) if (page.scan.items[i].size > 0) p[page.scan.items[i].id] = true
                    page.picked = p
                } catch (e) { page.scan = { items: [], total: 0 } }
                page.scanning = false
            }
        }
    }
    Process {
        id: listP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-backup\" list 2>/dev/null"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.backups = JSON.parse(text) } catch (e) { } } }
    }
    Process {
        id: doP
        property string done: ""
        stdout: StdioCollector { id: doOut }
        stderr: StdioCollector { id: doErr }
        onExited: function(code) {
            page.busy = false
            if (code !== 0) { const w = doErr.text.trim().split("\n").pop(); page.status(w !== "" ? w : I18n.t("That did not work")) }
            else if (doP.done === "clean") {
                let r = { freed: 0, terminal: false }
                try { r = JSON.parse(doOut.text) } catch (e) { }
                if (r.terminal) {
                    // V6.01: it used to look again at once, before your password was even typed, so nothing
                    // seemed to change. Now it waits for the terminal and then looks again
                    page.status(r.freed > 0 ? I18n.t("Freed %1 here; finish the rest in the terminal", page.mb(r.freed))
                                            : I18n.t("Finish it in the terminal; this list updates after"))
                    page.waitFor("clean")
                } else {
                    page.status(I18n.t("Freed %1", page.mb(r.freed)))
                    scanP.running = true; page.scanning = true
                }
            } else if (doP.done === "update") {
                page.status(I18n.t("The update goes on in the terminal"))
                page.waitFor("update")
            } else if (doP.done !== "") page.status(doP.done)
            listP.running = true
            if (!perfP.running) perfP.running = true
        }
    }
    Process {
        id: waitP
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-care\" wait 2>/dev/null"]
        onExited: {
            const w = page.waiting
            page.waiting = ""
            if (w === "clean") { page.scanning = true; scanP.running = true; page.status(I18n.t("Cleaned up")) }
            if (!perfP.running) perfP.running = true
        }
    }
    function waitFor(what) { if (waitP.running) return; waiting = what; waitP.running = true }
    function act(cmd, done) {
        if (doP.running) return
        busy = true; doP.done = done; doP.command = cmd; doP.running = true
    }

    PageScroll {
        anchors.fill: parent

        SectionTitle { text: I18n.t("Care"); sym: "health_and_safety"
            sub: I18n.t("Keep the shell light, and the computer up to date and clean. Whatever needs your password opens in a terminal.") }

        // ==================== what the shell uses ====================
        SectionTitle { text: I18n.t("What the shell uses"); sym: "memory"
            sub: I18n.t("Right now, part by part (memory each part really takes, and the processor)") }
        Rectangle {
            width: parent.width
            height: useCol.height + 32
            radius: M3.sq ? 0 : M3.rL
            color: M3.surfaceC
            Column {
                id: useCol
                x: 20; y: 16
                width: parent.width - 40
                spacing: 10
                Row {
                    spacing: 10
                    T { text: page.mb(page.perf.total || 0); font.pixelSize: 30; font.weight: Font.DemiBold; color: M3.primary }
                    T { anchors.baseline: parent.children[0].baseline; text: I18n.t("in all"); font.pixelSize: 14; color: M3.inkDim }
                }
                Repeater {
                    model: (page.perf.rows || []).slice(0, 8)
                    delegate: Item {
                        id: ur
                        required property var modelData
                        width: useCol.width; height: 30
                        readonly property real most: Math.max(1, (page.perf.rows && page.perf.rows.length) ? page.perf.rows[0].mem : 1)
                        T { width: 190; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight; font.pixelSize: 13
                            text: I18n.t(ur.modelData.name) + (ur.modelData.count > 1 ? "  ×" + ur.modelData.count : "") }
                        Rectangle {
                            x: 200; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 200 - 150; height: 10; radius: 5; color: M3.surfaceHigh
                            Rectangle {
                                width: Math.max(6, parent.width * ur.modelData.mem / ur.most); height: parent.height; radius: 5; color: M3.primary
                                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            }
                        }
                        T { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13; color: M3.inkDim
                            text: page.mb(ur.modelData.mem) + "   " + ur.modelData.cpu.toFixed(1) + "%" }
                    }
                }
                T { visible: (page.perf.rows || []).length === 0; text: I18n.t("Measuring..."); color: M3.inkDim; font.pixelSize: 13 }
            }
        }
        // one click lighter
        Repeater {
            model: page.perf.fixes || []
            delegate: Rectangle {
                id: fx
                required property var modelData
                width: parent.width
                height: Math.max(64, fxText.height + 28)
                radius: M3.sq ? 0 : M3.rM
                color: M3.surfaceC
                Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "bolt"; glyph: ""; size: 22; color: M3.primary }
                T {
                    id: fxText
                    x: 56; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56 - fxBtn.width - 36
                    wrapMode: Text.WordWrap; font.pixelSize: 13
                    text: I18n.t(fx.modelData.text) + (fx.modelData.frees > 0 ? "  " + I18n.t("(frees about %1)", page.mb(fx.modelData.frees)) : "")
                }
                Btn {
                    id: fxBtn
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    text: I18n.t(fx.modelData.label); enabled: !page.busy
                    onClicked: page.act(fx.modelData.cmd, I18n.t("Done: %1", I18n.t(fx.modelData.label)))
                }
            }
        }

        // ==================== clean up ====================
        SectionTitle { text: I18n.t("Clean up"); sym: "cleaning_services"
            sub: I18n.t("Old package files, packages nothing needs, old logs and caches. Nothing is removed before you press Clean.") }
        Row {
            spacing: 10
            Btn { sym: "search"; icon: ""; enabled: !page.scanning && page.waiting !== "clean"; text: page.scanning ? I18n.t("Looking...") : I18n.t("Look")
                onClicked: { page.scanning = true; scanP.running = true } }
            Btn {
                primary: true; sym: "delete_sweep"; icon: ""
                readonly property real sel: { let s = 0; if (page.scan) for (let i = 0; i < page.scan.items.length; i++) if (page.picked[page.scan.items[i].id]) s += page.scan.items[i].size; return s }
                visible: !!page.scan && (sel > 0 || page.waiting === "clean"); enabled: !page.busy && page.waiting === ""
                text: page.waiting === "clean" ? I18n.t("Cleaning in the terminal...") : I18n.t("Clean %1", page.mb(sel))
                onClicked: { const ids = Object.keys(page.picked).filter(function(k) { return page.picked[k] })
                             page.act(["bash", "-c", "\"$HOME/.local/bin/rice-care\" clean \"$@\"", "_"].concat(ids), "clean") }
            }
        }
        Repeater {
            model: page.scan ? page.scan.items : []
            delegate: Rectangle {
                id: ci
                required property var modelData
                readonly property bool on: !!page.picked[modelData.id]
                width: parent.width; height: 58
                radius: M3.sq ? 0 : M3.rM
                color: M3.surfaceC
                opacity: modelData.size > 0 ? 1 : 0.5
                Rectangle {
                    x: 18; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: M3.sq ? 0 : 6
                    color: ci.on ? M3.primary : "transparent"; border.width: 2; border.color: ci.on ? M3.primary : M3.inkDim
                    Icon { anchors.centerIn: parent; visible: ci.on; name: "check"; glyph: ""; size: 16; color: M3.inkPrimary }
                }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56 - 120
                    T { text: I18n.t(ci.modelData.name) + (ci.modelData.root ? "  ·  " + I18n.t("needs your password") : ""); font.pixelSize: 14 }
                    T { text: I18n.t(ci.modelData.desc); font.pixelSize: 12; color: M3.inkDim; elide: Text.ElideRight; width: parent.width }
                }
                T { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; text: page.mb(ci.modelData.size); font.pixelSize: 14; font.weight: Font.DemiBold }
                MouseArea {
                    anchors.fill: parent; enabled: ci.modelData.size > 0; cursorShape: Qt.PointingHandCursor
                    onClicked: { const p = Object.assign({}, page.picked); p[ci.modelData.id] = !ci.on; page.picked = p }
                }
            }
        }

        // ==================== backup ====================
        SectionTitle { text: I18n.t("Backup"); sym: "settings_backup_restore"
            sub: I18n.t("Your whole setup in one file: settings, themes, keybinds, window rules and the wallpaper. Put it back on a new install in one click.") }
        Row {
            spacing: 10
            Btn { primary: true; sym: "save"; icon: ""; enabled: !page.busy; text: I18n.t("Save a backup now")
                onClicked: page.act(["bash", "-c", "\"$HOME/.local/bin/rice-backup\" save"], I18n.t("Saved in DarkShadow-backups")) }
            Btn { sym: "folder_open"; icon: ""; text: I18n.t("Open the folder")
                onClicked: Quickshell.execDetached(["bash", "-c", "mkdir -p \"$HOME/DarkShadow-backups\"; xdg-open \"$HOME/DarkShadow-backups\""]) }
        }
        T { visible: (page.backups.backups || []).length === 0; text: I18n.t("No backups yet."); color: M3.inkDim; font.pixelSize: 13 }
        Repeater {
            model: (page.backups.backups || []).slice(0, 6)
            delegate: Rectangle {
                id: bk
                required property var modelData
                readonly property bool asking: page.confirm === modelData.path
                width: parent.width; height: 62
                radius: M3.sq ? 0 : M3.rM
                color: M3.surfaceC
                Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "inventory_2"; glyph: ""; size: 22; color: M3.primary }
                Column {
                    x: 56; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 56 - restoreBtn.width - 30
                    T { text: bk.modelData.made !== "" ? bk.modelData.made : bk.modelData.name; font.pixelSize: 14; elide: Text.ElideRight; width: parent.width }
                    T { font.pixelSize: 12; color: M3.inkDim; elide: Text.ElideRight; width: parent.width
                        text: (bk.modelData.name.indexOf("before-restore") === 0 ? I18n.t("Before a restore") + "  ·  " : "")
                              + (bk.modelData.version !== "" ? "V" + bk.modelData.version + "  ·  " : "") + page.mb(bk.modelData.size) + (bk.modelData.host !== "" ? "  ·  " + bk.modelData.host : "") }
                }
                Btn {
                    id: restoreBtn
                    anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    primary: bk.asking; enabled: !page.busy && bk.modelData.ok
                    text: bk.asking ? I18n.t("Sure? Replace my setup") : I18n.t("Restore")
                    onClicked: {
                        if (!bk.asking) { page.confirm = bk.modelData.path; return }
                        page.confirm = ""
                        page.act(["bash", "-c", "\"$HOME/.local/bin/rice-backup\" restore \"$1\"", "_", bk.modelData.path], I18n.t("Restored: your setup from before is kept too"))
                    }
                }
            }
        }
        Item { width: 1; height: 24 }
    }
}
