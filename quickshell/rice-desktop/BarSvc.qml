pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// What the bar asks the system: the Wi-Fi / Bluetooth / Do not disturb switches (rice-services) and the weather, for
// every bar at once. Since V4.55 "Bar on every screen" makes a bar for each screen, and each copy used to start its
// own rice-services every 8 s and its own rice-weather.
Singleton {
    id: svc
    property bool shown: false          // the top bar is on screen
    property bool sideShown: false      // the side bar (VBar) is on screen; only while one of them is, anything is asked
    property var state: ({})            // rice-services state
    property var wx: null               // rice-weather json
    function refresh() { if (!svcProc.running) svcProc.running = true }
    // after a click: rice-cc writes the new state first (it used to be a 700 ms timer in each bar)
    function refreshSoon() { soon.restart() }
    function refreshWx() { if (!wxProc.running) wxProc.running = true }
    Process {
        id: svcProc
        command: ["bash", "-c", "\"$HOME/.local/bin/rice-services\" state 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: { try { svc.state = JSON.parse(text) } catch (e) { } } }
    }
    // the switches change rarely from outside the shell (a click refreshes in 700 ms, below): 30 s is plenty and
    // keeps this from starting rice-services (a Python process and 6-9 subprocesses) 11 times a minute
    Timer { interval: 30000; running: svc.shown || svc.sideShown; repeat: true; triggeredOnStart: true; onTriggered: svc.refresh() }
    Timer { id: soon; interval: 700; onTriggered: svc.refresh() }
    Process {
        id: wxProc
        command: [Quickshell.env("HOME") + "/.local/bin/rice-weather", "json"]
        stdout: StdioCollector { onStreamFinished: { try { const j = JSON.parse(text.trim().split("\n").pop()); if (j && j.temp !== undefined) svc.wx = j } catch (e) { } } }
    }
}
