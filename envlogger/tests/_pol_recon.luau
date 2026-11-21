local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1k.lua"
local source = fs.readFile(path)
local t0 = os.clock()
local ok, res = pcall(function()
    return Sandbox.run(source, { timeout = tonumber(process.env.POLTIME or "45") })
end)
if not ok then
    print("RUN FAILED", tostring(res):sub(1, 500))
    return
end
print(string.format("wall=%.1fs exhausted=%s reason=%s outputs=%d stages=%d",
    os.clock() - t0, tostring(res.exhausted), tostring(res.exhaustedReason),
    #(res.outputs or {}), res.stages and #res.stages or 0))

local notes, strings = {}, {}
for _, rec in ipairs(res.trace.records) do
    if rec.kind == "note" then
        notes[#notes + 1] = tostring(rec.expression)
    elseif rec.kind == "string" and type(rec.value) == "string" and #rec.value > 3 then
        strings[#strings + 1] = rec.value
    end
end
print("== NOTES (" .. #notes .. ") ==")
for i = 1, math.min(#notes, 80) do print(notes[i]:sub(1, 300)) end
print("== LONG STRINGS (" .. #strings .. ") ==")
local seen = {}
for _, s in ipairs(strings) do
    if #s > 8 and not seen[s] then
        seen[s] = true
        print(string.format("[%d] %s", #s, s:sub(1, 400)))
    end
end
print("== OUTPUTS ==")
for _, o in ipairs(res.outputs or {}) do print(tostring(o):sub(1, 300)) end
