local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local t0 = os.clock()
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 300, noInstrument = true }) end)
print(string.format("wall=%.0fs ok=%s exhausted=%s reason=%s outputs=%d decrypted=%s",
    os.clock() - t0, tostring(ok), tostring(res.exhausted), tostring(res.exhaustedReason),
    #(res.outputs or {}), tostring(res.decryptedStringCount)))
for _, rec in ipairs(res.trace.records) do
    if rec.kind == "note" then print("  note:", tostring(rec.expression):sub(1, 130)) end
end
local log = Stdlib.envCallLog()
print("  " .. log:sub(1, 32))
