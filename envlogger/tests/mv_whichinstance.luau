local Sandbox = require("../src/core/sandbox")

local src = [==[
local e = getfenv()
local offenders = {}
local checked = 0
for k, v in pairs(e) do
  if type(v) == "userdata" then
    local ok, member = pcall(function() return v.FindFirstChild end)
    if ok and type(member) == "function" then
      checked += 1

      local okIdx = pcall(function() return member.FindFirstChild end)
      if not okIdx then
        offenders[#offenders+1] = k
      end
    end
  end
end
print("userdata with fn FFC:", checked)
print("OFFENDERS (raw fn members):", table.concat(offenders, ", "))
]==]

local ok, res = pcall(Sandbox.run, src, { timeout = 30, maxNest = 1 })
if not ok then
	print("sandbox failed:", res)
	return
end
print("script ok:", res.ok, "err:", res.err)
for _, o in ipairs(res.outputs or {}) do
	print(o.channel .. "|", string.sub(o.text, 1, 400))
end
