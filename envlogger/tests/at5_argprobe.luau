local Sandbox = require("../src/core/sandbox")
local src = [[
local cases = {
	{ "setmetatable", function() return setmetatable() end },
	{ "tonumber", function() return tonumber() end },
	{ "tostring", function() return tostring() end },
	{ "rawset", function() return rawset() end },
	{ "rawget", function() return rawget() end },
	{ "assert", function() return assert() end },
	{ "type", function() return type() end },
	{ "next", function() return next() end },
	{ "typeof", function() return typeof() end },
	{ "rep", function() return string.rep() end },
	{ "concat", function() return table.concat() end },
	{ "getmetatable", function() return getmetatable() end },
	{ "insert", function() return table.insert() end },
	{ "format", function() return string.format() end },
	{ "gmatch", function() return string.gmatch() end },
	{ "char", function() return string.char(nil) end },
	{ "unpack", function() return table.unpack() end },
	{ "pack", function() return string.pack() end },
	{ "select", function() return select() end },
	{ "error", function() return error() end },
}
for _, case in ipairs(cases) do
	local ok, err = pcall(case[2])
	print(case[1] .. "|", tostring(ok), "|", tostring(err))
end
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 60 })
if not ok then print("sandbox error:", res) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
