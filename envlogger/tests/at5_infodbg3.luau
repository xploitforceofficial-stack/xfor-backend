local Sandbox = require("../src/core/sandbox")

local src = [[
local enumType = Enum.HumanoidRigType
local enumItem = enumType.R6
print("typeof IsA", typeof(enumItem.IsA), "type", type(enumItem.IsA))
local ok, s, l, nm = pcall(debug.info, enumItem.IsA, "sln")
print("IsA info", tostring(ok), tostring(s), tostring(l), tostring(nm))
print("typeof FromName", typeof(enumType.FromName))
local ok2, s2, l2, nm2 = pcall(debug.info, enumType.FromName, "sln")
print("FromName info", tostring(ok2), tostring(s2), tostring(l2), tostring(nm2))
local ok3, s3, l3, nm3 = pcall(debug.info, enumType.FromValue, "sln")
print("FromValue info", tostring(ok3), tostring(s3), tostring(l3), tostring(nm3))
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
