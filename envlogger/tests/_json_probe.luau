local Sandbox = require("../src/core/sandbox")

local src = [[
local body = '{"a":0,"b":0,"c":"No fingerprint found"}'
local hs = game:GetService("HttpService")
local data = hs:JSONDecode(body)
print("type:", type(data))
print("c:", tostring(data and data.c))
local data2 = hs.JSONDecode(body)
print("dotcall type:", type(data2))
print("dotcall c:", tostring(type(data2) == "table" and data2.c or "N/A"))
]]

local ok, res = pcall(function()
    return Sandbox.run(src, { timeout = 20 })
end)
if not ok then print("RUN FAILED", tostring(res)); return end
for _, o in ipairs(res.outputs or {}) do
    print(o.channel .. ": " .. tostring(o.text))
end
print("err:", tostring(res.err))
