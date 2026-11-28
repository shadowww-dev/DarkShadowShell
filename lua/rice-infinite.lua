-- Infinite Desktop is based on the idea of Sarods2D: https://github.com/sarodscommits/hyprland-infinitie-desktop-v2 (MIT)
-- DarkShadow's Shell: Infinite Desktop (Settings > Desktop > Infinite Desktop, or SUPER + F)
-- The windows of a workspace float on an endless canvas. While it is on:
--   CTRL + mouse wheel          zoom out / in around the pointer (the windows get smaller and come together)
--   SUPER + mouse wheel         move the canvas up / down      SUPER + SHIFT + wheel: left / right
--   SUPER + ALT + arrows        move the canvas
--   hold SUPER + ALT            move the mouse: the canvas moves with it, live (no input group: a timer follows the
--                               pointer; before Hyprland 0.56 rice-canvasd reads the mouse, which needs the group)
--   SUPER + drag a window       against the edge of the screen it pushes the others away (rice-canvasd reads the
--                               mouse directly for that, which needs the input group; the rest needs nothing)
--   (these two also work while it is off, on the floating windows of the workspace you are on)
--   SUPER + ALT + 0             back to 100 %
--   SUPER + CTRL + arrows       go to the next window that way: the canvas glides until it is in the middle
-- A new window does not land on top of the others: it gets its own place next to the one you were in, and the
-- canvas glides to it (the pointer follows), so there is always room.
-- Turning it off puts every window back where it was and tiles again the ones that were tiled.
-- Every screen is a part of the same canvas (Settings > Desktop > Infinite Desktop > Screens): the windows of every
-- screen float side by side as the screens are, and a new window gets its room on its own screen. "This workspace"
-- (screens = 1) keeps the canvas on the workspace you turned it on.
-- Everything is guarded: if something is missing in this Hyprland, the rest of the config still loads.

local RI = {}
RiceInfinite = RI

local HOME = os.getenv("HOME") or ""
local STATE = HOME .. "/.config/rice/infinite.state"
local CONF = HOME .. "/.config/rice/infinite.conf"
local LAYOUT = HOME .. "/.config/rice/infinite-layout"
local RUN = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local LIVE = RUN .. "/rice-infinite.live"      -- what moves while you hold the keys (Infinite.qml reads it)
local MARK = RUN .. "/rice-infinite.poll"      -- "this config follows the pointer itself": rice-infinite state
-- Hyprland 0.56 tells a config which keys are held (hl.is_key_down) and where the pointer is: then the mouse needs no
-- permission at all. Before it, rice-canvasd reads /dev/input, which needs the input group.
local CAN_POLL = type(hl.is_key_down) == "function" and type(hl.timer) == "function"
local CAN_WARP = CAN_POLL and type(hl.dsp) == "table" and type(hl.dsp.cursor) == "table" and type(hl.dsp.cursor.move) == "function"

RI.on = false
RI.ws = nil
RI.z, RI.ox, RI.oy = 1.0, 0, 0
RI.world = {}      -- address -> { x, y, w, h } on the canvas (screen = offset + canvas * zoom)
RI.tiled = {}      -- address -> true: it was tiled before, tile it again when turned off
RI.cfg = { step = 0.12, min = 0.2, max = 1.0, pan = 180, screens = 0, speed = 1.0, dir = 1 }   -- V7.16: every screen by default

local function run(d)
    if d then pcall(hl.dispatch, d) end
end

-- every screen is one canvas (screens = 0, the default), or only the workspace it was turned on (screens = 1)
local function shared()
    return tonumber(RI.cfg.screens) ~= 1
end

local function sel(w)
    local a = tostring(w.address or "")
    if a:sub(1, 2) ~= "0x" then a = "0x" .. a end
    return "address:" .. a
end

local bind_keys, unbind_keys

-- your keys (Settings > Desktop > Infinite Desktop > Keys): on / off, the keys you hold (with the mouse or the
-- arrows), the ones for going to the next window, and the one for zooming with the wheel
RI.keys = { key_toggle = "SUPER + F", mod_hold = "SUPER + ALT", mod_go = "SUPER + CTRL", mod_zoom = "CTRL" }

function RI.load_cfg()
    local f = io.open(CONF, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*(%w+)%s*=%s*([%d%.]+)%s*$")
        if k and RI.cfg[k] ~= nil and tonumber(v) then RI.cfg[k] = tonumber(v) end
        local kk, kv = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if kk and RI.keys[kk] ~= nil and kv ~= "" then RI.keys[kk] = kv end
    end
    f:close()
end

-- a kill or a full disk mid-write must not leave a truncated state file
local function write_atomic(path, text)
    local f = io.open(path .. ".tmp", "w")
    if not f then return end
    f:write(text)
    f:close()
    os.rename(path .. ".tmp", path)
end

local function save()
    local s = string.format("on=%d\nws=%s\nz=%.5f\nox=%.2f\noy=%.2f\nsig=%s\n", RI.on and 1 or 0, shared() and "all" or tostring(RI.ws or ""), RI.z, RI.ox, RI.oy,
        os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "")
    for a in pairs(RI.tiled) do s = s .. "tiled=" .. a .. "\n" end
    write_atomic(STATE, s)
end

local function active_ws()
    local ws = hl.get_active_workspace()
    return ws and ws.id or nil
end

-- the windows of the canvas workspace that can be moved
-- pop-ups that belong to an app and are not windows of the canvas (Steam's notification toasts and the like): they
-- stay where the app put them, like a pinned window. Moving or focusing them moved the whole canvas instead.
local OVERLAY_TITLE = { "^notificationtoasts_" }
local function overlay(w)
    local t = tostring(w and w.title or "")
    for _, pat in ipairs(OVERLAY_TITLE) do
        if t:match(pat) then return true end
    end
    return false
end

local function each_window(fn)
    local ok, list = pcall(hl.get_windows)
    if ok and type(list) == "table" then for _, w in ipairs(list) do fn(w) end end
end

-- every screen: only the workspace each screen shows (V5.02: the windows of every other workspace were taken too)
local function shown(w, wsid)
    local m = w.monitor
    local aw = type(m) == "table" and (m.active_workspace or m.activeWorkspace) or nil
    local id = type(aw) == "table" and aw.id or aw
    if id == nil then return true end
    return tonumber(id) == tonumber(wsid)
end

local function wins()
    local out = {}
    local ok, list = pcall(hl.get_windows)
    if not ok or type(list) ~= "table" then return out end
    local all = shared()
    for _, w in pairs(list) do
        local wsid = w.workspace and w.workspace.id
        if wsid ~= nil and ((all and shown(w, wsid)) or wsid == RI.ws) and w.mapped ~= false and not w.hidden and (tonumber(w.fullscreen) or 0) == 0
            and not w.pinned and not overlay(w) and w.at and w.size then
            out[#out + 1] = w
        end
    end
    return out
end

-- where a window is on the canvas. Its place always comes from where it is on the screen now (Hyprland gives the
-- place a window is going to), so a window you moved yourself never jumps back; its size is kept
local function canvas(w)
    local s = RI.world[w.address]
    local x, y = (w.at.x - RI.ox) / RI.z, (w.at.y - RI.oy) / RI.z
    if not s then
        s = { x = x, y = y, w = w.size.x / RI.z, h = w.size.y / RI.z }
        RI.world[w.address] = s
    elseif not (s.tx and math.abs(w.at.x - s.tx) <= 2 and math.abs(w.at.y - s.ty) <= 2) then
        -- (where we put it ourselves: keep the exact value, no rounding creeping in)
        s.x, s.y = x, y
    end
    return s
end

local function place(w, s, resize)
    s.tx, s.ty = math.floor(RI.ox + s.x * RI.z + 0.5), math.floor(RI.oy + s.y * RI.z + 0.5)
    if resize then
        run(hl.dsp.window.resize({ x = math.max(60, math.floor(s.w * RI.z + 0.5)), y = math.max(40, math.floor(s.h * RI.z + 0.5)), window = sel(w) }))
    end
    run(hl.dsp.window.move({ x = math.floor(RI.ox + s.x * RI.z + 0.5), y = math.floor(RI.oy + s.y * RI.z + 0.5), window = sel(w) }))
end

-- a place that would land outside its screen is brought back on it. A window given its place while the canvas was
-- panned has canvas numbers that mean nothing once the view is back at 100 %; without this it was put outside the
-- screen and looked gone after turning Infinite Desktop off. V7.16: a place that only stuck out a little (the usual
-- case for a floating window such as Settings) was left half off the screen and looked gone too, so the whole
-- rectangle is kept inside the monitor now, not just its top-left corner.
local function visible_place(w, s)
    local m = w.monitor
    if type(m) ~= "table" or not m.width then m = hl.get_active_monitor() end
    if type(m) ~= "table" or not m.width then return s end
    local sc = tonumber(m.scale) or 1
    if sc <= 0 then sc = 1 end
    local W, H = (tonumber(m.width) or 1920) / sc, (tonumber(m.height) or 1080) / sc
    local r = m.reserved or {}
    local l, t = (tonumber(m.x) or 0) + (tonumber(r.left) or 0), (tonumber(m.y) or 0) + (tonumber(r.top) or 0)
    local rr, bb = (tonumber(m.x) or 0) + W - (tonumber(r.right) or 0), (tonumber(m.y) or 0) + H - (tonumber(r.bottom) or 0)
    local sw, sh = (tonumber(s.w) or 400) * RI.z, (tonumber(s.h) or 300) * RI.z
    local x, y = RI.ox + s.x * RI.z, RI.oy + s.y * RI.z
    local pad = 24
    local nx, ny = x, y
    if sw > rr - l - 2 * pad then nx = l + (rr - l - sw) / 2
    else nx = math.max(l + pad, math.min(rr - pad - sw, x)) end
    if sh > bb - t - 2 * pad then ny = t + (bb - t - sh) / 2
    else ny = math.max(t + pad, math.min(bb - pad - sh, y)) end
    if math.abs(nx - x) > 0.5 or math.abs(ny - y) > 0.5 then
        s.x, s.y = (nx - RI.ox) / RI.z, (ny - RI.oy) / RI.z
        s.tx, s.ty = nil, nil
    end
    return s
end

local function here()
    return RI.on and (shared() or active_ws() == RI.ws)
end

function RI.zoom_to(nz, cx, cy)
    if not here() then return end
    local list = wins()
    for _, w in ipairs(list) do canvas(w) end
    nz = math.max(RI.cfg.min, math.min(RI.cfg.max, nz))
    if math.abs(nz - RI.z) < 0.0005 then return end
    if not cx then
        local c = hl.get_cursor_pos()
        cx, cy = c.x, c.y
    end
    -- the point under the pointer stays under the pointer
    local wx, wy = (cx - RI.ox) / RI.z, (cy - RI.oy) / RI.z
    RI.z = nz
    RI.ox, RI.oy = cx - wx * nz, cy - wy * nz
    for _, w in ipairs(list) do place(w, RI.world[w.address], true) end
    save()
end

-- dir > 0: closer (bigger), dir < 0: farther away (smaller)
function RI.zoom(dir)
    local f = 1 + RI.cfg.step
    RI.zoom_to(dir > 0 and RI.z * f or RI.z / f)
end

-- while the canvas is dragged with the mouse, Hyprland's own windowMove animation would chase each 16 ms target and
-- lag behind it (the windows moved in visible steps). It is turned off for the drag and put back afterwards
local liveMove = false
local function live_anim(on)
    pcall(hl.animation, { leaf = "windowsMove", enabled = not on, speed = 3, bezier = "quick" })
end

-- live: many small moves in a row (SUPER + ALT + mouse); the place is written down once at the end (RI.save)
function RI.pan(dx, dy, live)
    if not here() then return end
    local list = wins()
    for _, w in ipairs(list) do canvas(w) end
    RI.ox, RI.oy = RI.ox + dx, RI.oy + dy
    for _, w in ipairs(list) do place(w, RI.world[w.address], false) end
    if not live then save() end
end

function RI.save()
    if liveMove then liveMove = false; live_anim(false) end
    save()
end

-- the floating windows of the workspace you are on (for SUPER + ALT while Infinite Desktop is off)
local function floats_here()
    local out, ws = {}, active_ws()
    local ok, list = pcall(hl.get_windows)
    if not ok or type(list) ~= "table" or ws == nil then return out end
    for _, w in pairs(list) do
        if w.floating and w.workspace and w.workspace.id == ws and w.mapped ~= false and not w.hidden
            and (tonumber(w.fullscreen) or 0) == 0 and not w.pinned and not overlay(w) and w.at then
            out[#out + 1] = w
        end
    end
    return out
end

local function nudge(list, dx, dy, skip)
    for _, w in ipairs(list) do
        if w.address ~= skip then
            run(hl.dsp.window.move({ x = math.floor(w.at.x + dx), y = math.floor(w.at.y + dy), window = sel(w) }))
        end
    end
end

-- SUPER + ALT + mouse (the timer below, or rice-canvasd before 0.56): the canvas, or with Infinite Desktop off the
-- floating windows here
function RI.slide(dx, dy)
    if here() then
        if not liveMove then liveMove = true; live_anim(true) end
        RI.pan(dx, dy, true)
    else
        nudge(floats_here(), dx, dy)
    end
end

-- ---------- the mouse without the input group (Hyprland 0.56+) ----------
-- Hyprland cannot hand a config the mouse movement, but it can tell it which keys are held and where the pointer is.
-- A timer reads both: the canvas moves by how far the pointer went, and the wallpaper and the bar follow through
-- a small file in the runtime folder (Infinite.qml reads it; the same state rice-canvasd sends over its socket).
local MODS = {
    SUPER = "SUPER", WIN = "SUPER", LOGO = "SUPER", META = "SUPER", MOD4 = "SUPER",
    ALT = "ALT", MOD1 = "ALT", CTRL = "CTRL", CONTROL = "CTRL", SHIFT = "SHIFT",
}
local SYMS = {
    SUPER = { "Super_L", "Super_R" }, ALT = { "Alt_L", "Alt_R" },
    CTRL = { "Control_L", "Control_R" }, SHIFT = { "Shift_L", "Shift_R" },
}
local HOLD, HOLD_SET = nil, {}   -- the keysyms to check, and the modifiers they are (SHIFT may always come along)

-- "SUPER + ALT" -> { { "Super_L", "Super_R" }, { "Alt_L", "Alt_R" } }; a key this does not know: no pointer
local function hold_parse()
    HOLD, HOLD_SET = nil, {}
    if not CAN_POLL then return end
    local out, seen = {}, {}
    for part in (RI.keys.mod_hold or ""):gmatch("[^+]+") do
        local name = MODS[part:gsub("%s", ""):upper()]
        if not name then return end
        HOLD_SET[name] = true
        if not seen[name] then seen[name] = true; out[#out + 1] = SYMS[name] end
    end
    if #out > 0 then HOLD = out end
end

local function key_down(name)
    for _, s in ipairs(SYMS[name]) do
        local ok, down = pcall(hl.is_key_down, s)
        if ok and down then return true end
    end
    return false
end

-- exactly the hold keys (SHIFT may come along, like rice-canvasd): SUPER, ALT or CTRL stop it when not asked for
local function hold_down()
    if not HOLD then return false end
    for _, list in ipairs(HOLD) do
        local any = false
        for _, s in ipairs(list) do
            local ok, down = pcall(hl.is_key_down, s)
            if ok and down then any = true; break end
        end
        if not any then return false end
    end
    for _, name in ipairs({ "SUPER", "ALT", "CTRL" }) do
        if not HOLD_SET[name] and key_down(name) then return false end
    end
    return true
end

-- the pointer stops at the edge of the screen. 24 px inside it is put back, so the canvas goes on: you keep pushing,
-- the pointer stays near the edge (the movement past the edge is lost, nothing else)
local BAND = 24
local function warp_target(p, dx, dy)
    if not CAN_WARP then return nil end
    local ok, m = pcall(hl.get_monitor_at, p.x, p.y)
    if not ok or type(m) ~= "table" then return nil end
    local sc = tonumber(m.scale) or 1
    if sc <= 0 then sc = 1 end
    local l, t = tonumber(m.x) or 0, tonumber(m.y) or 0
    local w, h = tonumber(m.width) or 1920, tonumber(m.height) or 1080
    if (tonumber(m.transform) or 0) % 2 == 1 then w, h = h, w end     -- turned by 90°: the sides swap
    local r, b = l + w / sc, t + h / sc
    local x, y = p.x, p.y
    if dx > 0 and x > r - BAND and r - BAND > l then x = r - BAND
    elseif dx < 0 and x < l + BAND and l + BAND < r then x = l + BAND end
    if dy > 0 and y > b - BAND and b - BAND > t then y = b - BAND
    elseif dy < 0 and y < t + BAND and t + BAND < b then y = t + BAND end
    if x ~= p.x or y ~= p.y then return x, y end
    return nil
end

-- hold 1 + where the canvas is (absolute: a write the shell misses loses nothing), or hold 0
local function live_write(held)
    if held and not RI.on then return end
    local f = io.open(LIVE, "w")
    if not f then return end
    if held then
        f:write(string.format("hold 1\nox=%.2f\noy=%.2f\n", RI.ox, RI.oy))
    else
        f:write("hold 0\n")
    end
    f:close()
end

local function live_off()
    live_write(false)
end

local poll = { last = nil, held = false, ax = 0, ay = 0, wait = 0 }

-- The pointer is put back inside the edge on every tick, so it drifts away from it for one tick only: at 16 ms that
-- was 5-16 px of shake at the edge, easy to see; at 1 ms it is under a pixel at any speed you pan at. The canvas still
-- moves every 16 ms (moving every window a thousand times a second would be a lot of work for nothing).
local TICK_IDLE, TICK_FAST = 16, 1
local TIMER, TICK_MS = nil, TICK_IDLE

local function tick_rate(ms)
    TICK_MS = ms
    if TIMER then pcall(TIMER.set_timeout, TIMER, ms) end
end

local function cursor_pos()
    local ok, p = pcall(hl.get_cursor_pos)
    if ok and type(p) == "table" and p.x and p.y then return { x = p.x, y = p.y } end
    return nil
end

local function tick()
    poll.wait = poll.wait + TICK_MS
    local step = poll.wait >= TICK_IDLE     -- the keys, and the canvas: every 16 ms
    if step then poll.wait = 0 end

    if step then
        local down = hold_down()
        if down ~= poll.held then
            poll.held = down
            poll.last, poll.ax, poll.ay = nil, 0, 0
            if down then poll.last = cursor_pos() end
            tick_rate(down and TICK_FAST or TICK_IDLE)
            live_write(down)
            if not down then pcall(RI.save) end     -- the place is written down once, at the end
            return
        end
        if not down then return end
    end
    if not poll.held then return end

    local p = cursor_pos()
    if not p then return end
    if not poll.last then poll.last = p; return end
    local dx, dy = p.x - poll.last.x, p.y - poll.last.y
    poll.last = p
    local sp = math.max(0.1, math.min(5.0, tonumber(RI.cfg.speed) or 1.0))
    poll.ax, poll.ay = poll.ax + dx * sp, poll.ay + dy * sp
    local wx, wy = warp_target(p, dx, dy)
    if wx then
        run(hl.dsp.cursor.move({ x = wx, y = wy }))
        -- the pointer is there now: the jump itself is not movement (else the canvas would jump back by it)
        poll.last = { x = wx, y = wy }
    end
    if not step then return end

    local sign = tonumber(RI.cfg.dir) == 2 and -1 or 1
    -- whole pixels now, the rest kept: a slow move is not lost (the same as rice-canvasd)
    local ix = poll.ax >= 0 and math.floor(poll.ax) or math.ceil(poll.ax)
    local iy = poll.ay >= 0 and math.floor(poll.ay) or math.ceil(poll.ay)
    poll.ax, poll.ay = poll.ax - ix, poll.ay - iy
    -- never more than a big step at once: a hiccup is caught up smoothly, not in one jump
    local cx = math.max(-160, math.min(160, ix))
    local cy = math.max(-160, math.min(160, iy))
    poll.ax, poll.ay = poll.ax + (ix - cx), poll.ay + (iy - cy)
    if cx ~= 0 or cy ~= 0 then
        RI.slide(cx * sign, cy * sign)
        pcall(live_write, true)
    end
end

-- the middle of the usable part of the screen (logical pixels, without the bar)
local function middle()
    -- the screen the pointer is on (a window opens where the mouse is), or else the one you are working on
    local c = hl.get_cursor_pos()
    local m = c and hl.get_monitor_at(c.x, c.y) or hl.get_active_monitor()
    if not m then return 960, 540, 1920, 1080 end
    local sc = (tonumber(m.scale) or 1)
    if sc <= 0 then sc = 1 end
    local W, H = (m.width or 1920) / sc, (m.height or 1080) / sc
    local r = m.reserved or {}
    local l, t, rr, b = tonumber(r.left) or 0, tonumber(r.top) or 0, tonumber(r.right) or 0, tonumber(r.bottom) or 0
    return (m.x or 0) + l + (W - l - rr) / 2, (m.y or 0) + t + (H - t - b) / 2, W - l - rr, H - t - b
end

-- on every screen: move the canvas only as far as the new window needs to be in sight of its own screen
local function reveal(s, m)
    if not (s and m) then return end
    local sc = tonumber(m.scale) or 1
    if sc <= 0 then sc = 1 end
    local W, H = (m.width or 1920) / sc, (m.height or 1080) / sc
    local r = m.reserved or {}
    local l, t = (m.x or 0) + (tonumber(r.left) or 0), (m.y or 0) + (tonumber(r.top) or 0)
    local rr, b = (m.x or 0) + W - (tonumber(r.right) or 0), (m.y or 0) + H - (tonumber(r.bottom) or 0)
    local x, y = RI.ox + s.x * RI.z, RI.oy + s.y * RI.z
    local x2, y2 = x + s.w * RI.z, y + s.h * RI.z
    local dx = 0
    if x < l then dx = l - x elseif x2 > rr then dx = rr - x2 end
    local dy = 0
    if y < t then dy = t - y elseif y2 > b then dy = b - y2 end
    if dx ~= 0 or dy ~= 0 then RI.pan(math.floor(dx + 0.5), math.floor(dy + 0.5)) end
end

-- glide the canvas so that this canvas point is in the middle of the screen (Hyprland animates the moves)
local function center_on(cx, cy, list)
    local mx, my = middle()
    local nox, noy = mx - cx * RI.z, my - cy * RI.z
    if math.abs(nox - RI.ox) + math.abs(noy - RI.oy) < 1 then return end
    RI.ox, RI.oy = nox, noy
    for _, w in ipairs(list) do
        local s = RI.world[w.address]
        if s then place(w, s, false) end
    end
end

local function focus(w)
    run(hl.dsp.focus({ window = sel(w) }))
end

local function overlaps(a, list, skip)
    for addr, b in pairs(list) do
        if addr ~= skip and a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then return true end
    end
    return false
end

-- a free place on the canvas next to the window you were in (to the right, then below, then left, then above)
local function room(from, w, h)
    local gap = 40
    if not from then
        local mx, my = middle()
        return (mx - RI.ox) / RI.z - w / 2, (my - RI.oy) / RI.z - h / 2
    end
    local tries = {
        function(k) return from.x + from.w + gap + k * (w + gap), from.y end,
        function(k) return from.x, from.y + from.h + gap + k * (h + gap) end,
        function(k) return from.x - w - gap - k * (w + gap), from.y end,
        function(k) return from.x, from.y - h - gap - k * (h + gap) end,
    }
    for k = 0, 12 do
        for _, f in ipairs(tries) do
            local x, y = f(k)
            if not overlaps({ x = x, y = y, w = w, h = h }, RI.world, nil) then return x, y end
        end
    end
    return from.x + from.w + gap, from.y
end

-- SUPER + CTRL + arrows: the nearest window that way, brought to the middle
function RI.go(dir)
    if not here() then return end
    local list = wins()
    local a = hl.get_active_window()
    local cx, cy
    if a and a.at and a.size and a.workspace and (shared() or a.workspace.id == RI.ws) then
        cx, cy = a.at.x + a.size.x / 2, a.at.y + a.size.y / 2
    else
        cx, cy = middle()
    end
    local best, bestd
    for _, w in ipairs(list) do
        if not (a and w.address == a.address) then
            local dx, dy = w.at.x + w.size.x / 2 - cx, w.at.y + w.size.y / 2 - cy
            local along, across
            if dir == "right" then along, across = dx, dy
            elseif dir == "left" then along, across = -dx, dy
            elseif dir == "down" then along, across = dy, dx
            else along, across = -dy, dx end
            if along > 1 then
                local d = along + 2 * math.abs(across)
                if not bestd or d < bestd then best, bestd = w, d end
            end
        end
    end
    if not best then return end
    -- the middle of that window goes to the middle of the screen: the whole canvas glides by that much
    local mx, my = middle()
    RI.pan(math.floor(mx - (best.at.x + best.size.x / 2) + 0.5), math.floor(my - (best.at.y + best.size.y / 2) + 0.5))
    focus(best)
end

-- a window that opened on the canvas: float it, give it its own room next to the last one, glide there
function RI.opened(w)
    if not RI.on then return end
    if not (w and w.workspace and (shared() or w.workspace.id == RI.ws)) then return end
    if overlay(w) then return end
    if not w.floating then
        -- it would have been tiled: it tiles again when Infinite Desktop is turned off
        RI.tiled[w.address] = true
        run(hl.dsp.window.float({ action = "set", window = sel(w) }))
    end
    local list = wins()
    local lastAddr = (RI.last ~= w.address) and RI.last or RI.prev
    local from = lastAddr and RI.world[lastAddr]
    for _, o in ipairs(list) do
        if o.address ~= w.address then canvas(o) end
    end
    if lastAddr and not RI.world[lastAddr] then from = nil end
    -- on every screen: the last window only when it is on the same screen, else the middle of this one
    if shared() and from and w.monitor then
        local lw
        for _, o in ipairs(list) do if o.address == lastAddr then lw = o end end
        local lm = lw and lw.monitor
        if not (lm and lm.name and lm.name == w.monitor.name) then from = nil end
    end
    local _, _, W, H = middle()
    local nw = from and from.w or (W * 0.6) / RI.z
    local nh = from and from.h or (H * 0.7) / RI.z
    local x, y = room(from, nw, nh)
    RI.world[w.address] = { x = x, y = y, w = nw, h = nh }
    local fresh = {}
    for _, o in ipairs(wins()) do fresh[#fresh + 1] = o end
    for _, o in ipairs(fresh) do
        if o.address == w.address then place(o, RI.world[o.address], true) end
    end
    if shared() and w.monitor then
        reveal(RI.world[w.address], w.monitor)
    else
        center_on(x + nw / 2, y + nh / 2, fresh)
    end
    focus(w)
    if RI.last ~= w.address then RI.prev = RI.last end
    RI.last = w.address
    save()
end

-- SUPER + dragging a window against the edge of the screen: the other windows move away, so it can go on
function RI.edge_push(dx, dy)
    local a = hl.get_active_window()
    if not (a and a.at and a.floating) then return end
    -- only when the pointer is at the edge of the screen and the mouse goes on that way: the window you hold
    -- cannot go further, so the others come towards it
    local m = hl.get_active_monitor()
    local c = hl.get_cursor_pos()
    if not (m and c) then return end
    local sc = tonumber(m.scale) or 1
    if sc <= 0 then sc = 1 end
    local l, t = m.x or 0, m.y or 0
    local r, b = l + (m.width or 1920) / sc, t + (m.height or 1080) / sc
    local px, py = 0, 0
    if (dx < 0 and c.x <= l + 2) or (dx > 0 and c.x >= r - 3) then px = -dx end
    if (dy < 0 and c.y <= t + 2) or (dy > 0 and c.y >= b - 3) then py = -dy end
    if px == 0 and py == 0 then return end
    if not here() then
        nudge(floats_here(), px, py, a.address)
        return
    end
    local list = wins()
    for _, w in ipairs(list) do canvas(w) end
    RI.ox, RI.oy = RI.ox + px, RI.oy + py
    for _, w in ipairs(list) do
        if w.address ~= a.address then place(w, RI.world[w.address], false) end
    end
    -- the window you hold stays under the pointer: its place on the canvas moved
    local s = RI.world[a.address]
    if s then s.x, s.y = (a.at.x - RI.ox) / RI.z, (a.at.y - RI.oy) / RI.z; s.tx = nil end
end

-- rice-canvasd: the push at the edge while SUPER + drag (and, before 0.56, SUPER + ALT + mouse): it reads the mouse,
-- Hyprland cannot tell a config how far the pointer went past the edge of the screen
local function daemon()
    run(hl.dsp.exec_cmd(HOME .. "/.local/bin/rice-infinite daemon" .. (CAN_POLL and " push" or "")))
end

local function notify(text)
    run(hl.dsp.exec_cmd("command -v notify-send >/dev/null && notify-send -t 1600 -a 'Infinite Desktop' 'Infinite Desktop' '" .. text .. "'"))
end

-- keys that only exist while it is on (CTRL + wheel goes back to your apps when it is off). Made from your keys
local KEYS = {}
local function k(mod, key) return mod .. " + " .. key end

bind_keys = function()
    local p = function() return RI.cfg.pan end
    local K = RI.keys
    local hold, go, zoom = K.mod_hold, K.mod_go, K.mod_zoom
    KEYS = { k(zoom, "mouse_down"), k(zoom, "mouse_up"), "SUPER + SHIFT + mouse_down", "SUPER + SHIFT + mouse_up",
        k(hold, "left"), k(hold, "right"), k(hold, "up"), k(hold, "down"), k(hold, "0"),
        k(go, "left"), k(go, "right"), k(go, "up"), k(go, "down") }
    pcall(hl.unbind, "SUPER + mouse_down")
    pcall(hl.unbind, "SUPER + mouse_up")
    pcall(hl.bind, k(zoom, "mouse_down"), function() RI.zoom(-1) end)
    pcall(hl.bind, k(zoom, "mouse_up"), function() RI.zoom(1) end)
    pcall(hl.bind, "SUPER + mouse_down", function() RI.pan(0, -p()) end)
    pcall(hl.bind, "SUPER + mouse_up", function() RI.pan(0, p()) end)
    pcall(hl.bind, "SUPER + SHIFT + mouse_down", function() RI.pan(-p(), 0) end)
    pcall(hl.bind, "SUPER + SHIFT + mouse_up", function() RI.pan(p(), 0) end)
    pcall(hl.bind, k(hold, "left"), function() RI.pan(p(), 0) end, { repeating = true })
    pcall(hl.bind, k(hold, "right"), function() RI.pan(-p(), 0) end, { repeating = true })
    pcall(hl.bind, k(hold, "up"), function() RI.pan(0, p()) end, { repeating = true })
    pcall(hl.bind, k(hold, "down"), function() RI.pan(0, -p()) end, { repeating = true })
    pcall(hl.bind, k(hold, "0"), function() RI.zoom_to(1.0) end)
    pcall(hl.bind, k(go, "left"), function() RI.go("left") end)
    pcall(hl.bind, k(go, "right"), function() RI.go("right") end)
    pcall(hl.bind, k(go, "up"), function() RI.go("up") end)
    pcall(hl.bind, k(go, "down"), function() RI.go("down") end)
end

unbind_keys = function()
    for _, key in ipairs(KEYS) do pcall(hl.unbind, key) end
    pcall(hl.unbind, "SUPER + mouse_down")
    pcall(hl.unbind, "SUPER + mouse_up")
    -- the normal SUPER + wheel: next / previous workspace
    pcall(hl.bind, "SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
    pcall(hl.bind, "SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))
end

-- the on / off key (yours, SUPER + F by default)
local toggle_key = nil
local function bind_toggle()
    if toggle_key then pcall(hl.unbind, toggle_key) end
    toggle_key = RI.keys.key_toggle
    pcall(hl.bind, toggle_key, function() RI.toggle() end)
end

-- after Settings changed something
function RI.reload()
    if liveMove then liveMove = false; live_anim(false) end
    if RI.on then for _, key in ipairs(KEYS) do pcall(hl.unbind, key) end end
    local was = shared()
    pcall(RI.load_cfg)
    pcall(hold_parse)
    -- the keys may be other ones now: a hold from before is not one
    poll.last, poll.ax, poll.ay, poll.held, poll.wait = nil, 0, 0, false, 0
    tick_rate(TICK_IDLE)
    pcall(bind_toggle)
    if RI.on then bind_keys() end
    -- every screen <-> this workspace: the windows of a screen that joins float too (the ones that leave are still
    -- tiled again when it is turned off)
    if RI.on and shared() ~= was and RI.ws ~= nil then
        for _, w in ipairs(wins()) do
            canvas(w)
            if not w.floating then
                RI.tiled[w.address] = true
                run(hl.dsp.window.float({ action = "set", window = sel(w) }))
            end
        end
        save()
    end
end

-- ---------- the canvas of each workspace is remembered (turn it off and on: everything is where you left it) ----------
RI.layouts = {}     -- workspace id -> { z, ox, oy, wins = { { a = address, c = class, x, y, w, h }, ... } }

local function clean(t)
    return (tostring(t or ""):gsub("[|\n]", " "))
end

local function write_layouts()
    local out = {}
    for ws, l in pairs(RI.layouts) do
        out[#out + 1] = string.format("ws|%s|%.5f|%.2f|%.2f\n", tostring(ws), l.z, l.ox, l.oy)
        for _, e in ipairs(l.wins) do
            out[#out + 1] = string.format("win|%s|%s|%s|%.2f|%.2f|%.2f|%.2f\n", tostring(ws), clean(e.a), clean(e.c), e.x, e.y, e.w, e.h)
        end
    end
    write_atomic(LAYOUT, table.concat(out))
end

local function read_layouts()
    local f = io.open(LAYOUT, "r")
    if not f then return end
    for line in f:lines() do
        local p = {}
        for v in (line .. "|"):gmatch("([^|]*)|") do p[#p + 1] = v end
        if p[1] == "ws" and #p >= 5 then
            local ws = tonumber(p[2]) or p[2]
            RI.layouts[ws] = { z = tonumber(p[3]) or 1, ox = tonumber(p[4]) or 0, oy = tonumber(p[5]) or 0, wins = {} }
        elseif p[1] == "win" and #p >= 8 then
            local l = RI.layouts[tonumber(p[2]) or p[2]]
            if l then
                l.wins[#l.wins + 1] = { a = p[3], c = p[4], x = tonumber(p[5]) or 0, y = tonumber(p[6]) or 0,
                    w = tonumber(p[7]) or 400, h = tonumber(p[8]) or 300 }
            end
        end
    end
    f:close()
end

local function class_of(w)
    return clean(w.class or w.initialClass or w.initial_class or "")
end

-- before turning off: where every window of the canvas is on it
local function key()
    return shared() and "all" or RI.ws
end

local function remember()
    local k = key()
    if k == nil then return end
    local l = { z = RI.z, ox = RI.ox, oy = RI.oy, wins = {} }
    for _, w in ipairs(wins()) do
        local s = canvas(w)
        l.wins[#l.wins + 1] = { a = w.address, c = class_of(w), x = s.x, y = s.y, w = s.w, h = s.h }
    end
    RI.layouts[k] = l
    write_layouts()
end

-- after turning on: the windows go back to their places (the same window, or else one of the same app)
local function bring_back()
    local l = RI.layouts[key()]
    if not l then return false end
    RI.z, RI.ox, RI.oy = l.z, l.ox, l.oy
    local used = {}
    local function find(w)
        for i, e in ipairs(l.wins) do
            if not used[i] and e.a == w.address then used[i] = true; return e end
        end
        local c = class_of(w)
        if c == "" then return nil end
        for i, e in ipairs(l.wins) do
            if not used[i] and e.c == c then used[i] = true; return e end
        end
        return nil
    end
    local list = wins()
    local fresh = {}
    for _, w in ipairs(list) do
        local e = find(w)
        if e then
            RI.world[w.address] = { x = e.x, y = e.y, w = e.w, h = e.h }
        else
            fresh[#fresh + 1] = w
        end
    end
    -- a window that was not there before keeps its place on the screen
    for _, w in ipairs(fresh) do
        local o = RI.world[w.address]
        if o then RI.world[w.address] = { x = (o.x - RI.ox) / RI.z, y = (o.y - RI.oy) / RI.z, w = o.w / RI.z, h = o.h / RI.z } end
    end
    for _, w in ipairs(list) do
        local s = RI.world[w.address]
        if s then place(w, visible_place(w, s), true) end
    end
    return true
end

pcall(read_layouts)

function RI.set(on)
    on = on and true or false
    if on == RI.on then return end
    if on then
        RI.ws = active_ws()
        if RI.ws == nil then return end
        RI.z, RI.ox, RI.oy, RI.world, RI.tiled = 1.0, 0, 0, {}, {}
        local list = wins()
        for _, w in ipairs(list) do
            RI.world[w.address] = { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
            if not w.floating then
                RI.tiled[w.address] = true
                run(hl.dsp.window.float({ action = "set", window = sel(w) }))
            end
        end
        RI.on = true
        -- it had a canvas before (every screen, or this workspace): everything back where you left it
        if not bring_back() then
            -- floating gives a window another size: put each one back where it was
            for _, w in ipairs(wins()) do
                local s = RI.world[w.address]
                if s and RI.tiled[w.address] then place(w, s, true) end
            end
        end
        local a = hl.get_active_window()
        RI.last = a and a.address or nil
        bind_keys()
        daemon()
        notify("On: hold " .. RI.keys.mod_hold .. " and move the mouse, " .. RI.keys.mod_zoom .. " + wheel to zoom")
        -- before 0.56 SUPER + ALT + mouse reads the mouse itself and cannot yet: say what the one step is
        if not CAN_POLL then run(hl.dsp.exec_cmd(HOME .. "/.local/bin/rice-canvasd --tell")) end
    else
        if liveMove then liveMove = false; live_anim(false) end
        if RI.ws ~= nil then
            pcall(remember)
            -- back to 100 % where everything started
            RI.z, RI.ox, RI.oy = 1.0, 0, 0
            each_window(function(w)
                local s = RI.world[w.address]
                if s and (shared() or (w.workspace and w.workspace.id == RI.ws)) then place(w, visible_place(w, s), true) end
                if RI.tiled[w.address] then run(hl.dsp.window.float({ action = "unset", window = sel(w) })) end
            end)
        end
        RI.on = false
        unbind_keys()
        pcall(live_off)
        notify("Off: windows are back")
    end
    save()
end

function RI.toggle()
    RI.set(not RI.on)
end

-- after a config reload: carry on where it was
local function restore()
    local f = io.open(STATE, "r")
    if not f then return end
    local st = { tiled = {} }
    for line in f:lines() do
        local k, v = line:match("^(%w+)=(.*)$")
        if k == "tiled" then st.tiled[v] = true elseif k then st[k] = v end
    end
    f:close()
    -- only after a config reload of this same session, not on the next login
    local sig = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""
    if st.on ~= "1" or sig == "" or st.sig ~= sig then
        if st.on == "1" then RI.on = false; save() end
        return
    end
    RI.on = true
    RI.ws = st.ws ~= "all" and (tonumber(st.ws) or st.ws) or active_ws()
    RI.z, RI.ox, RI.oy = tonumber(st.z) or 1.0, tonumber(st.ox) or 0, tonumber(st.oy) or 0
    RI.tiled = st.tiled
    RI.world = {}
    bind_keys()
    daemon()
end

pcall(RI.load_cfg)
pcall(hold_parse)
pcall(restore)

pcall(bind_toggle)

-- Settings reads this to know the mouse needs no input group here (the file names this Hyprland, so a leftover of
-- another session does not count)
pcall(function()
    if not CAN_POLL then os.remove(MARK); return end
    local f = io.open(MARK, "w")
    if f then f:write(os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or ""); f:close() end
end)
pcall(live_off)     -- a stale hold of a session that ended is not a hold now
-- the pointer itself (Hyprland 0.56+): a timer, not a process, and no permission
if CAN_POLL then
    local ok, t = pcall(hl.timer, function() pcall(tick) end, { timeout = TICK_IDLE, type = "repeat" })
    if ok then TIMER = t end
end

-- rice-canvasd runs with Hyprland (only one at a time; it stops when Hyprland stops); 0.56+ only for the push at the
-- edge, the mouse itself is the timer above
local CANVASD = HOME .. "/.local/bin/rice-infinite daemon" .. (CAN_POLL and " push" or "")
pcall(hl.on, "hyprland.start", function() pcall(hl.exec_cmd, CANVASD) end)
if (os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "") ~= "" then pcall(hl.exec_cmd, CANVASD) end

-- a window that opens on the canvas floats too
pcall(hl.on, "window.open", function(w) pcall(RI.opened, w) end)
pcall(hl.on, "window.close", function(w)
    if w and (RI.world[w.address] or RI.tiled[w.address]) then
        RI.world[w.address] = nil
        RI.tiled[w.address] = nil
        save()
    end
end)
-- the window you are in: new windows get their place next to it
pcall(hl.on, "window.active", function(w)
    if RI.on and w and w.address and w.workspace and (shared() or w.workspace.id == RI.ws) and w.address ~= RI.last then
        RI.prev = RI.last
        RI.last = w.address
    end
end)
