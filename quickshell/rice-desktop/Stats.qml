pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// CPU, RAM, swap, disk and GPU for every widget from one rice-stats process. Each widget used to start its own,
// so a desktop with resources + gauge + trio + the bar's system monitor sampled the machine four times at once.
Singleton {
    id: stats
    property var st: ({ cpu: 0, ram: 0, gpu: 0 })
    property bool haveGpu: false
    Process {
        command: [Quickshell.env("HOME") + "/.local/bin/rice-stats"]
        running: true
        stdout: SplitParser {
            onRead: function(l) {
                try {
                    const j = JSON.parse(l)
                    stats.st = j
                    if (!stats.haveGpu && (j.gpu > 0 || j.gtemp > 0)) stats.haveGpu = true
                } catch (e) { }
            }
        }
    }
}
