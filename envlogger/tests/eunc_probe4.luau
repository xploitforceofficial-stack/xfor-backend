local fs = require("@lune/fs")
local Sandbox = require("../src/core/sandbox")

local source = [====[
local out = {}
local function log(s) out[#out+1] = s end

-- Heartbeat dt: does the callback receive dt? Is it a number 0<dt<1?
local dt
local rs = game:GetService("RunService")
local conn = rs.Heartbeat:Connect(function(d) dt = d; conn:Disconnect() end)
task.wait(0.2)
log("hb dt: " .. tostring(dt) .. " (type " .. type(dt) .. ")")

-- Heartbeat:Wait timing
local t0 = os.clock()
local w = rs.Heartbeat:Wait()
log("Wait returned " .. tostring(w) .. " elapsed " .. string.format("%.4f", os.clock() - t0))

-- ClassName not writable
local p = Instance.new("Part")
local okW = pcall(function() p.ClassName = "Folder" end)
log("write ClassName ok: " .. tostring(okW) .. " (expect false)")
log("ClassName after: " .. tostring(p.ClassName))

-- FindFirstChild not recursive by default
local f = Instance.new("Folder"); f.Name = "Root"
local inner = Instance.new("Folder"); inner.Name = "Inner"; inner.Parent = f
local deep = Instance.new("Part"); deep.Name = "Deep"; deep.Parent = inner
log("f:FindFirstChild('Deep'): " .. tostring(f:FindFirstChild("Deep")))
local rec = f:FindFirstChild("Deep", true)
log("recursive found: " .. tostring(rec) .. " inner: " .. tostring(f:FindFirstChild("Inner")))

-- random numeric index on Part
local okN = pcall(function() return p[77] end)
log("p[77] ok: " .. tostring(okN) .. " (expect false)")

-- ServiceAdded unique (chained on game)
log("game.ServiceAdded type: " .. type(game.ServiceAdded))
local okSA, sa = pcall(function() return game.ServiceAdded end)
log("pcall game.ServiceAdded: " .. tostring(okSA) .. " -> " .. tostring(sa))
if type(sa) == "userdata" or type(sa) == "table" then
	local a = sa:Connect(function() end)
	local b = sa:Connect(function() end)
	log("ServiceAdded a ~= b: " .. tostring(a ~= b))
	log("typeof a: " .. tostring(typeof(a)))
	a:Disconnect() b:Disconnect()
end

print(table.concat(out, "\n"))
]====]

local ok, res = pcall(Sandbox.run, source, { timeout = 60, maxNest = 1 })
if not ok then
	print("SANDBOX CRASH:", res)
	return
end
print("ok:", res.ok, "err:", tostring(res.err):sub(1, 300))
if type(res.outputs) == "table" then
	for _, item in res.outputs do
		print(if type(item) == "table" then tostring(item.text or item[1]) else tostring(item))
	end
end
