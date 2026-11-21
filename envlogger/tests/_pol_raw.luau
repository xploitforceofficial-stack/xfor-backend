local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local t0 = os.clock()
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 25, noInstrument = true }) end)
print(string.format("raw wall=%.1fs ok=%s", os.clock() - t0, tostring(ok)))
if ok then
    for _, rec in ipairs(res.trace.records) do
        if rec.kind == "note" then print("   note:", tostring(rec.expression):sub(1, 150)) end
    end
end
print("   band=" .. tostring(Stdlib.__stats["bit32.band"]) .. " sub=" .. tostring(Stdlib.__stats["string.sub"]))
