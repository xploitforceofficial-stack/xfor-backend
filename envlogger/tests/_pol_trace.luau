local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 20 }) end)
print("ok=", tostring(ok), "trace.count=", tostring(res.trace and res.trace.count), "dropped=", tostring(res.trace and res.trace.dropped))
print("records=", tostring(res.trace and #res.trace.records))
local total = 0
local top = {}
for k, v in pairs(Stdlib.__stats) do total += v; top[#top + 1] = { k, v } end
table.sort(top, function(a, b) return a[2] > b[2] end)
print("total lib calls:", total)
for i = 1, math.min(#top, 10) do print("   " .. top[i][1] .. " = " .. top[i][2]) end
