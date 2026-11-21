local Sandbox = require("../src/core/sandbox")
local fs = require("@lune/fs")
local process = require("@lune/process")

local path = process.env.POLFILE or "C:/Users/Sandr/OneDrive/Desktop/OmniDBF/envlogger/tests/_polsec1k.lua"
local source = fs.readFile(path)
local t0 = os.clock()
local ok, res = pcall(function()
    return Sandbox.run(source, { timeout = tonumber(process.env.POLTIME or "60") })
end)
if not ok then print("RUN FAILED", tostring(res):sub(1, 500)); return end
print(string.format("wall=%.1fs exhausted=%s reason=%s outputs=%d",
    os.clock() - t0, tostring(res.exhausted), tostring(res.exhaustedReason), #(res.outputs or {})))

local kinds: { [string]: number } = {}
local strings: { [string]: number } = {}
local order: { string } = {}
for _, rec in ipairs(res.trace.records) do
    kinds[rec.kind] = (kinds[rec.kind] or 0) + 1
    local v = rec.value
    if type(v) == "string" and #v >= 4 then
        if strings[v] == nil then order[#order + 1] = v end
        strings[v] = (strings[v] or 0) + 1
    end
    if type(rec.expression) == "string" and #rec.expression >= 8 and rec.expression:find("[%a]") then
        local e = rec.expression
        if strings[e] == nil then order[#order + 1] = e end
        strings[e] = (strings[e] or 0) + 1
    end
end
print("== record kinds ==")
for k, n in pairs(kinds) do print(string.format("  %s = %d", k, n)) end

print("== decoded strings (>=6 chars) ==")
local count = 0
for _, s in ipairs(order) do
    if #s >= 6 then
        count += 1
        if count <= 300 then print(string.format("[%5d] %s", #s, s:sub(1, 300))) end
    end
end
print("total distinct >=6:", count)
print("== outputs ==")
for _, o in ipairs(res.outputs or {}) do print(tostring(o):sub(1, 500)) end
