"""The executor globals protected scripts branch on must answer as real values.

An unimplemented name comes back as an unknown proxy: truthy, and truthy on
every field read. That is the "wrong but truthy" stand-in my notes warn about -
it sends a script down a branch it should not take and then into a busy loop -
so the check is not "does it exist" but "does reading it give a real answer".

Two behaviours are load-bearing and were both got wrong once:
  - getupvalues reports nothing. Luau has no debug.getupvalue, and an empty list
    is both the only honest answer and the safe one: a "was I hooked?" check
    finds nothing and continues.
  - settings() reads truthy AND accepts a write. Scripts assign through it
    (`settings().Rendering.QualityLevel = "Level01"`), so an empty table (loses
    that block, v14.7 (3): 825 -> 799 statements) and __index returning true
    (cannot assign a field on a boolean) are both wrong.

Usage: python deobf/research/exec_globals_check.py
"""
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import harness

PROBE = r"""
local function w(k, v) warn("EXECPROBE", k, v) end
local up = 42
local function f() return up end
local names = getupvalues(f)
w("nUpvalues", #names)
w("up1", names[1])
local nm = getupvalue(f, 1)
w("getupvalue.name", nm)
w("nConstants", #getconstants(f))
w("settings.type", type(settings))
w("settings.callType", type(settings()))
w("settings.unknownTruthy", settings().SomeToggle and true or false)
w("settings.writeAccepted", pcall(function()
    settings().Rendering.QualityLevel = "Level01"
end))
w("settings.stable", settings().Rendering == settings().Rendering)
w("UserSettings.type", type(UserSettings()))
w("protect_gui.identity", protect_gui("gui") == "gui")
w("syn.protect_gui.identity", syn.protect_gui("gui") == "gui")
w("secret.isString", type(makesecret()) == "string")
"""

EXPECT = {

    "nUpvalues": "0",
    "up1": "nil",
    "getupvalue.name": "nil",
    "nConstants": "0",

    "settings.type": '"function"',
    "settings.callType": '"table"',
    "settings.unknownTruthy": "true",
    "settings.writeAccepted": "true",
    "settings.stable": "true",
    "UserSettings.type": '"table"',
    "protect_gui.identity": "true",
    "syn.protect_gui.identity": "true",
    "secret.isString": "true",
}

def main():
    hpath = os.path.join(tempfile.gettempdir(), "exec_globals_check.harness.luau")
    body, err = harness.run_once(harness.find_luau(), PROBE, {"time_budget": 30},
                                 hpath, 90, False)
    raw = harness.LAST_RAW[0]
    if body is None:
        print("NO BODY:", (err or "")[:600])
        print(raw[-1200:])
        return 1
    found = {}
    for m in re.finditer(r'warn\("EXECPROBE",\s*"([^"]+)",\s*([^)]*)\)', raw):
        found.setdefault(m.group(1), m.group(2).strip())

    bad = []
    for k, want in EXPECT.items():
        got = found.get(k)
        ok = got == want
        if not ok:
            bad.append(k)
        print("%-26s %-14s %s" % (k, got, "ok" if ok else "WANT " + want))
    print()
    print("%d/%d as expected" % (len(EXPECT) - len(bad), len(EXPECT)))
    return 1 if bad else 0

if __name__ == "__main__":
    raise SystemExit(main())
