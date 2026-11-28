#!/usr/bin/env python3
"""Checks for the rice-hotcorner helpers that need no desktop: a file name taken twice in one second, and the
Hyprland config swap. Runs anywhere and in CI on every push."""
import importlib.machinery
import importlib.util
import os
import tempfile

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
loader = importlib.machinery.SourceFileLoader("hotcorner", os.path.join(root, "bin", "rice-hotcorner"))
spec = importlib.util.spec_from_loader("hotcorner", loader)
hc = importlib.util.module_from_spec(spec)
loader.exec_module(hc)

tmp = tempfile.mkdtemp()

# two shots in one second: the second name is kept, not written over the first
first = os.path.join(tmp, "Screenshot.png")
open(first, "w").close()
assert hc.unique(first) == os.path.join(tmp, "Screenshot-2.png")
open(os.path.join(tmp, "Screenshot-2.png"), "w").close()
assert hc.unique(first) == os.path.join(tmp, "Screenshot-3.png")
free = os.path.join(tmp, "other.png")
assert hc.unique(free) == free
print("ok 1 - a taken name gets -2, a free one is kept")

# the hot corner line goes and the config is swapped in, never cut short
h = os.path.join(tmp, "hyprland.lua")
with open(h, "w") as f:
    f.write('general { }\nrequire("rice-hotcorner")\nbind = "x"\n')
hc.HLUA = h
hc.BLUR_LUA = os.path.join(tmp, "rice-hotcorner.lua")
hc.q = lambda *a: None
hc.apply_blur()
with open(h) as f:
    text = f.read()
assert 'require("rice-hotcorner")' not in text
assert "bind = " in text and text.startswith("general")
assert not os.path.exists(h + ".tmp")
print("ok 2 - the config keeps the rest and leaves no .tmp")
# two fast Keep Awake presses start one inhibitor, and the second press turns that one off
import threading
import time

pidf = os.path.join(tmp, "awake.pid")
hc.AWAKE_PID = pidf
hc.CACHE = tmp
hc.alive = lambda f, w="": int(open(f).read()) if os.path.exists(f) else 0
spawned = []


class FakeProc:
    pid = 999999          # an unrelated process: os.kill is stubbed below


hc.subprocess.Popen = lambda *a, **k: (time.sleep(0.25), spawned.append(1), FakeProc())[2]
hc.notify = lambda *a, **k: None
hc.os.kill = lambda *a: None

threads = [threading.Thread(target=hc.toggle_awake) for _ in range(2)]
for t in threads:
    t.start()
for t in threads:
    t.join()
assert len(spawned) == 1, "two fast presses started %d inhibitors" % len(spawned)
assert not os.path.exists(pidf), "the second press did not turn the first one off"
print("ok 3 - two fast Keep Awake presses start one inhibitor")
