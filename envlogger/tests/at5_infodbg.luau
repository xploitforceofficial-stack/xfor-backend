_G.__FUHD_DBG_INFO = true
local Sandbox = require("../src/core/sandbox")

local src = [[
local folder = Instance.new("Folder")
local fn = folder.WaitForChild
print("CALLING INFO", typeof(fn))
local s, l, nm, p, v = debug.info(fn, "slnaf")
print("RESULT", tostring(s), tostring(l), "[" .. tostring(nm) .. "]", tostring(p), tostring(v))
local rng = Random.new(5)
local clone = rng.Clone
print("RNG CLONE", tostring(select(3, debug.info(clone, "sln"))))
local sig = folder.ChildRemoved
local conn = sig:Connect(function() end)
print("DISCONNECT", tostring(select(3, debug.info(conn.Disconnect, "sln"))))
]]

local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then
	print("sandbox error:", res)
	return
end
print("ok:", res.ok, "err:", res.err)
for _, entry in ipairs(res.outputs or {}) do
	print("OUT|" .. tostring(entry.text))
end
