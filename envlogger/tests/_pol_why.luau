local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 180 }) end)
if not ok then print("RUN FAILED:", tostring(res)) return end
print("ok=", tostring(res.ok), "err=", tostring(res.err))
local outs = res.outputs or {}
print("outputs:", #outs)
for i = 1, math.min(#outs, 6) do print("  OUT", tostring(outs[i])) end
local notes = 0
for _, rec in ipairs(res.trace.records) do
    if rec.kind == "note" then
        notes += 1
        if notes <= 12 then print("NOTE:", tostring(rec.expression):sub(1, 200)) end
    end
end
print("notes:", notes, "records:", #res.trace.records)
print("ENVLOG TAIL:", Stdlib.envCallLog():sub(-2000))
