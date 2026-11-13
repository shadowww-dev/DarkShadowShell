import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: page
    property var ctl
    readonly property bool niri: !!Quickshell.env("NIRI_SOCKET")
    property var st: ({
        hypr: true,
        padFound: true,
        padName: "",
        natural_scroll: false,
        tap_to_click: true,
        scroll_factor: 1.0,
        sensitivity: 0.0,
        swipe_3_workspace: true,
        swipe_3_up: "taskview",
        swipe_3_down: "close",
        pinch_3: true,
        swipe_4_up: "dashboard",
        swipe_4_down: "cc",
        swipe_4_horizontal: "switch",
        pinch_4: true
    })

    function sh(args) { runner.command = ["bash", "-c", "\"$HOME/.local/bin/rice-gestures\" \"$@\" 2>&1", "_"].concat(args); runner.running = true }
    function set(k, v) { page.sh(["set", k, String(v)]); const n = Object.assign({}, page.st); n[k] = v; page.st = n; page.ctl.status = I18n.t("Applied") }

    Process {
        id: stateProc
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-gestures\" state"]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { page.st = JSON.parse(text) } catch (e) { } } }
    }
    Process { id: runner; stdout: StdioCollector { onStreamFinished: stateLater.restart() } }
    Timer { id: stateLater; interval: 350; onTriggered: stateProc.running = true }
    Timer { interval: 2500; running: page.visible; repeat: true; onTriggered: if (!stateProc.running) stateProc.running = true }
    onVisibleChanged: if (visible) stateProc.running = true

    component GesturePick: SettingRow {
        property string key: ""
        property var choices: []
        reserved: 340
        Seg {
            anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
            options: parent.choices
            current: String(page.st[parent.key] || (parent.choices[0] && parent.choices[0].value) || "")
            onChosen: v => page.set(parent.key, v)
        }
    }

    component GestureRow: Rectangle {
        property string fingers: ""
        property string gesture: ""
        property string action: ""
        property string sym: "touch_app"
        width: parent ? parent.width : 400
        height: 54
        radius: M3.rM
        color: gh.hovered ? M3.surfaceHigh : "transparent"
        Behavior on color { ColorAnimation { duration: 160 } }
        HoverHandler { id: gh }
        Row {
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            Rectangle {
                width: 32; height: 32; radius: 16
                color: M3.secondaryContainer
                anchors.verticalCenter: parent.verticalCenter
                Icon { anchors.centerIn: parent; name: parent.parent.parent.sym; glyph: ""; size: 16; color: M3.inkSecondaryC }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                T { text: parent.parent.parent.action; font.pixelSize: 13; font.weight: Font.Medium }
                T { kind: "reading"; text: parent.parent.parent.gesture; font.pixelSize: 11; color: M3.inkDim }
            }
        }
        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            height: 28; width: fLabel.implicitWidth + 20; radius: 8 * M3.shapeK
            color: M3.surfaceHighest
            border.width: 1; border.color: M3.outlineVariant
            T { id: fLabel; anchors.centerIn: parent; text: parent.parent.fingers; font.pixelSize: 11; font.weight: Font.DemiBold; color: M3.ink }
        }
    }

    PageScroll {
        anchors.fill: parent

        Rectangle {
            width: parent.width
            height: 180
            radius: M3.rXL
            color: M3.primaryContainer
            clip: true
            Blob {
                width: 240; height: 240; x: parent.width - 180; y: -40
                kind: "puffy"; color: M3.alpha(M3.inkPrimaryC, 0.08)
                RotationAnimator on rotation { from: 0; to: 360; duration: 55000; loops: Animation.Infinite; running: page.visible }
            }
            Item {
                x: 24; anchors.verticalCenter: parent.verticalCenter
                width: 88; height: 88
                Blob { anchors.fill: parent; kind: Prefs.accentShape; color: M3.primary }
                Icon { anchors.centerIn: parent; name: "touch_app"; glyph: "\uf245"; size: 36; color: M3.inkPrimary }
            }
            Column {
                x: 136; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 136 - 24
                spacing: 4
                T { text: I18n.t("TOUCHPAD GESTURES"); font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 1.2; color: M3.alpha(M3.inkPrimaryC, 0.75) }
                T { kind: "title"; text: I18n.t("Swipe & pinch with your fingers"); font.pixelSize: 24; font.weight: Font.Medium; color: M3.inkPrimaryC }
                T { kind: "reading"; width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 13; color: M3.alpha(M3.inkPrimaryC, 0.85)
                    text: I18n.t("Switch workspaces, summon the Task view, open the control center, and zoom the canvas seamlessly with 3 and 4-finger gestures.") }
            }
        }

        Rectangle {
            id: devCard
            readonly property bool hasPad: (page.st.devices && page.st.devices.pads > 0) || page.st.padFound
            width: parent.width; height: 68; radius: M3.rL
            color: hasPad ? M3.surfaceC : M3.alpha(M3.primary, 0.10)
            border.width: hasPad ? 0 : 1; border.color: M3.alpha(M3.primary, 0.35)
            Rectangle {
                x: 18; anchors.verticalCenter: parent.verticalCenter; width: 36; height: 36; radius: 18
                color: devCard.hasPad ? M3.secondaryContainer : M3.primaryContainer
                Icon { anchors.centerIn: parent; name: devCard.hasPad ? "touch_app" : "info"; glyph: ""; size: 18
                    color: devCard.hasPad ? M3.inkSecondaryC : M3.inkPrimaryC }
            }
            Column {
                x: 66; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 86
                spacing: 3
                T { font.pixelSize: 14; font.weight: Font.DemiBold; text: devCard.hasPad ? I18n.t("Touchpad ready") : I18n.t("No touchpad detected") }
                T { font.pixelSize: 12; color: M3.inkDim; text: devCard.hasPad ? (page.st.padName ? page.st.padName + "  ·  " + I18n.t("Hardware active") : I18n.t("Touchpad hardware active and reporting multi-touch")) : I18n.t("Plug in or enable a touchpad to use multi-finger gestures.") }
            }
        }

        SectionTitle { text: I18n.t("Touchpad behavior"); sub: I18n.t("Natural scroll direction, tap to click and pointer speed.") }
        ToggleRow {
            label: I18n.t("Natural scrolling")
            desc: I18n.t("Content follows your fingers, like touching a glass screen")
            checked: page.st.natural_scroll === true
            onToggled: v => page.set("natural_scroll", v)
        }
        ToggleRow {
            label: I18n.t("Tap to click")
            desc: I18n.t("Tap with one finger to click, tap with two fingers for right click")
            checked: page.st.tap_to_click === true
            onToggled: v => page.set("tap_to_click", v)
        }
        SliderRow {
            label: I18n.t("Scroll speed")
            desc: I18n.t("How fast content moves when scrolling with two fingers")
            from: 0.4; to: 2.5; step: 0.1; decimals: 1; unit: "x"
            value: page.st.scroll_factor || 1.0
            onCommitted: v => page.set("scroll_factor", v)
        }
        SliderRow {
            label: I18n.t("Pointer speed")
            desc: I18n.t("Sensitivity of the mouse and touchpad pointer")
            from: -0.8; to: 0.8; step: 0.05; decimals: 2; unit: ""
            value: page.st.sensitivity || 0.0
            onCommitted: v => page.set("sensitivity", v)
        }

        SectionTitle { text: I18n.t("Three fingers"); sub: I18n.t("Switch workspaces, summon the Task view overview and manage windows.") }
        ToggleRow {
            label: I18n.t("Swipe horizontal to switch workspaces")
            desc: I18n.t("Swipe 3 fingers left or right to slide between workspaces smoothly")
            checked: page.st.swipe_3_workspace !== false
            onToggled: v => page.set("swipe_3_workspace", v)
        }
        GesturePick {
            label: I18n.t("Swipe up")
            desc: I18n.t("Open the Task view overview or make the window fullscreen")
            key: "swipe_3_up"
            choices: [{ value: "taskview", label: I18n.t("Task view") }, { value: "fullscreen", label: I18n.t("Fullscreen") }, { value: "none", label: I18n.t("Off") }]
        }
        GesturePick {
            label: I18n.t("Swipe down")
            desc: I18n.t("Close the active window or hide it in the scratchpad")
            key: "swipe_3_down"
            choices: [{ value: "close", label: I18n.t("Close window") }, { value: "magic", label: I18n.t("Scratchpad") }, { value: "none", label: I18n.t("Off") }]
        }
        ToggleRow {
            label: I18n.t("Pinch to fullscreen or float")
            desc: I18n.t("Pinch out to fullscreen the window, pinch in to float or tile it")
            checked: page.st.pinch_3 !== false
            onToggled: v => page.set("pinch_3", v)
        }

        SectionTitle { text: I18n.t("Four fingers"); sub: I18n.t("Summon the dynamic island, open the control center, switch apps and lock.") }
        GesturePick {
            label: I18n.t("Swipe up")
            desc: I18n.t("Open the dynamic island dashboard or the application launcher")
            key: "swipe_4_up"
            choices: [{ value: "dashboard", label: I18n.t("Dashboard") }, { value: "launcher", label: I18n.t("Launcher") }, { value: "none", label: I18n.t("Off") }]
        }
        GesturePick {
            label: I18n.t("Swipe down")
            desc: I18n.t("Show the control center with switches, volume, brightness and notifications")
            key: "swipe_4_down"
            choices: [{ value: "cc", label: I18n.t("Control center") }, { value: "none", label: I18n.t("Off") }]
        }
        GesturePick {
            label: I18n.t("Swipe horizontal")
            desc: I18n.t("Quickly switch between open windows like Alt + Tab")
            key: "swipe_4_horizontal"
            choices: [{ value: "switch", label: I18n.t("App switcher") }, { value: "none", label: I18n.t("Off") }]
        }
        ToggleRow {
            label: I18n.t("Pinch to lock or scratchpad")
            desc: I18n.t("Pinch in with 4 fingers to lock the screen, pinch out for the magic scratchpad")
            checked: page.st.pinch_4 !== false
            onToggled: v => page.set("pinch_4", v)
        }

        SectionTitle { text: I18n.t("Infinite Desktop"); sub: I18n.t("Touchpad controls on the infinite floating canvas.") }
        Rectangle {
            width: parent.width; height: igList.implicitHeight; radius: M3.rL; color: M3.surfaceC; clip: true
            Column {
                id: igList
                width: parent.width
                GestureRow { fingers: I18n.t("2 fingers"); gesture: I18n.t("Pinch together or apart"); action: I18n.t("Continuous 1:1 zoom around pointer"); sym: "zoom_in" }
                GestureRow { fingers: I18n.t("Super + Alt"); gesture: I18n.t("Hold keys and move finger / 2-finger scroll"); action: I18n.t("Pan the infinite canvas"); sym: "pan_tool" }
                GestureRow { fingers: I18n.t("Super + 3 fingers"); gesture: I18n.t("Swipe left, right, up or down"); action: I18n.t("Glide canvas to the next window"); sym: "arrow_forward" }
                GestureRow { fingers: I18n.t("Super + Alt + 0"); gesture: I18n.t("Press 0 while holding keys"); action: I18n.t("Reset canvas zoom to 100%"); sym: "restart_alt" }
            }
        }
    }
}
