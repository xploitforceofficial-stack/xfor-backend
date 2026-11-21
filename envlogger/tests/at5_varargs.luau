local Sandbox = require("../src/core/sandbox")
local src = [[
local function f1(...)
	return select("#", ...), ...
end
local count, first, second, third = f1("head", nil, "tail")
print("f1|", count, first, second, third)
local function f2()
	return 17, nil, 29
end
local rc = select("#", f2())
local a, b, c = f2()
print("f2|", rc, a, b, c)
local function pack(...) return table.pack(...) end
local p = pack(1, nil, 3)
print("pack|", p.n, p[1], p[3])
]]
local ok, res = pcall(Sandbox.run, src, { timeout = 30 })
if not ok then print("sandbox error:", tostring(res):sub(1,200)) return end
print("ok:", res.ok, "err:", res.err)
for _, e in ipairs(res.outputs or {}) do print("OUT|" .. tostring(e.text)) end
