local Sandbox = require("../src/core/sandbox")
local Stdlib = require("../src/env/stdlib")
local fs = require("@lune/fs")
local source = fs.readFile("C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec_a.lua")
local t0 = os.clock()
local ok, res = pcall(function() return Sandbox.run(source, { timeout = 270 }) end)
print(string.format("wall=%.1fs ok=%s exhausted=%s reason=%s outputs=%d stages=%s",
    os.clock() - t0, tostring(ok), tostring(res.exhausted), tostring(res.exhaustedReason),
    #(res.outputs or {}), tostring(res.stages and #res.stages or 0)))
for _, rec in ipairs(res.trace.records) do
    if rec.kind == "note" then print("  note:", tostring(rec.expression):sub(1, 150)) end
end
print("  band=" .. tostring(Stdlib.__stats["bit32.band"]) .. " sub=" .. tostring(Stdlib.__stats["string.sub"]) ..
      " char=" .. tostring(Stdlib.__stats["string.char"]) .. " concat=" .. tostring(Stdlib.__stats["table.concat"]) ..
      " rep=" .. tostring(Stdlib.__stats["string.rep"]))
