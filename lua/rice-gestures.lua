local home = os.getenv("HOME") or ""
local bin = home .. "/.local/bin/"

local function run(cmd)
    hl.dispatch(hl.dsp.exec_cmd(cmd))
end

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 3, direction = "up", action = function() run(bin .. "rice-taskview overview") end })
hl.gesture({ fingers = 3, direction = "down", action = "close" })
hl.gesture({ fingers = 3, direction = "pinchout", action = "fullscreen" })
hl.gesture({ fingers = 3, direction = "pinchin", action = function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })) end })

hl.gesture({ fingers = 4, direction = "up", action = function() run(bin .. "rice-dashboard open") end })
hl.gesture({ fingers = 4, direction = "down", action = function() run(bin .. "rice-cc") end })
hl.gesture({ fingers = 4, direction = "left", action = function() run(bin .. "rice-taskview switch") end })
hl.gesture({ fingers = 4, direction = "right", action = function() run(bin .. "rice-taskview back") end })
hl.gesture({ fingers = 4, direction = "pinchin", action = function() run(bin .. "rice-lock") end })
hl.gesture({ fingers = 4, direction = "pinchout", action = function() hl.dispatch(hl.dsp.workspace.toggle_special("magic")) end })

hl.gesture({ fingers = 3, direction = "up", mods = "SUPER", action = function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })) end })
hl.gesture({ fingers = 3, direction = "down", mods = "SUPER", action = function() hl.dispatch(hl.dsp.workspace.toggle_special("magic")) end })
hl.gesture({ fingers = 3, direction = "left", mods = "SUPER", action = function() hl.dispatch(hl.dsp.focus({ workspace = "e-1" })) end })
hl.gesture({ fingers = 3, direction = "right", mods = "SUPER", action = function() hl.dispatch(hl.dsp.focus({ workspace = "e+1" })) end })
