-- Infinite Desktop's Lua config with a fake Hyprland: the two screen modes (Settings > Desktop > Infinite Desktop >
-- Screens), a new window on the second screen, and turning it off. Run by tests/infinite.sh, once as 0.55 (no
-- hl.is_key_down: rice-canvasd) and once as 0.56+ (RI_TEST_POLL=1: the pointer itself, and the warp at the edge).
local path = arg[1]
local POLL = os.getenv("RI_TEST_POLL") == "1"
local moves, focuses, floatarr, events, anims = {}, {}, {}, {}, {}
local keys, timers, warps = {}, {}, {}
local timer
local n = 0
local function ok(msg) n = n + 1; print("ok " .. n .. " - " .. msg) end
local function bad(msg) print("not ok " .. (n + 1) .. " - " .. msg); os.exit(1) end
local function check(c, msg) if c then ok(msg) else bad(msg) end end
local function rec(d) if type(d) == "function" then d() else events[#events + 1] = d end end

local function mon(name, x, y)
    return { name = name, x = x, y = y, width = 1920, height = 1080, scale = 1, reserved = { left = 0, top = 0, right = 0, bottom = 0 } }
end
local M1, M2 = mon("DP-1", 0, 0), mon("HDMI-A-1", 1920, 0)

local function win(addr, wsid, m, x, y, w, h)
    return { address = addr, workspace = { id = wsid }, monitor = m, at = { x = x, y = y }, size = { x = w or 400, y = h or 300 },
        mapped = true, hidden = false, floating = true, pinned = false, fullscreen = 0, class = "app" }
end
local W = { win("0xa", 1, M1, 100, 100), win("0xb", 11, M2, 100, 100) }
local active_ws, cursor = 1, { x = 100, y = 100 }
local function at(t, fn) for _, w in ipairs(W) do if "address:" .. w.address == t.window then fn(w) end end end

hl = {
    on = function() end, bind = function() end, unbind = function() end, exec_cmd = function() end,
    animation = function(t) anims[#anims + 1] = t end,
    get_windows = function() return W end,
    get_active_workspace = function() return { id = active_ws } end,
    get_active_window = function() return W[1] end,
    get_active_monitor = function() return M1 end,
    get_cursor_pos = function() return cursor end,
    get_monitor_at = function(x) return x >= 1920 and M2 or M1 end,
    dispatch = rec,
    dsp = {
        window = {
            move = function(t) return function() moves[#moves + 1] = t; at(t, function(w) w.at.x, w.at.y = t.x, t.y end) end end,
            resize = function(t) return function() at(t, function(w) w.size.x, w.size.y = t.x, t.y end) end end,
            float = function(t) return function() floatarr[#floatarr + 1] = t.action end end,
            close = function() return function() end end,
        },
        focus = function(t) return function() focuses[#focuses + 1] = t; if t.workspace then active_ws = t.workspace end end end,
        exec_cmd = function() return function() end end,
    },
}
if POLL then
    hl.is_key_down = function(sym) return keys[sym] == true end
    hl.timer = function(fn, opts)
        local t = { ms = opts.timeout }
        function t:set_timeout(ms) self.ms = ms end
        timers[#timers + 1] = fn
        timer = t
        return t
    end
    hl.dsp.cursor = { move = function(t) return function() warps[#warps + 1] = t; cursor.x, cursor.y = t.x, t.y end end }
end
assert(loadfile(path))()
check(POLL == (type(hl.is_key_down) == "function"), "the fake Hyprland has hl.is_key_down, or not")

-- screens = 1: only the workspace it was turned on
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
check(RiceInfinite.on, "it is on")
local before = #moves
RiceInfinite.pan(100, 0)
local a = 0
for i = before + 1, #moves do if moves[i].window == "address:0xa" then a = a + 1 end end
check(a > 0, "screens = 1: the window of the workspace moves")
local b = 0
for i = before + 1, #moves do if moves[i].window == "address:0xb" then b = b + 1 end end
check(b == 0, "screens = 1: the window of the other screen stays")
RiceInfinite.set(false)
check(not RiceInfinite.on, "it is off")

-- screens = 0: every screen, but only the workspace each screen shows (a window on another workspace stays)
RiceInfinite.cfg.screens = 0
M1.active_workspace = { id = 1 }
W = { win("0xa", 1, M1, 100, 100), win("0xb", 11, M2, 1970, 100), win("0xd", 2, M1, 100, 100) }
before = #moves
RiceInfinite.set(true)
check(RiceInfinite.on, "it is on with every screen")
RiceInfinite.pan(100, 0)
a, b = 0, 0
for i = before + 1, #moves do
    if moves[i].window == "address:0xa" then a = a + 1 end
    if moves[i].window == "address:0xb" then b = b + 1 end
end
check(a > 0 and b > 0, "screens = 0: the windows of both screens move")
local d = 0
for i = before + 1, #moves do if moves[i].window == "address:0xd" then d = d + 1 end end
check(d == 0, "screens = 0: a window on a workspace no screen shows stays")
table.remove(W, 3)

-- a window that opens on the second screen gets its room there, inside that screen
cursor = { x = 2000, y = 300 }
local fresh = win("0xc", 11, M2, 2000, 300, 700, 500)
fresh.floating = false
W[#W + 1] = fresh
RiceInfinite.opened(fresh)
check(fresh.at.x >= 1920 and fresh.at.x + fresh.size.x <= 3840, "the new window stays on its own screen")

-- off: every screen is put back and tiled again
RiceInfinite.set(false)
check(floatarr[#floatarr] == "unset", "off tiles it again")
check(focuses[#focuses].window == "address:0xc", "the new window was focused")
check(not RiceInfinite.on, "it is off again")

-- a window that got its canvas place while the view was panned: turning it off brings the window back on screen
active_ws = 1
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
RiceInfinite.pan(5000, 0)
local stray = win("0xe", 1, M1, 3000, 200, 400, 300)
W[#W + 1] = stray
RiceInfinite.opened(stray)
RiceInfinite.set(false)
check(stray.at.x >= M1.x and stray.at.x + stray.size.x <= M1.x + 1920
      and stray.at.y >= M1.y and stray.at.y + stray.size.y <= M1.y + 1080,
    "off brings a window placed on a panned canvas back on screen")

-- a floating window that only stuck out of the screen came back half off and looked gone: off keeps the whole
-- rectangle inside the monitor now (Settings is the usual one; a tiled Firefox was retiled and stayed visible)
active_ws = 99
local edge = win("0xf", 99, M1, -180, 120, 420, 300)
W = { edge }
RiceInfinite.cfg.screens = 1
RiceInfinite.set(true)
RiceInfinite.set(false)
check(edge.at.x >= M1.x + 24 and edge.at.x + edge.size.x <= M1.x + 1920
      and edge.at.y >= M1.y + 24 and edge.at.y + edge.size.y <= M1.y + 1080,
    "off clamps a floating window that only stuck out of the screen")

-- 0.56+: the pointer itself, no input group (and the warp at the edge of the screen)
local function tick() for _, f in ipairs(timers) do f() end end
local function ticks() for _ = 1, 16 do tick() end end     -- 16 ms of the timer (16 ticks while held, one when idle)
local function hold(x, y)
    keys = { Super_L = true, Alt_L = true }
    cursor = { x = x, y = y or 500 }
    ticks()
end
local function move(x, y) cursor = { x = x, y = y or 500 }; ticks() end
local function let_go() keys = {}; ticks() end
if POLL then
    check(type(hl.is_key_down) == "function" and #timers == 1, "the pointer is followed by a timer")
    os.execute("mkdir -p " .. (os.getenv("HOME") or "") .. "/.config/rice")
    RiceInfinite.set(true)
    RiceInfinite.cfg.speed, RiceInfinite.cfg.dir = 1.0, 1
    local ox = RiceInfinite.ox
    hold(500)                                     -- the hold starts: no move yet
    check(RiceInfinite.ox == ox, "holding the keys alone moves nothing")
    check(timer.ms == 1, "while the keys are held the pointer is followed every millisecond")
    move(540)
    check(math.abs(RiceInfinite.ox - ox - 40) < 0.001, "the pointer moves the canvas with it")
    check(anims[#anims] and anims[#anims].leaf == "windowsMove" and anims[#anims].enabled == false,
        "the window move animation is off while the canvas is dragged")
    local live = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.live")
    local t = live and live:read("a") or ""
    if live then live:close() end
    check(t:match("hold 1") ~= nil and t:match("ox=") ~= nil, "the shell is told the canvas is held and where")

    -- at the edge the pointer is put back a little (it cannot leave the screen), so the canvas goes on
    let_go()
    hold(1915)
    ox = RiceInfinite.ox
    move(1919)
    check(#warps > 0 and warps[#warps].x == 1896, "at the edge the pointer is put back inside")
    check(math.abs(RiceInfinite.ox - ox - 4) < 0.001, "the move to the edge still moves it")
    ox = RiceInfinite.ox
    move(1900)
    check(math.abs(RiceInfinite.ox - ox - 4) < 0.001, "the jump back is not counted as movement")

    -- SUPER + ALT + another one of these keys: not the hold (SUPER + CTRL is Next window)
    keys.Control_L = true
    ox = RiceInfinite.ox
    move(1910)
    check(RiceInfinite.ox == ox, "SUPER + ALT + CTRL does not move the canvas")
    keys.Control_L = nil
    tick()                                        -- the hold starts again here (the pointer does not jump)
    ox = RiceInfinite.ox

    -- reversed: the canvas goes the other way
    RiceInfinite.cfg.dir = 2
    move(1890)
    check(math.abs(RiceInfinite.ox - ox - 20) < 0.001, "dir = 2 moves the canvas the other way")
    RiceInfinite.cfg.dir = 1

    -- letting go writes the place down and tells the shell
    let_go()
    check(anims[#anims] and anims[#anims].leaf == "windowsMove" and anims[#anims].enabled == true,
        "the window move animation is back after the drag")
    local st = io.open(os.getenv("HOME") .. "/.config/rice/infinite.state")
    local stt = st and st:read("a") or ""
    if st then st:close() end
    check(stt:match("on=1") ~= nil, "letting go saves the place")
    live = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.live")
    t = live and live:read("a") or ""
    if live then live:close() end
    check(t:match("hold 0") ~= nil, "letting go tells the shell")
    check(timer.ms == 16, "letting go follows it every 16 ms again")
    RiceInfinite.set(false)
else
    check(#timers == 0, "0.55: no timer, rice-canvasd reads the mouse instead")
end
check((function() local f = io.open(os.getenv("XDG_RUNTIME_DIR") .. "/rice-infinite.poll"); if f then f:close() return true end return false end)() == POLL,
    "the marker for Settings follows the Hyprland")
