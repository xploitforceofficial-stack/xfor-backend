local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
local bad = {}
for k, v in pairs(e) do
  if type(v) == "function" then
    local ok = pcall(function() return v.FindFirstChild end)
    if not ok then bad[#bad+1] = k end
  end
end
table.sort(bad)
print("non-indexable env functions:", table.concat(bad, ", "))
]==]

local ok, res = pcall(Sandbox.run, src, { timeout = 20, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end
print("script ok:", res.ok, "err:", res.err)
for _, o in ipairs(res.outputs or {}) do
	print(o.channel .. "|", o.text)
end
